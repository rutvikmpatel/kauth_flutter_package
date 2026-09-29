import 'package:flutter_test/flutter_test.dart';
import 'package:kauth_flutter_package/kauth_flutter_package.dart';
import 'package:kauth_flutter_package/provider/keycloak_auth_provider.dart';
import 'package:kauth_flutter_package/models/keycloak_token.dart';
import 'package:kauth_flutter_package/repo/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  KAuthConfig get config => KAuthConfig.defaults();

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<void> logoutBackChannel(String refreshToken) async {}

  @override
  Future<KeycloakTokenResponse> refreshToken(String refreshToken) async {
    return KeycloakTokenResponse(
      access_token: 'fake_refreshed_access_token',
      refresh_token: 'fake_refreshed_refresh_token',
      expires_in: 300,
    );
  }

  @override
  Future<void> sendOtp(String phone, {String countryCode = '+91'}) async {}

  @override
  Future<KeycloakTokenResponse> verifyOtp(String phone, String otp, {String countryCode = '+91'}) async {
    return KeycloakTokenResponse(
      access_token: 'fake_access_token',
      refresh_token: 'fake_refresh_token',
      expires_in: 300,
    );
  }
}

void main() {
  group('KeycloakAuthProvider Tests', () {
    late KeycloakAuthProvider provider;
    late FakeAuthRepository fakeRepo;

    setUp(() {
      fakeRepo = FakeAuthRepository();
      provider = KeycloakAuthProvider(repository: fakeRepo);
    });

    test('checkSession returns true if refreshToken is present even if token is expired', () async {
      final expiredToken = AuthToken(
        accessToken: 'expired_access_token',
        refreshToken: 'valid_refresh_token',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      final dummyUser = KeycloakUser(uid: 'user_1', username: 'test');

      expect(expiredToken.isExpired, isTrue);
      final isValid = await provider.checkSession(expiredToken, dummyUser);
      expect(isValid, isTrue, reason: 'Offline session should remain valid when refresh token is available');
    });

    test('refreshToken computes expiresAt from response expires_in', () async {
      final oldToken = AuthToken(
        accessToken: 'old_access',
        refreshToken: 'old_refresh',
      );
      final dummyUser = KeycloakUser(uid: 'user_1', username: 'test');

      final newToken = await provider.refreshToken(oldToken, dummyUser);
      expect(newToken, isNotNull);
      expect(newToken!.accessToken, equals('fake_refreshed_access_token'));
      expect(newToken.refreshToken, equals('fake_refreshed_refresh_token'));
      expect(newToken.expiresAt, isNotNull);
      expect(newToken.expiresAt!.isAfter(DateTime.now()), isTrue);
    });
  });
}
