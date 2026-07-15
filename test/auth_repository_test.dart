import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:http/http.dart' as http;
import 'package:kauth_flutter_package/models/k_auth_config.dart';
import 'package:kauth_flutter_package/models/k_auth_exception.dart';
import 'package:kauth_flutter_package/repo/auth_repository.dart';
import 'package:kauth_flutter_package/repo/auth_repository_impl.dart';

// Generate Mocks
@GenerateMocks([http.Client])
import 'auth_repository_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late AuthRepository repository;
  late KAuthConfig config;

  setUp(() {
    mockClient = MockClient();
    config = const KAuthConfig(baseUrl: 'https://test.auth.com');
    // We construct the Impl directly for testing to inject dependencies
    repository = AuthRepositoryImpl(client: mockClient, config: config);
  });

  group('AuthRepository', () {
    test('sendOtp throws KAuthServerException on non-200 response', () async {
      when(mockClient.post(any)).thenAnswer(
        (_) async => http.Response('{"error": "bad_request"}', 400),
      );

      expect(
        () => repository.sendOtp('1234567890'),
        throwsA(isA<KAuthServerException>()),
      );
    });

    test('verifyOtp throws KAuthInvalidOtpException on invalid otp response', () async {
       when(mockClient.post(any)).thenAnswer(
        (_) async => http.Response('Invalid OTP provided', 401),
      );

      expect(
        () => repository.verifyOtp('1234567890', '0000'),
        throwsA(isA<KAuthInvalidOtpException>()),
      );
    });

    test('check default config', () async {
       final defaultConfig = KAuthConfig.defaults();
       expect(defaultConfig.baseUrl, "https://auth.keshavonline.com");
    });

    test('logoutBackChannel makes POST request to correct endpoint with JSON payload', () async {
      when(mockClient.post(
        any,
        headers: anyNamed('headers'),
        body: anyNamed('body'),
      )).thenAnswer(
        (_) async => http.Response('', 204),
      );

      await repository.logoutBackChannel('test_refresh_token');

      final captured = verify(mockClient.post(
        captureAny,
        headers: captureAnyNamed('headers'),
        body: captureAnyNamed('body'),
      )).captured;

      expect(captured[0].toString(), 'https://test.auth.com/logout/backChannel');
      expect(captured[1]['Content-Type'], 'application/json');
      expect(captured[2], '{"refreshToken":"test_refresh_token"}');
    });
  });
}
