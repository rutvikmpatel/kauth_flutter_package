import 'package:http/http.dart' as http;
import '../models/keycloak_token.dart';
import '../models/k_auth_config.dart';
import 'auth_repository_impl.dart';

abstract class AuthRepository {
  factory AuthRepository({http.Client? client, KAuthConfig? config}) = AuthRepositoryImpl;

  Future<void> sendOtp(String phone, {String countryCode = '+91'});

  Future<KeycloakTokenResponse> verifyOtp(String phone, String otp, {String countryCode = '+91'});

  Future<KeycloakTokenResponse> refreshToken(String refreshToken);

  Future<void> logout(String refreshToken);
}
