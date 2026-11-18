import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/user_repository.dart';
import '../core/error_text.dart';

/// Edit display name. Checks the text, asks the server (PATCH /me) and keeps the new name for the app.
class RenameViewModel extends Notifier<bool> {
  /// True while the request runs.
  @override
  bool build() => false;

  /// Returns a sentence for the user when the name was not changed, else null.
  Future<String?> rename(String raw) async {
    if (state) return null;
    final String checked;
    try {
      checked = UserRepository.checkDisplayName(raw);
    } catch (e) {
      return errorText(e);
    }
    state = true;
    try {
      final user = await ref.read(userRepositoryProvider).rename(checked);
      await ref.read(authRepositoryProvider).updateUserName(user);
      return null;
    } catch (e) {
      return errorText(e);
    } finally {
      state = false;
    }
  }
}

final renameViewModelProvider = NotifierProvider<RenameViewModel, bool>(RenameViewModel.new);
