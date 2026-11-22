/// Default location of the Cricket backend (IIS deployment).
/// Endpoints are documented in docs/BACKEND_API_SPEC.md and live Swagger at
/// https://www.saras.ind.in/CricketAPI/swagger/index.html
class ApiConfig {
  static const String host = 'https://www.saras.ind.in/CricketAPI';
  static const String baseUrl = '$host/api/v1';
  static const Duration timeout = Duration(seconds: 20);

  static Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);
}
