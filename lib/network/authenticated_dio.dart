import 'package:dio/dio.dart';
import 'package:authflow/authflow.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../models/k_auth_exception.dart';

/// A ready-to-use Dio instance that automatically handles
/// attaching authentication tokens and retrying requests on 401 Unauthorized.
class AuthenticatedDio {
  final Dio dio;
  late final Dio _retryDio;
  final Duration clockSkewBuffer;

  AuthenticatedDio({
    required BaseOptions options,
    List<Interceptor>? additionalInterceptors,
    HttpClientAdapter? httpClientAdapter,
    this.clockSkewBuffer = const Duration(seconds: 30),
  }) : dio = Dio(options) {
    if (httpClientAdapter != null) {
      dio.httpClientAdapter = httpClientAdapter;
    }
    // Dedicated Dio instance for retrying failed requests.
    // Shares the exact same HttpClientAdapter and BaseOptions to reuse connections,
    // but intentionally omits QueuedInterceptorsWrapper to prevent re-entrant deadlocks.
    _retryDio = Dio(options)..httpClientAdapter = dio.httpClientAdapter;
    if (additionalInterceptors != null) {
      _retryDio.interceptors.addAll(additionalInterceptors);
    }

    _setupInterceptors(additionalInterceptors);
  }

  HttpClientAdapter get httpClientAdapter => dio.httpClientAdapter;
  set httpClientAdapter(HttpClientAdapter adapter) {
    dio.httpClientAdapter = adapter;
    _retryDio.httpClientAdapter = adapter;
  }

  /// Checks whether a JWT token is expired or within the [buffer] window
  /// (default 30 seconds) to guard against clock skew and network transit latency.
  static bool isJwtExpired(String token, {Duration buffer = const Duration(seconds: 30)}) {
    try {
      final expirationDate = JwtDecoder.getExpirationDate(token);
      // Proactively refresh before actual expiration to prevent in-transit expiration and clock drift
      return DateTime.now().isAfter(expirationDate.subtract(buffer));
    } catch (_) {
      return false;
    }
  }

  bool _isJwtExpired(String token, {Duration buffer = const Duration(seconds: 30)}) =>
      isJwtExpired(token, buffer: buffer);

  /// Determines whether a refresh failure is an explicit, permanent authentication revocation
  /// (e.g. Keycloak returned 400 with 'invalid_grant', 'invalid_token', or 'session not found')
  /// versus any transient issue (network offline, timeouts, 429 rate limit, 5xx server crash).
  bool _isPermanentAuthRevocation(dynamic e) {
    if (e is AuthException) {
      return _isPermanentAuthRevocation(e.error);
    }
    if (e is KAuthNetworkException) return false;
    if (e is KAuthServerException) {
      final status = e.statusCode;
      if (status != null && status >= 500) return false;
    }

    final str = e.toString().toLowerCase();

    // Any network or connection-related error is never a permanent auth revocation
    if (str.contains('socketexception') ||
        str.contains('timeout') ||
        str.contains('failed host lookup') ||
        str.contains('connection refused') ||
        str.contains('connection reset') ||
        str.contains('network') ||
        str.contains('osstatus error') ||
        str.contains('handshake') ||
        str.contains('clientexception')) {
      return false;
    }

    // Explicit RFC 6749 & Keycloak permanent revocation indicators
    return str.contains('invalid_grant') ||
        str.contains('invalid_token') ||
        str.contains('session not found') ||
        str.contains('session_expired') ||
        str.contains('token expired') ||
        str.contains('token is not active') ||
        str.contains('invalid refresh token') ||
        str.contains('user not found') ||
        str.contains('user is disabled');
  }

