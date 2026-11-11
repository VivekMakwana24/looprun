import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// State: whether the location disclosure was accepted on this phone.
class DisclosureViewModel extends Notifier<bool> {
  @override
  bool build() => ref.watch(profileRepositoryProvider).disclosureAccepted;

  /// Asks for the location permission (the system prompt), then records the acceptance.
  /// Only the "Agree and continue" button calls this, so nothing is requested before the user read the text.
  Future<void> accept() async {
    try {
      await ref.read(locationRepositoryProvider).requestPermission();
    } catch (_) {
      // Location is asked for again when a run starts, so do not block the user here.
    }
    await ref.read(profileRepositoryProvider).acceptDisclosure();
    state = true;
  }
}

final disclosureViewModelProvider =
    NotifierProvider<DisclosureViewModel, bool>(DisclosureViewModel.new);
