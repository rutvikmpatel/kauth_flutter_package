import 'package:authflow/authflow.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class KeycloakUserMetadata {
  final int? creationTimestamp;
  final int? lastSignInTimestamp;
  final int? lastRefreshTimestamp;
  final String signInProvider;
  final Map<String, dynamic> customClaims;

  KeycloakUserMetadata({
    this.creationTimestamp,
    this.lastSignInTimestamp,
    this.lastRefreshTimestamp,
    this.signInProvider = "keycloak",
    this.customClaims = const {},
  });

  factory KeycloakUserMetadata.fromJson(Map<String, dynamic> json) {
    return KeycloakUserMetadata(
      creationTimestamp: json['creationTimestamp'],
      lastSignInTimestamp: json['lastSignInTimestamp'],
      lastRefreshTimestamp: json['lastRefreshTimestamp'],
      signInProvider: json['signInProvider'] ?? "keycloak",
      customClaims: json['customClaims'] ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'creationTimestamp': creationTimestamp,
      'lastSignInTimestamp': lastSignInTimestamp,
      'lastRefreshTimestamp': lastRefreshTimestamp,
      'signInProvider': signInProvider,
      'customClaims': customClaims,
    };
  }
}

class KeycloakUser extends AuthUser {
  final String uid;
  final String? email;
  final String? phoneNumber;
  final String? firstName;
  final String? lastName;
  final String? username;
  final bool emailVerified;
  final bool phoneVerified;
  final bool isEnabled;
  final int? createdAt;
  final int? lastLoginAt;
  final KeycloakUserMetadata? metadata;

  @override
  String get id => uid;

  KeycloakUser({
    required this.uid,
    this.email,
    this.phoneNumber,
    this.firstName,
    this.lastName,
    this.username,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.isEnabled = true,
    this.createdAt,
    this.lastLoginAt,
    this.metadata,
  });

  String get displayName {
    if (firstName != null && lastName != null) {
      return "$firstName $lastName";
    }
    return firstName ?? lastName ?? username ?? email ?? phoneNumber ?? "Unknown User";
  }

  String get initials {
    String first = firstName?.isNotEmpty == true ? firstName![0] : "";
    String last = lastName?.isNotEmpty == true ? lastName![0] : "";
    if (first.isEmpty && last.isEmpty) return "U";
    return (first + last).toUpperCase();
  }

  String? get primaryIdentifier => email ?? phoneNumber;

  bool get isAnonymous => false;

  bool get hasVerifiedContact => emailVerified || phoneVerified;

  bool get isProfileComplete => firstName != null && lastName != null && hasVerifiedContact;

  @override
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'phoneNumber': phoneNumber,
      'firstName': firstName,
      'lastName': lastName,
      'username': username,
      'emailVerified': emailVerified,
      'phoneVerified': phoneVerified,
      'isEnabled': isEnabled,
      'createdAt': createdAt,
      'lastLoginAt': lastLoginAt,
      'metadata': metadata?.toJson(),
    };
  }

  factory KeycloakUser.fromJwt(String token) {
    print("DEBUG: Decoding JWT token: $token");
    Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
    print("DEBUG: Decoded token payload: $decodedToken");
    
    final uid = decodedToken['sub'];
    if (uid == null) throw Exception("Invalid token: sub claim missing");

    final iat = decodedToken['iat'] is int ? decodedToken['iat'] as int : null;
    final exp = decodedToken['exp'] is int ? decodedToken['exp'] as int : null;

    final metadata = KeycloakUserMetadata(
      creationTimestamp: iat,
      lastSignInTimestamp: iat,
      lastRefreshTimestamp: DateTime.now().millisecondsSinceEpoch,
    );

    return KeycloakUser(
      uid: uid,
      email: decodedToken['email'],
      phoneNumber: decodedToken['phone_number'],
      firstName: decodedToken['given_name'],
      lastName: decodedToken['family_name'],
      username: decodedToken['preferred_username'],
      emailVerified: decodedToken['email_verified'] == true,
      phoneVerified: decodedToken['phone_number_verified'] == true,
      createdAt: iat,
      lastLoginAt: iat,
      metadata: metadata,
    );
  }

  static KeycloakUser deserialize(Map<String, dynamic> json) {
    return KeycloakUser(
      uid: json['uid'],
      email: json['email'],
      phoneNumber: json['phoneNumber'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      username: json['username'],
      emailVerified: json['emailVerified'] ?? false,
      phoneVerified: json['phoneVerified'] ?? false,
      isEnabled: json['isEnabled'] ?? true,
      createdAt: json['createdAt'],
      lastLoginAt: json['lastLoginAt'],
      metadata: json['metadata'] != null ? KeycloakUserMetadata.fromJson(json['metadata']) : null,
    );
  }
}
