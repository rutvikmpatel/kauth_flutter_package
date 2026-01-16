import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class InternalHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final Map<String, String>? defaultHeaders;
  
  static Map<String, String>? _cachedMetadataHeaders;

  InternalHttpClient({this.defaultHeaders});

  Future<Map<String, String>> _getMetadataHeaders() async {
    if (_cachedMetadataHeaders != null) return _cachedMetadataHeaders!;
    
    final headers = <String, String>{};
    
    // Add Platform
    try {
      if (Platform.isAndroid) {
        headers['X-Platform'] = 'Android';
      } else if (Platform.isIOS) {
        headers['X-Platform'] = 'iOS';
      } else if (Platform.isWindows) {
        headers['X-Platform'] = 'Windows';
      } else if (Platform.isMacOS) {
        headers['X-Platform'] = 'MacOS';
      } else if (Platform.isLinux) {
        headers['X-Platform'] = 'Linux';
      } else {
        headers['X-Platform'] = 'Unknown';
      }
    } catch (e) {
      headers['X-Platform'] = 'Web/Unknown';
    }
    
    // Add App Version & Signature
    try {
      final info = await PackageInfo.fromPlatform();
      headers['X-App-Name'] = info.appName;
      headers['X-App-Version'] = info.version;
      headers['X-App-Build-Number'] = info.buildNumber;
      headers['X-Package-Name'] = info.packageName;
      
      // On Android, buildSignature returns the SHA hex string of the signing certificate.
      // On iOS, it might return empty or local signing info.
      // We send it regardless as 'X-App-Signature'.
      if (info.buildSignature.isNotEmpty) {
        headers['X-App-Signature'] = info.buildSignature;
      }
    } catch (e) {
      // KAuthLogger.log("Failed to get package info: $e");
    }
    
    _cachedMetadataHeaders = headers;
    return headers;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // KAuthLogger.log('Request: ${request.method} ${request.url}');
    
    // 1. Add Configured Default Headers
    if (defaultHeaders != null) {
      request.headers.addAll(defaultHeaders!);
    }

    // 2. Add Automatic Metadata Headers
    final metadataHeaders = await _getMetadataHeaders();
    request.headers.addAll(metadataHeaders);
    
    // KAuthLogger.log('Headers: ${request.headers}');
    
    try {
      final response = await _inner.send(request);
      // KAuthLogger.log('Response: ${response.statusCode} for ${request.url}');
      return response;
    } catch (e) {
      // KAuthLogger.error('Error: $e', error: e, stackTrace: stack);
      rethrow;
    }
  }
}
