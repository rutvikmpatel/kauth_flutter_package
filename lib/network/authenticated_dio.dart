import 'package:dio/dio.dart';
import 'package:authflow/authflow.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

/// A ready-to-use Dio instance that automatically handles
/// attaching authentication tokens and retrying requests on 401 Unauthorized.
class AuthenticatedDio {
  final Dio dio;

  AuthenticatedDio({
    required BaseOptions options,
    List<Interceptor>? additionalInterceptors,
  }) : dio = Dio(options) {
    _setupInterceptors(additionalInterceptors);
  }

  bool _isJwtExpired(String token) {
    try {
      return JwtDecoder.isExpired(token);
    } catch (_) {
      return false;
    }
  }

  void _setupInterceptors(List<Interceptor>? additionalInterceptors) {
    dio.interceptors.add(
      // QueuedInterceptorsWrapper intrinsically locks the interceptor queue
      // when any asynchronous operation (like await refreshSession()) is happening inside it.
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = AuthManager().currentToken;
          // 1. Proactively check if token is expired before sending
          if (token != null && (token.isExpired || _isJwtExpired(token.accessToken))) {
            // Because this is a QueuedInterceptor, this await blocks all other
            // incoming requests in this interceptor until the refresh finishes.
            await AuthManager().refreshSession();
          }

          // 2. Attach the latest token to every outgoing request
          final latestToken = AuthManager().currentToken?.accessToken;
          if (latestToken != null) {
            options.headers['Authorization'] = 'Bearer $latestToken';
          }
          return handler.next(options);
        },
        onError: (DioException err, ErrorInterceptorHandler handler) async {
          // 3. Check if the error is a 401 Unauthorized
          if (err.response?.statusCode == 401) {
            final originalRequest = err.requestOptions;
            final currentToken = AuthManager().currentToken?.accessToken;
            final requestAuthHeader = originalRequest.headers['Authorization'];

            // If another queued request already refreshed the token while we were waiting,
            // retry immediately with the latest token without calling refreshSession() again!
            if (currentToken != null && requestAuthHeader != 'Bearer $currentToken') {
              originalRequest.headers['Authorization'] = 'Bearer $currentToken';
              try {
                final response = await dio.fetch(originalRequest);
                return handler.resolve(response);
              } on DioException catch (retryErr) {
                return handler.next(retryErr);
              } catch (_) {
                return handler.next(err);
              }
            }

            try {
              // 4. Attempt to refresh the token.
              // This async await locks the interceptor queue, queueing any new
              // requests automatically until this is resolved.
              final newToken = await AuthManager().refreshSession();

              if (newToken != null && newToken.accessToken.isNotEmpty) {
                // 5. Update the Authorization header of the original failed request
                // Use newToken.accessToken to ensure a valid JWT string is formatted
                originalRequest.headers['Authorization'] = 'Bearer ${newToken.accessToken}';

                // 6. Retry the original request
                final response = await dio.fetch(originalRequest);
                return handler.resolve(response);
              } else {
                // If refresh failed, pass the error down
                return handler.next(err);
              }
            } catch (e) {
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
