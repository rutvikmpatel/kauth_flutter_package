import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kauth_flutter_package/kauth_flutter_package.dart';
import 'package:kauth_flutter_package/provider/keycloak_auth_provider.dart';
import 'package:kauth_flutter_package/models/keycloak_token.dart';
import 'package:kauth_flutter_package/repo/auth_repository.dart';

String _createMockJwt(DateTime exp) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'}))).replaceAll('=', '');
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': exp.millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '');
  return '$header.$payload.fakesignature';
}

class MockDioAdapter implements HttpClientAdapter {
  int attempts = 0;
  final int Function(int attempt) statusCodeGenerator;

  MockDioAdapter(this.statusCodeGenerator);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    attempts++;
    final code = statusCodeGenerator(attempts);
    return ResponseBody.fromString(code == 200 ? '{"success":true}' : '{"error":"unauthorized"}', code);
  }

  @override
  void close({bool force = false}) {}
}

class FakeAuthRepository implements AuthRepository {
  KAuthConfig get config => KAuthConfig.defaults();

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<void> logoutBackChannel(String refreshToken) async {}

  int refreshCallCount = 0;
  bool shouldThrowNetworkError = false;
  bool shouldThrowServer400 = false;
  bool shouldThrowRateLimit429 = false;

  @override
  Future<KeycloakTokenResponse> refreshToken(String refreshToken) async {
    refreshCallCount++;
    if (shouldThrowNetworkError) {
      throw KAuthNetworkException('Simulated network timeout/socket failure');
    }
    if (shouldThrowRateLimit429) {
      throw KAuthServerException('Rate limited: Too many requests', statusCode: 429);
    }
    if (shouldThrowServer400) {
      throw KAuthServerException('Failed to refresh token: {"error":"invalid_grant","error_description":"Offline user session not found"}', statusCode: 400);
    }
    await Future.delayed(const Duration(milliseconds: 20));
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

    test('refreshToken leaves expiresAt null to prevent authflow clearAll trap on offline launch', () async {
      final oldToken = AuthToken(
        accessToken: 'old_access',
        refreshToken: 'old_refresh',
      );
      final dummyUser = KeycloakUser(uid: 'user_1', username: 'test');

      final newToken = await provider.refreshToken(oldToken, dummyUser);
      expect(newToken, isNotNull);
      expect(newToken!.accessToken, equals('fake_refreshed_access_token'));
      expect(newToken.refreshToken, equals('fake_refreshed_refresh_token'));
      expect(newToken.expiresAt, isNull, reason: 'expiresAt must remain null so authflow does not clear local storage offline');
    });

    test('concurrent refreshToken calls share single in-flight future and only call repository once', () async {
      final oldToken = AuthToken(
        accessToken: 'old_access',
        refreshToken: 'old_refresh',
      );
      final dummyUser = KeycloakUser(uid: 'user_1', username: 'test');

      // Simulate mainApi and messagingApi calling refreshToken at the exact same moment
      final results = await Future.wait([
        provider.refreshToken(oldToken, dummyUser),
        provider.refreshToken(oldToken, dummyUser),
        provider.refreshToken(oldToken, dummyUser),
      ]);

      expect(fakeRepo.refreshCallCount, equals(1), reason: 'Repository must only be hit once for concurrent calls');
      expect(results[0]?.accessToken, equals('fake_refreshed_access_token'));
      expect(results[1]?.accessToken, equals('fake_refreshed_access_token'));
      expect(results[2]?.accessToken, equals('fake_refreshed_access_token'));
    });

    test('refreshToken rethrows network and server exceptions instead of silently swallowing', () async {
      final oldToken = AuthToken(
        accessToken: 'old_access',
        refreshToken: 'old_refresh',
      );
      final dummyUser = KeycloakUser(uid: 'user_1', username: 'test');

      fakeRepo.shouldThrowNetworkError = true;

      expect(
        () => provider.refreshToken(oldToken, dummyUser),
        throwsA(isA<KAuthNetworkException>()),
      );
    });
  });

  group('AuthenticatedDio Clock Skew & Transit Buffer Tests', () {
    test('returns true when token has already expired in the past', () {
      final expiredJwt = _createMockJwt(DateTime.now().subtract(const Duration(seconds: 10)));
      expect(AuthenticatedDio.isJwtExpired(expiredJwt), isTrue);
    });

    test('returns true when token is technically valid for 10s but falls inside 30s transit window', () {
      final nearExpiringJwt = _createMockJwt(DateTime.now().add(const Duration(seconds: 10)));
      expect(
        AuthenticatedDio.isJwtExpired(nearExpiringJwt),
        isTrue,
        reason: 'Tokens expiring within 30 seconds must trigger proactive refresh to avoid 401 in transit',
      );
    });

    test('returns false when token is comfortably valid outside 30s buffer', () {
      final validJwt = _createMockJwt(DateTime.now().add(const Duration(minutes: 5)));
      expect(
        AuthenticatedDio.isJwtExpired(validJwt),
        isFalse,
      );
    });

    test('respects custom clock skew buffer duration', () {
      final jwtValidFor45s = _createMockJwt(DateTime.now().add(const Duration(seconds: 45)));

      // With default 30s buffer, 45s is NOT expired
      expect(AuthenticatedDio.isJwtExpired(jwtValidFor45s, buffer: const Duration(seconds: 30)), isFalse);

      // With 60s buffer, 45s IS expired
      expect(AuthenticatedDio.isJwtExpired(jwtValidFor45s, buffer: const Duration(seconds: 60)), isTrue);
    });

    test('returns false gracefully without throwing if token is malformed', () {
      expect(AuthenticatedDio.isJwtExpired('invalid.malformed.token'), isFalse);
      expect(AuthenticatedDio.isJwtExpired(''), isFalse);
    });
  });

  group('AuthenticatedDio Deadlock & Retry Tests', () {
    test('does not deadlock and attempts exactly 2 times when retry also returns 401', () async {
      final fakeRepo = FakeAuthRepository();
      final provider = KeycloakAuthProvider(repository: fakeRepo);
      await AuthManager().configure(
        AuthConfig(
          providers: [provider],
          defaultProviderId: provider.providerId,
        ),
      );
      final dummyUser = KeycloakUser(uid: 'user_1', username: 'test');
      final validJwt = _createMockJwt(DateTime.now().add(const Duration(minutes: 5)));
      await AuthManager().setSession(
        dummyUser,
        AuthToken(accessToken: validJwt, refreshToken: 'refresh_1'),
        providerId: provider.providerId,
      );

      final adapter = MockDioAdapter((attempt) => 401);
      final authDio = AuthenticatedDio(
        options: BaseOptions(baseUrl: 'https://example.com'),
        httpClientAdapter: adapter,
      );

      try {
        await authDio.dio.get('/test').timeout(const Duration(seconds: 2));
        fail('Should have failed with 401');
      } on DioException catch (e) {
        expect(e.response?.statusCode, equals(401));
        expect(
          adapter.attempts,
          equals(2),
          reason: 'Should only attempt once initially and once on retry without looping or deadlocking',
        );
      }
    });

    test('resolves successfully when retry returns 200', () async {
      final fakeRepo = FakeAuthRepository();
      final provider = KeycloakAuthProvider(repository: fakeRepo);
      await AuthManager().configure(
        AuthConfig(
          providers: [provider],
          defaultProviderId: provider.providerId,
        ),
      );
      final dummyUser = KeycloakUser(uid: 'user_1', username: 'test');
      final validJwt = _createMockJwt(DateTime.now().add(const Duration(minutes: 5)));
      await AuthManager().setSession(
        dummyUser,
        AuthToken(accessToken: validJwt, refreshToken: 'refresh_1'),
        providerId: provider.providerId,
      );

      // Attempt 1 -> 401, Attempt 2 (retry) -> 200
      final adapter = MockDioAdapter((attempt) => attempt == 1 ? 401 : 200);
      final authDio = AuthenticatedDio(
        options: BaseOptions(baseUrl: 'https://example.com'),
        httpClientAdapter: adapter,
      );

      final response = await authDio.dio.get('/test').timeout(const Duration(seconds: 2));
      expect(response.statusCode, equals(200));
      expect(adapter.attempts, equals(2));
    });

    test('suppresses 401 and emits connectionError when refresh fails due to network outage', () async {
      final fakeRepo = FakeAuthRepository()..shouldThrowNetworkError = true;
      final provider = KeycloakAuthProvider(repository: fakeRepo);
      await AuthManager().configure(
        AuthConfig(
          providers: [provider],
          defaultProviderId: provider.providerId,
        ),
      );
      final dummyUser = KeycloakUser(uid: 'user_1', username: 'test');
      final validJwt = _createMockJwt(DateTime.now().add(const Duration(minutes: 5)));
      await AuthManager().setSession(
        dummyUser,
        AuthToken(accessToken: validJwt, refreshToken: 'refresh_1'),
        providerId: provider.providerId,
      );

      final adapter = MockDioAdapter((attempt) => 401);
      final authDio = AuthenticatedDio(
        options: BaseOptions(baseUrl: 'https://example.com'),
        httpClientAdapter: adapter,
      );

      try {
        await authDio.dio.get('/test').timeout(const Duration(seconds: 2));
        fail('Should have failed with connectionError');
      } on DioException catch (e) {
        // Must NOT pass down the 401 response status, preventing app-level logout
        expect(e.type, equals(DioExceptionType.connectionError));
        expect(e.response, isNull, reason: '401 must be suppressed so app does not log out on offline refresh');
      }
    });

    test('rejects with 401 response when proactive refresh fails due to permanent revocation (400 Bad Request)', () async {
      final fakeRepo = FakeAuthRepository()..shouldThrowServer400 = true;
      final provider = KeycloakAuthProvider(repository: fakeRepo);
      await AuthManager().configure(
        AuthConfig(
          providers: [provider],
          defaultProviderId: provider.providerId,
        ),
      );
      final dummyUser = KeycloakUser(uid: 'user_1', username: 'test');
      // Token is already expired to trigger proactive refresh in onRequest
      final expiredJwt = _createMockJwt(DateTime.now().subtract(const Duration(minutes: 5)));
      await AuthManager().setSession(
        dummyUser,
        AuthToken(accessToken: expiredJwt, refreshToken: 'refresh_1'),
        providerId: provider.providerId,
      );

      final adapter = MockDioAdapter((attempt) => 200);
      final authDio = AuthenticatedDio(
        options: BaseOptions(baseUrl: 'https://example.com'),
        httpClientAdapter: adapter,
      );

      try {
        await authDio.dio.get('/test').timeout(const Duration(seconds: 2));
        fail('Should have failed with 401');
      } on DioException catch (e) {
        expect(e.response?.statusCode, equals(401), reason: 'Permanent refresh failure must yield 401 so app can trigger re-login');
      }
    });

    test('suppresses 401 and emits connectionError when refresh returns 429 Too Many Requests (rate limit)', () async {
      final fakeRepo = FakeAuthRepository()..shouldThrowRateLimit429 = true;
      final provider = KeycloakAuthProvider(repository: fakeRepo);
      await AuthManager().configure(
        AuthConfig(
          providers: [provider],
          defaultProviderId: provider.providerId,
        ),
      );
      final dummyUser = KeycloakUser(uid: 'user_1', username: 'test');
      final validJwt = _createMockJwt(DateTime.now().add(const Duration(minutes: 5)));
      await AuthManager().setSession(
        dummyUser,
        AuthToken(accessToken: validJwt, refreshToken: 'refresh_1'),
        providerId: provider.providerId,
      );

      final adapter = MockDioAdapter((attempt) => 401);
      final authDio = AuthenticatedDio(
        options: BaseOptions(baseUrl: 'https://example.com'),
        httpClientAdapter: adapter,
      );

      try {
        await authDio.dio.get('/test').timeout(const Duration(seconds: 2));
        fail('Should have failed with connectionError');
      } on DioException catch (e) {
        expect(e.type, equals(DioExceptionType.connectionError));
        expect(e.response, isNull, reason: '429 rate limit must NOT trigger logout');
      }
    });
  });
}
