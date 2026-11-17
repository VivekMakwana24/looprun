/// Error from the API layer. [statusCode] is null when there is no HTTP status to report: either no answer
/// at all (network failure, [isNetwork]) or an answer the app could not read ([malformed]).
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.malformed = false});

  /// The server answered, but the body did not have the shape of the contract (a bug or a proxy page).
  /// Not a connection problem, so it must not be reported as one (review follow-up 7).
  const ApiException.malformed(this.message)
      : statusCode = null,
        malformed = true;

  final int? statusCode;
  final String message;
  final bool malformed;

  /// No answer from the server at all.
  bool get isNetwork => statusCode == null && !malformed;

  @override
  String toString() => 'ApiException(${malformed ? 'malformed' : statusCode}, $message)';
}
