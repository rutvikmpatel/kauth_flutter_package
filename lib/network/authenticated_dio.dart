import 'package:dio/dio.dart';
import 'package:authflow/authflow.dart';

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

  void _setupInterceptors(List<Interceptor>? additionalInterceptors) {
    dio.interceptors.add(
      // QueuedInterceptorsWrapper intrinsically locks the interceptor queue
      // when any asynchronous operation (like await refreshSession()) is happening inside it.
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) async {
          // 1. Proactively check if token is expired before sending
          if (AuthManager().currentToken?.isExpired ?? false) {
            // Because this is a QueuedInterceptor, this await blocks all other
            // incoming requests in this interceptor until the refresh finishes.
            await AuthManager().refreshSession();
          }

          // 2. Attach the token to every outgoing request
          final token = AuthManager().currentToken?.accessToken;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException err, ErrorInterceptorHandler handler) async {
          // 3. Check if the error is a 401 Unauthorized
          if (err.response?.statusCode == 401) {
            final originalRequest = err.requestOptions;

            try {
              // 4. Attempt to refresh the token.
              // This async await locks the interceptor queue, queueing any new
              // requests automatically until this is resolved.
              final newToken = await AuthManager().refreshSession();

              if (newToken != null) {
                // 5. Update the Authorization header of the original failed request
                originalRequest.headers['Authorization'] = 'Bearer $newToken';

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
