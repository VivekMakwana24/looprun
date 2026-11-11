import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';
import '../../data/models/api_exception.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/profile_repository.dart';

export '../../data/repositories/profile_repository.dart' show maxHomeZones;

class ProfileState {
  const ProfileState({
    this.zones = const [],
    this.radiusM = 200,
    this.freezeUntil,
    this.busy = false,
    this.message,
    this.messageSeq = 0,
  });

  final List<HomeZone> zones;
  final double radiusM;

  /// Epoch ms, or null.
  final int? freezeUntil;
  final bool busy;

  /// One-shot text for a snackbar; [messageSeq] changes every time a new one is set.
  final String? message;
  final int messageSeq;

  ProfileState copyWith({
    List<HomeZone>? zones,
    double? radiusM,
    int? freezeUntil,
    bool clearFreeze = false,
    bool? busy,
    String? message,
    int? messageSeq,
  }) {
    return ProfileState(
      zones: zones ?? this.zones,
      radiusM: radiusM ?? this.radiusM,
      freezeUntil: clearFreeze ? null : (freezeUntil ?? this.freezeUntil),
      busy: busy ?? this.busy,
      message: message ?? this.message,
      messageSeq: messageSeq ?? this.messageSeq,
    );
  }
}

class ProfileViewModel extends Notifier<ProfileState> {
  @override
  ProfileState build() => ProfileState(zones: ref.watch(profileRepositoryProvider).homeZones());

  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  void setRadius(double radiusM) => state = state.copyWith(radiusM: radiusM);

  void _say(String text) {
    state = state.copyWith(message: text, messageSeq: state.messageSeq + 1);
  }

  /// Runs [action] with the busy flag set; turns failures into a message. Returns true on success.
  Future<bool> _run(Future<String?> Function() action) async {
    state = state.copyWith(busy: true);
    var ok = false;
    try {
      final text = await action();
      if (text != null) _say(text);
      ok = true;
    } on ApiException catch (e) {
      _say('Request failed: ${e.message}');
    } on AppException catch (e) {
      _say(e.message);
    } catch (e) {
      _say('Something went wrong: $e');
    } finally {
      state = state.copyWith(busy: false);
    }
    return ok;
  }

  Future<void> addZoneHere() {
    return _run(() async {
      final zones = await _repo.addZoneHere(state.radiusM);
      state = state.copyWith(zones: zones);
      return 'Zone added. Cells inside it never show your name.';
    });
  }

  Future<void> clearZones() {
    return _run(() async {
      final zones = await _repo.clearZones();
      state = state.copyWith(zones: zones);
      return 'All home zones removed.';
    });
  }

  /// days 0 ends the freeze.
  Future<void> setFreeze(int days) {
    return _run(() async {
      final until = await _repo.setFreeze(days);
      state = until == null ? state.copyWith(clearFreeze: true) : state.copyWith(freezeUntil: until);
      return days == 0 ? 'Freeze ended.' : 'Your cells will not decay for $days days.';
    });
  }

  /// Deletes the account and local data, then signs out (the router then shows the sign-in screen).
  Future<void> deleteAccount() {
    return _run(() async {
      await _repo.deleteAccount();
      state = state.copyWith(zones: const []);
      await ref.read(authRepositoryProvider).signOut();
      return null;
    });
  }
}

final profileViewModelProvider =
    NotifierProvider<ProfileViewModel, ProfileState>(ProfileViewModel.new);
