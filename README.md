# kauth_flutter_package

A robust Flutter authentication package designed for seamless integration with Keycloak. It simplifies OTP-based login, token management (including automatic refresh), and secure session storage.

## Features

*   **OTP Login**: Easy-to-use API for sending and verifying OTPs.
*   **Automatic Token Refresh**: Transparently handles access token expiration and refreshing via `AuthenticatedHttpClient`.
*   **Secure Storage**: Uses secure storage (Keychain/EncryptedSharedPreferences) to persist user sessions.
*   **Robust Error Handling**: Provides specific exceptions (`KAuthInvalidOtpException`, `KAuthNetworkException`) for better UI handling.
*   **Environment Configuration**: Supports custom base URLs for Development, Staging, and Production environments.

## Getting Started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  kauth_flutter_package: ^0.0.1
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
// Send OTP
try {
  await KAuth.sendOtp("9876543210");
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
```

### 3. Authenticated Requests

Use `KAuth.client` to make authenticated HTTP requests. It automatically attaches the Bearer token and handles 401 retries.

```dart
final client = KAuth.client;
final response = await client.get(Uri.parse('https://api.yourservice.com/profile'));
```

### 4. Logout

```dart
// Performs remote logout (invalidating token on server) and clears local session
await KAuth.logout();
```

## Additional Information

*   This package depends on `authflow` for session state management.
*   Ensure platform-specific configuration for `flutter_secure_storage` is secure (e.g., KeyStore/Keychain setup).
