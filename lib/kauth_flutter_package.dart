library kauth_flutter_package;

export 'package:authflow/authflow.dart';
export 'models/keycloak_user.dart';
export 'models/k_auth_config.dart';
export 'models/k_auth_exception.dart';

import 'package:authflow/authflow.dart';
import 'package:http/http.dart' as http;
import 'models/keycloak_user.dart';
import 'provider/keycloak_auth_provider.dart';
import 'network/authenticated_http_client.dart';
import 'models/k_auth_config.dart';
import 'repo/auth_repository.dart';

import 'dart:convert'; // For jsonDecode

class KAuth {
  static KeycloakAuthProvider? _provider;
  static KAuthConfig _config = KAuthConfig.defaults();

  static Future<void> initialize({
    KAuthConfig? config,
  }) async {
    _config = config ?? KAuthConfig.defaults();
    final repository = AuthRepository(config: _config);
    final provider = KeycloakAuthProvider(repository: repository);
    _provider = provider;
    
    await AuthManager().configure(
      AuthConfig(
        providers: [provider],
        defaultProviderId: provider.providerId,
        storage: SecureAuthStorage(
          userDeserializer: (String data) => KeycloakUser.deserialize(jsonDecode(data)),
        ),
      ),
    );
  }

  static Future<void> sendOtp(String phoneNumber, {String countryCode = '+91'}) async {
    if (_provider == null) throw Exception("KAuth not initialized");
    await _provider!.sendOtp(phoneNumber, countryCode: countryCode);
  }

  static Future<void> verifyOtp(String phoneNumber, String otp, {String countryCode = '+91'}) async {
    if (_provider == null) throw Exception("KAuth not initialized");
    final result = await _provider!.verifyOtp(phoneNumber, otp, countryCode: countryCode);
    await AuthManager().setSession(result.user!, result.token!);
  }

  static Future<void> logout() async {
    try {
      final token = AuthManager().currentToken;
      if (_provider != null && token != null) {
        await _provider!.remoteLogout(token);
      }
    } catch (e) {
      // Ignore remote logout errors and proceed to local logout
    } finally {
      await AuthManager().logout();
    }
  }

  static http.Client get client => AuthenticatedHttpClient();
}
