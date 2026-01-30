# kauth_flutter_package

A robust Flutter authentication package designed for seamless integration with Keycloak. It simplifies OTP-based login, token management (including automatic refresh), and secure session storage.

## Features

*   **OTP Login**: Easy-to-use API for sending and verifying OTPs.
*   **Automatic Token Refresh**: Transparently handles access token expiration and refreshing via `AuthenticatedHttpClient`.
*   **Secure Storage**: Uses secure storage (Keychain/EncryptedSharedPreferences) to persist user sessions.
*   **Robust Error Handling**: Provides specific exceptions (`KAuthInvalidOtpException`, `KAuthNetworkException`) for better UI handling.
*   **Environment Configuration**: Supports custom base URLs for Development, Staging, and Production environments.
*   **Device Information**: Easily retrieve device and app metadata.
*   **Auth Builder**: Widget builder for handling authentication states.

## Getting Started

### Installation

Add the package to your `pubspec.yaml` using git:

```yaml
dependencies:
  kauth_flutter_package:
    git:
      url: https://github.com/rutvikmpatel/kauth_flutter_package.git
```

## Usage

### 1. Initialization

Initialize `KAuth` in your `main()` method before running the app. You can pass a `KAuthConfig` to point to your specific Keycloak server.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize with default config (Production)
  await KAuth.initialize();

  // OR Initialize with custom config (Development)
  /*
  await KAuth.initialize(
    config: KAuthConfig(baseUrl: "http://10.0.2.2:8085"),
  );
  */

  runApp(const MyApp());
}
```

### 2. Login Flow (OTP)

```dart
void main() async {
  // Send OTP
  try {
    // Default country code is +91
    await KAuth.sendOtp("9876543210");
    
    // Or specify country code
    // await KAuth.sendOtp("9876543210", countryCode: "+1");
    print("OTP Sent!");
  } catch (e) {
    print("Error: $e");
  }

  // Verify OTP
  try {
    await KAuth.verifyOtp("9876543210", "1234");
    print("Login Successful!");
  } on KAuthInvalidOtpException {
    print("Invalid OTP entered.");
  } catch (e) {
    print("Verification failed: $e");
  }
}
```

### 3. User Management & UI

Retrieve the current user or listen to authentication state changes.

#### Current User

```dart
void main() {
  KeycloakUser? user = KAuth.currentUser;
  if (user != null) {
    print("User ID: ${user.uid}");
    print("Name: ${user.displayName}");
  }
}
```

#### AuthBuilder Widget

Use `AuthBuilder` to switch your UI based on authentication state.

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: AuthBuilder(
          // Shown when user is logged in
          authenticated: (context, user, token) {
             return HomePage(user: user as KeycloakUser);
          },
          // Shown when user is logged out or session expired
          unauthenticated: (context) {
             return LoginPage();
          },
        ),
      ),
    );
  }
}
```

### 4. Device Information

Get useful device and application metadata using `KAuth.getDeviceInfo()`.

```dart
void main() async {
  KDeviceInfo deviceInfo = await KAuth.getDeviceInfo();

  print("Platform: ${deviceInfo.platform}");       // e.g., Android, iOS
  print("Manufacturer: ${deviceInfo.manufacturer}"); // e.g., Google, Apple
  print("Model: ${deviceInfo.model}");             // e.g., Pixel 7, iPhone 14
  print("App Version: ${deviceInfo.version}");     // e.g., 1.0.0
  print("Device ID: ${deviceInfo.deviceId}");
}
```

### 5. Authenticated Requests

Use `KAuth.client` to make authenticated HTTP requests. It automatically attaches the Bearer token and handles 401 retries.

```dart
void main() async {
  final client = KAuth.client;
  final response = await client.get(Uri.parse('https://api.yourservice.com/profile'));
}
```

### 6. Logout

```dart
void main() async {
  // Performs remote logout (invalidating token on server) and clears local session
  await KAuth.logout();
}
```

## Additional Information

*   This package depends on `authflow` for session state management.
*   Ensure platform-specific configuration for `flutter_secure_storage` is secure (e.g., KeyStore/Keychain setup).
