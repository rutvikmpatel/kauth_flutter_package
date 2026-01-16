import 'package:http/http.dart' as http;
import 'package:authflow/authflow.dart';

class AuthenticatedHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // 1. Check if token is expired before sending (Preventative)
    if (_isTokenExpired()) {
      await _tryRefresh();
    }

    // 2. Attach Token
    var token = AuthManager().currentToken?.accessToken;
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // 3. Send Request
    var response = await _inner.send(request);

    // 4. Handle 401 (Reactive)
    if (response.statusCode == 401) {
      // Attempt refresh
      final refreshed = await _tryRefresh();
      if (refreshed) {
        // If refresh successful, retry request with new token
        final newRequest = _copyRequest(request);
        if (newRequest != null) {
           token = AuthManager().currentToken?.accessToken;
           if (token != null) {
             newRequest.headers['Authorization'] = 'Bearer $token';
           }
           // Close the previous response stream since we aren't using it
           response.stream.drain();
           
           // CRITICAL: We call _inner.send() here, NOT this.send().
           // This ensures we bypass the interceptor logic for the retry, 
           // guaranteeing we cannot enter an infinite loop of 401s.
           // If this retry also fails, the 401 is returned to the caller.
           return _inner.send(newRequest);
        }
      }
    }

    return response;
  }

  bool _isTokenExpired() {
    return AuthManager().currentToken?.isExpired ?? false;
  }

  Future<bool> _tryRefresh() async {
    try {
      final newToken = await AuthManager().refreshSession();
      return newToken != null;
    } catch (e) {
      return false;
    }
  }

  http.BaseRequest? _copyRequest(http.BaseRequest request) {
    if (request is http.Request) {
      final newRequest = http.Request(request.method, request.url);
      newRequest.headers.addAll(request.headers);
      newRequest.bodyBytes = request.bodyBytes;
      newRequest.encoding = request.encoding;
      return newRequest;
    } 
    // Handle MultipartRequest if needed, though simpler to start with Request
    return null; 
  }
}
