class KDeviceInfo {
  final String platform;
  final String manufacturer;
  final String brand;
  final String model;
  final String osVersion;
  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;
  final String? deviceId;

  KDeviceInfo({
    required this.platform,
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.osVersion,
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
    this.deviceId,
  });

  @override
  String toString() {
    return 'KDeviceInfo(platform: $platform, manufacturer: $manufacturer, brand: $brand, model: $model, osVersion: $osVersion, appName: $appName, packageName: $packageName, version: $version, buildNumber: $buildNumber, deviceId: $deviceId)';
  }
}
