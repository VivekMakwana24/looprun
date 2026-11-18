/// The access token of the signed-in account, kept in memory for the API client.
///
/// [AuthRepository] writes it; the API client reads it for the Authorization header. It exists so the
/// API client does not read the auth repository, which is itself built from the API client: in debug
/// builds Riverpod rejects that loop with a CircularDependencyError on every request.
class SessionHolder {
  String? token;
}
