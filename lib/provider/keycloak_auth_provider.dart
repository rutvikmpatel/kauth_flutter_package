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

  // CRITICAL ARCHITECTURAL DECISION:
  // We intentionally keep `expiresAt: null` on AuthToken.
  //
  // Reason: In `package:authflow`, if `AuthToken.isExpired` is true during session restoration
  // (_restoreSession) and a refresh attempt fails (e.g. device is offline / Airplane mode on cold launch),
  // authflow will execute `await _storage!.clearAll()` and permanently wipe the user's saved session!
  //
  // Instead, proactive token expiration checks are performed directly on the JWT payload via
  // `JwtDecoder.isExpired(token.accessToken)` in `AuthenticatedDio.onRequest` and `AuthenticatedHttpClient`.
  // This guarantees proactive token refresh when online, while preventing authflow from ever wiping
  // offline sessions on cold start. DO NOT set `expiresAt` here without addressing authflow's clearAll trap!

  @override
  Future<bool> checkSession(AuthToken token, AuthUser user) async {
    // If an offline refresh token exists, the user session remains valid
    // even if the short-lived access token is expired.
    if (token.refreshToken != null && token.refreshToken!.isNotEmpty) {
      return true;
    }
    return !token.isExpired;
  }

  Future<AuthToken?>? _inFlightRefresh;

  @override
  Future<AuthToken?> refreshToken(AuthToken currentToken, AuthUser user) async {
    if (currentToken.refreshToken == null) {
      return null;
    }

    // If a refresh is already in-flight across any Dio instance (e.g. mainApi & messagingApi),
    // share the exact same Future to prevent duplicate network calls.
    if (_inFlightRefresh != null) {
      return _inFlightRefresh;
    }

    final future = _doRefreshToken(currentToken);
    _inFlightRefresh = future;
    try {
      return await future;
    } finally {
      _inFlightRefresh = null;
    }
  }

  Future<AuthToken?> _doRefreshToken(AuthToken currentToken) async {
    try {
      final response = await _repository.refreshToken(currentToken.refreshToken!);
      return AuthToken(
        accessToken: response.access_token,
        refreshToken: response.refresh_token,
        // expiresAt intentionally kept null (see architectural decision comment above)
        expiresAt: null,
      );
    } catch (e) {
      // Re-throw so caller (AuthenticatedDio) knows why refresh failed (network/500 vs 400 invalid_grant)
      rethrow;
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
    
    return AuthResult(
      user: user,
      token: AuthToken(
        accessToken: token,
        refreshToken: tokenResponse.refresh_token,
        // expiresAt intentionally kept null (see architectural decision comment above)
        expiresAt: null,
      ),
    );
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

  Future<void> remoteLogoutBackChannel(AuthToken token) async {
    if (token.refreshToken != null) {
      await _repository.logoutBackChannel(token.refreshToken!);
    }
  }
}
