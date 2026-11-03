/// Error from the API layer. [statusCode] is null for network failures (no response).
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int? statusCode;
  final String message;

  bool get isNetwork => statusCode == null;

  @override
  String toString() => 'ApiException($statusCode, $message)';
}
