/// An error whose [message] can be shown to the user as it is.
class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}