  void _setupInterceptors(List<Interceptor>? additionalInterceptors) {
    dio.interceptors.add(
      // QueuedInterceptorsWrapper intrinsically locks the interceptor queue
      // when any asynchronous operation (like await refreshSession()) is happening inside it.
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = AuthManager().currentToken;
          // 1. Proactively check if token is expired before sending (using clock skew buffer)
          if (token != null && (token.isExpired || _isJwtExpired(token.accessToken, buffer: clockSkewBuffer))) {
            try {
              // Because this is a QueuedInterceptor, this await blocks all other
              // incoming requests in this interceptor until the refresh finishes.
              await AuthManager().refreshSession();
            } catch (e) {
              // If proactive refresh failed due to permanent auth revocation (e.g. 400 invalid_grant),
              // reject immediately to avoid sending a doomed request with an expired token.
              if (_isPermanentAuthRevocation(e)) {
                return handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 401,
                      statusMessage: 'Unauthorized: Session expired or revoked',
                    ),
                    type: DioExceptionType.badResponse,
                    error: e,
                    message: 'Authentication session expired or revoked.',
                  ),
                );
              }
              // If transient (network/500/rate limit), ignore here; the outgoing request will proceed and fail naturally.
            }
          }

          // 2. Attach the latest token to every outgoing request
          final latestToken = AuthManager().currentToken?.accessToken;
          if (latestToken != null) {
            options.headers['Authorization'] = 'Bearer $latestToken';
          }
          return handler.next(options);
        },
        onError: (DioException err, ErrorInterceptorHandler handler) async {
          // If this request was already retried once, do not attempt to refresh or retry again!
          // This prevents infinite retry loops and cascading failures.
          if (err.requestOptions.extra['kAuthRetried'] == true) {
            return handler.next(err);
          }

          // 3. Check if the error is a 401 Unauthorized
          if (err.response?.statusCode == 401) {
            final originalRequest = err.requestOptions;
            final currentToken = AuthManager().currentToken?.accessToken;
            final requestAuthHeader = originalRequest.headers['Authorization'];

            // If another queued request already refreshed the token while we were waiting,
            // retry immediately with the latest token without calling refreshSession() again!
            if (currentToken != null && requestAuthHeader != 'Bearer $currentToken') {
              originalRequest.headers['Authorization'] = 'Bearer $currentToken';
              originalRequest.extra['kAuthRetried'] = true;
              if (originalRequest.data is FormData) {
                try {
                  originalRequest.data = (originalRequest.data as FormData).clone();
                } catch (_) {
                  return handler.next(err);
                }
              }
              try {
                // Use _retryDio to bypass QueuedInterceptorsWrapper and avoid re-entrant deadlock!
                final response = await _retryDio.fetch(originalRequest);
                return handler.resolve(response);
              } on DioException catch (retryErr) {
                return handler.next(retryErr);
              } catch (_) {
                return handler.next(err);
              }
            }

            AuthToken? newToken;
            try {
              // 4. Attempt to refresh the token.
              // This async await locks the interceptor queue, queueing any new
              // requests automatically until this is resolved.
              newToken = await AuthManager().refreshSession();
            } catch (e) {
              // 5. Only pass 401 downstream if Keycloak explicitly confirmed the session is permanently dead.
              if (_isPermanentAuthRevocation(e)) {
                return handler.next(err);
              }

              // For ANY other error (network drop, timeout, 5xx server error, rate limit),
              // suppress the 401 and convert to connectionError so the app does NOT log out the user!
              return handler.next(
                DioException(
                  requestOptions: originalRequest,
                  type: DioExceptionType.connectionError,
                  error: e,
                  message: 'Authentication token refresh failed due to network or server error.',
                ),
              );
            }

            if (newToken != null && newToken.accessToken.isNotEmpty) {
              // 6. Update the Authorization header of the original failed request
              originalRequest.headers['Authorization'] = 'Bearer ${newToken.accessToken}';
              originalRequest.extra['kAuthRetried'] = true;
              if (originalRequest.data is FormData) {
                try {
                  originalRequest.data = (originalRequest.data as FormData).clone();
                } catch (_) {
                  return handler.next(err);
                }
              }

              // 7. Retry using _retryDio to avoid re-entering QueuedInterceptorsWrapper and deadlocking!
              try {
                final response = await _retryDio.fetch(originalRequest);
                return handler.resolve(response);
              } on DioException catch (retryErr) {
                // If retry itself fails (e.g. endpoint returns 401 again or 403),
                // pass the error down immediately without deadlocking or re-entering.
                return handler.next(retryErr);
              } catch (_) {
                return handler.next(err);
              }
            } else {
              return handler.next(err);
            }
          } else {
            // Not a 401, just pass the error along
            return handler.next(err);
          }
        },
      ),
    );

    // Add any additional interceptors (like logging plugin)
    if (additionalInterceptors != null) {
      dio.interceptors.addAll(additionalInterceptors);
    }
  }
}
