/// Error from the API layer. [statusCode] is null when there is no HTTP status to report: either no answer
/// at all (network failure, [isNetwork]) or an answer the app could not read ([malformed]).
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.malformed = false, this.code});

  /// The server answered, but the body did not have the shape of the contract (a bug or a proxy page).
  /// Not a connection problem, so it must not be reported as one (review follow-up 7).
  const ApiException.malformed(this.message)
      : statusCode = null,
        malformed = true,
        code = null;

  final int? statusCode;
  final String message;
  final bool malformed;

  /// The `code` slug of a Phase 1a error body (`{"detail": {"code": ..., "message": ...}}`), or null.
  final String? code;

  /// No answer from the server at all.
  bool get isNetwork => statusCode == null && !malformed;

  /// A sentence for the user. Never the raw server text for the cases the app knows.
  String get friendlyMessage {
    if (malformed) return 'The server sent something this version of Looprun cannot read.';
    if (isNetwork) return "Can't reach the server. Check your connection.";
    switch (code) {
      case 'follow_limit':
        return 'You follow as many people as you can (500). Unfollow someone first.';
      case 'block_limit':
        return 'You have blocked as many people as you can (500).';
      case 'comment_limit':
        return 'This run has reached its limit of 200 comments.';
      case 'own_run':
        return 'You cannot give kudos to your own run.';
      case 'self':
        return 'That is not possible on your own account.';
      case 'name_rejected':
        return 'That name cannot be used. Try another one.';
    }
    switch (statusCode) {
      case 401:
        return 'Please sign in again.';
      case 403:
        return 'This account is being deleted.';
      case 404:
        return 'That is not available any more.';
      case 409:
        return 'That is not possible right now.';
      case 422:
        return 'That was not accepted. Check what you typed.';
      case 429:
        return 'Too many tries. Wait a little and try again.';
    }
    final s = statusCode;
    if (s != null && s >= 500) return 'The server is busy. Try again in a moment.';
    return 'Something went wrong. Try again.';
  }

  @override
  String toString() => 'ApiException(${malformed ? 'malformed' : statusCode}, $message)';
}
