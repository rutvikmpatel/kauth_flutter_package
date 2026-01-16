import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/keycloak_token.dart';
import '../network/internal_http_client.dart';
import 'auth_repository.dart';
import '../models/k_auth_config.dart';
import '../models/k_auth_exception.dart';

class AuthRepositoryImpl implements AuthRepository {
  final KAuthConfig config;
  final http.Client _client;

  AuthRepositoryImpl({http.Client? client, KAuthConfig? config}) 
      : _client = client ?? InternalHttpClient(),
        config = config ?? KAuthConfig.defaults();

  // Phone Login Routes
  String get phoneBase => "${config.baseUrl}/phone";
  String get sendOtpUrl => "$phoneBase/send";
  String get verifyOtpUrl => "$phoneBase/verify";
  
  // Token Routes
  String get refreshUrl => "${config.baseUrl}/refresh";
  String get logoutUrl => "${config.baseUrl}/logout";

  @override
  Future<void> sendOtp(String phone, {String countryCode = '+91'}) async {
    try {
      final fullPhone = "$countryCode$phone";
      final uri = Uri.parse(sendOtpUrl).replace(queryParameters: {
        'phoneNumber': fullPhone,
      });
      
      final response = await _client.post(uri);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      } else {
        throw KAuthServerException('Failed to send OTP: ${response.body}', statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is KAuthException) rethrow;
      throw KAuthNetworkException('Network error during sendOtp', e);
    }
  }

  @override
  Future<KeycloakTokenResponse> verifyOtp(String phone, String otp, {String countryCode = '+91'}) async {
    try {
      final fullPhone = "$countryCode$phone";
      final uri = Uri.parse(verifyOtpUrl).replace(queryParameters: {
        'phoneNumber': fullPhone,
        'otp': otp,
      });

      final response = await _client.post(uri);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body);
        if (json['error'] != null) {
          throw KAuthServerException("Verification failed: ${json['error_description'] ?? json['error']}");
        }
        return KeycloakTokenResponse.fromJson(json);
      } else {
         final body = response.body;
         // Heuristic for invalid OTP based on typical server responses
         if (body.contains("Invalid OTP") || body.contains("did not match")) {
           throw KAuthInvalidOtpException('Invalid OTP provided');
         }
        throw KAuthServerException('Failed to verify OTP: $body', statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is KAuthException) rethrow;
      throw KAuthNetworkException('Network error during verifyOtp', e);
    }
  }

  @override
  Future<KeycloakTokenResponse> refreshToken(String refreshToken) async {
    try {
      final response = await _client.post(
        Uri.parse(refreshUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body);
         if (json['error'] != null) {
          throw KAuthServerException("Refresh failed: ${json['error_description'] ?? json['error']}");
        }
        return KeycloakTokenResponse.fromJson(json);
      } else {
        throw KAuthServerException('Failed to refresh token: ${response.body}', statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is KAuthException) rethrow;
      throw KAuthNetworkException('Network error during refreshToken', e);
    }
  }

  @override
  Future<void> logout(String refreshToken) async {
    try {
      final response = await _client.post(
        Uri.parse(logoutUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      } else {
        throw KAuthServerException('Failed to logout: ${response.body}', statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is KAuthException) rethrow;
      throw KAuthNetworkException('Network error during logout', e);
    }
  }
}
