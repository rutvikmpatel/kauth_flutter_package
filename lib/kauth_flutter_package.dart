library kauth_flutter_package;

export 'package:authflow/authflow.dart';
export 'models/keycloak_user.dart';
export 'models/k_auth_config.dart';
export 'models/k_auth_exception.dart';
export 'models/k_device_info.dart';

import 'package:authflow/authflow.dart';
import 'package:http/http.dart' as http;
import 'models/keycloak_user.dart';
import 'models/k_device_info.dart';
import 'provider/keycloak_auth_provider.dart';
import 'network/authenticated_http_client.dart';
import 'models/k_auth_config.dart';
import 'repo/auth_repository.dart';

import 'dart:convert'; // For jsonDecode
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

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

  static KeycloakUser? get currentUser => AuthManager().currentUser as KeycloakUser?;

  static Future<KDeviceInfo> getDeviceInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final deviceInfo = DeviceInfoPlugin();

    String manufacturer = 'Unknown';
    String brand = 'Unknown';
    String model = 'Unknown';
    String osVersion = 'Unknown';
    String? deviceId;
    String platformName = 'Unknown';

    try {
      if (Platform.isAndroid) {
        platformName = 'Android';
        final androidInfo = await deviceInfo.androidInfo;
        manufacturer = androidInfo.manufacturer;
        brand = androidInfo.brand;
        model = androidInfo.model;
        osVersion = 'Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})';
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        platformName = 'iOS';
        final iosInfo = await deviceInfo.iosInfo;
        manufacturer = 'Apple';
        brand = 'Apple';
        model = iosInfo.utsname.machine;
        osVersion = '${iosInfo.systemName} ${iosInfo.systemVersion}';
        deviceId = iosInfo.identifierForVendor;
      } else {
        platformName = Platform.operatingSystem;
        osVersion = Platform.operatingSystemVersion;
      }
    } catch (e) {
      // Handle or log error if needed
    }

    return KDeviceInfo(
      platform: platformName,
      manufacturer: manufacturer,
      brand: brand,
      model: model,
      osVersion: osVersion,
      appName: packageInfo.appName,
      packageName: packageInfo.packageName,
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      deviceId: deviceId,
    );
  }

  static Future<void> sendOtp(String phoneNumber, {String countryCode = '+91'}) async {


    if (_provider == null) throw Exception("KAuth not initialized");
    await _provider!.sendOtp(phoneNumber, countryCode: countryCode);
  }

  static Future<void> verifyOtp(String phoneNumber, String otp, {String countryCode = '+91'}) async {
    if (_provider == null) throw Exception("KAuth not initialized");
    final result = await _provider!.verifyOtp(phoneNumber, otp, countryCode: countryCode);
    await AuthManager().setSession(result.user, result.token);
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
