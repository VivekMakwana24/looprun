import '../../core/app_exception.dart';
import '../../data/models/api_exception.dart';

/// A sentence for the user for anything that went wrong in a social call. Never the raw exception.
String errorText(Object error) {
  if (error is ApiException) return error.friendlyMessage;
  if (error is AppException) return error.message;
  return 'Something went wrong. Try again.';
}

/// True when the error is "no answer from the server".
bool isOffline(Object error) => error is ApiException && error.isNetwork;
