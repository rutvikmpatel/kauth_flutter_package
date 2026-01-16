import 'package:authflow/authflow.dart';
import '../models/keycloak_user.dart';
import '../repo/auth_repository.dart';
import '../models/k_auth_config.dart';

class KeycloakAuthProvider extends AuthProvider {
  final AuthRepository _repository;

  KeycloakAuthProvider({AuthRepository? repository, KAuthConfig? config})
      : _repository = repository ?? AuthRepository(config: config);
      
  @override
  String get providerId => "keycloak";

  @override
  Future<AuthResult> login(Map<String, dynamic> credentials) {
      throw UnimplementedError("Use sendOtp and verifyOtp for Keycloak login");
  }

  @override
  Future<AuthToken?> refreshToken(AuthToken currentToken, AuthUser user) async {
    if (currentToken.refreshToken == null) {
      return null;
    }

    try {
      final response = await _repository.refreshToken(currentToken.refreshToken!);
      return AuthToken(
        accessToken: response.access_token,
        refreshToken: response.refresh_token,
      );
    } catch (e) {
      // Refresh failed
      return null;
    }
  }
  
  // Custom methods for login flow which can be accessed via type casting the provider
  // or wrapping them in a manager helper.
  
  Future<void> sendOtp(String phoneNumber, {String countryCode = '+91'}) async {
     await _repository.sendOtp(phoneNumber, countryCode: countryCode);
  }

  Future<AuthResult> verifyOtp(String phoneNumber, String otp, {String countryCode = '+91'}) async {
    final tokenResponse = await _repository.verifyOtp(phoneNumber, otp, countryCode: countryCode);
    final token = tokenResponse.access_token;
    final user = KeycloakUser.fromJwt(token);
    
    // AuthResult(token: token, user: user)
    // Note: Authflow manages session via AuthManager.loginWithProvider usually returns AuthResult.
    // Since we are implementing custom flow, we return AuthResult here to be used by the caller
    // who then calls AuthManager.setSession().
    
    return AuthResult(user: user, token: AuthToken(accessToken: token, refreshToken: tokenResponse.refresh_token));
  }

  @override
  Future<void> logout() async {
    // Standard logout does not support token parameter.
    // Use remoteLogout for Keycloak specific logout that invalidates the token on server.
  }

  Future<void> remoteLogout(AuthToken token) async {
    if (token.refreshToken != null) {
      await _repository.logout(token.refreshToken!);
    }
  }
}
