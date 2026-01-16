import 'package:flutter/material.dart';
import 'package:kauth_flutter_package/kauth_flutter_package.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize KAuth with default config
  // For local testing on Android, use 10.0.2.2 instead of localhost
  // await KAuth.initialize(
  //   config: KAuthConfig(baseUrl: "http://10.0.2.2:8085"),
  // );
  await KAuth.initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KAuth Tester',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  
  String _status = "Ready";
  bool _otpSent = false;
  bool _isLoading = false;

  Future<void> _sendOtp() async {
    setState(() {
      _isLoading = true;
      _status = "Sending OTP...";
    });

    try {
      await KAuth.sendOtp(_phoneController.text);
      if (mounted) {
        setState(() {
          _status = "OTP Sent!";
          _otpSent = true;
          _isLoading = false;
        });
      }
    } on KAuthException catch (e) {
       if (mounted) {
        setState(() {
          _status = "Auth Error: ${e.message}";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = "Error sending OTP: $e";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    setState(() {
      _isLoading = true;
      _status = "Verifying OTP...";
    });

    try {
      await KAuth.verifyOtp(_phoneController.text, _otpController.text);
      
      if (mounted) {
        setState(() {
          _status = "Login Successful!";
          _isLoading = false;
        });
      }
    } on KAuthInvalidOtpException {
      if (mounted) {
        setState(() {
           _status = "Invalid OTP. Please try again.";
           _isLoading = false;
        });
      }
    } on KAuthException catch (e) {
      if (mounted) {
        setState(() {
           _status = "Auth Error: ${e.message}";
           _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = "Verification Failed: $e";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await KAuth.logout();
    if (mounted) {
      setState(() {
        _status = "Logged Out";
        _otpSent = false;
        _phoneController.clear();
        _otpController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("KAuth Test App")),
      body: AuthBuilder(
        authenticated: (context, user, token) => _buildProfileView(user as KeycloakUser),
        unauthenticated: (context) => _buildLoginView(),
      ),
    );
  }

  Widget _buildLoginView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Status: $_status", textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          
          if (!_otpSent) ...[
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: "Phone Number (10 digits)",
                border: OutlineInputBorder(),
                prefixText: "+91 ",
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _sendOtp,
              child: _isLoading ? const CircularProgressIndicator() : const Text("Send OTP"),
            ),
          ] else ...[
             TextField(
              controller: _otpController,
              decoration: const InputDecoration(
                labelText: "Enter OTP",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
             ElevatedButton(
              onPressed: _isLoading ? null : _verifyOtp,
              child: _isLoading ? const CircularProgressIndicator() : const Text("Verify & Login"),
            ),
            TextButton(
              onPressed: () => setState(() => _otpSent = false),
              child: const Text("Change Phone Number"),
            )
          ]
        ],
      ),
    );
  }

  Widget _buildProfileView(KeycloakUser user) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text("Welcome, ${user.displayName}!", style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text("ID: ${user.uid}"),
            Text("Phone: ${user.phoneNumber}"),
            Text("Verified: ${user.hasVerifiedContact}"),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _testAuthenticatedApi,
              child: const Text("Test Authenticated API"),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _logout,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text("Logout"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testAuthenticatedApi() async {
    setState(() {
      _status = "Calling Authenticated API...";
      _isLoading = true;
    });

    try {
      // We use httpbin.org to echo back our headers so we can verify them
      final response = await KAuth.client.get(Uri.parse('https://httpbin.org/headers'));
      
      if (mounted) {
        setState(() {
          _status = "API Result: ${response.statusCode}";
          _isLoading = false;
        });
        print("API Response Body: ${response.body}");
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Check logs for headers! Status: ${response.statusCode}")),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
           _status = "API Error: $e";
           _isLoading = false;
        });
      }
    }
  }
}
