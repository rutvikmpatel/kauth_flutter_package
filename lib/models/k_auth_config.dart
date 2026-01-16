class KAuthConfig {
  final String baseUrl;

  const KAuthConfig({
    required this.baseUrl,
  });

  factory KAuthConfig.defaults() {
    return const KAuthConfig(
      baseUrl: "https://auth.keshavonline.com",
    );
  }
}
