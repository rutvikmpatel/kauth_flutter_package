class KeycloakTokenResponse {
  // ignore: non_constant_identifier_names
  final String access_token;
  // ignore: non_constant_identifier_names
  final String? refresh_token;
  // ignore: non_constant_identifier_names
  final int? expires_in;
  // ignore: non_constant_identifier_names
  final String? token_type;
  final String? scope;
  // ignore: non_constant_identifier_names
  final String? id_token;

  KeycloakTokenResponse({
    // ignore: non_constant_identifier_names
    required this.access_token,
    // ignore: non_constant_identifier_names
    this.refresh_token,
    // ignore: non_constant_identifier_names
    this.expires_in,
    // ignore: non_constant_identifier_names
    this.token_type = "Bearer",
    this.scope,
    // ignore: non_constant_identifier_names
    this.id_token,
  });

  factory KeycloakTokenResponse.fromJson(Map<String, dynamic> json) {
    return KeycloakTokenResponse(
      access_token: json['access_token'],
      refresh_token: json['refresh_token'],
      expires_in: json['expires_in'],
      token_type: json['token_type'],
      scope: json['scope'],
      id_token: json['id_token'],
    );
  }
}
