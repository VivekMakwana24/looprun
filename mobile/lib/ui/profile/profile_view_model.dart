import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';
import '../../data/models/api_exception.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/profile_repository.dart';

export '../../data/repositories/profile_repository.dart' show maxHomeZones;

/// Radii offered when adding a home zone (the server accepts 50..1000 m).
const List<double> homeZoneRadii = [100, 200, 500, 1000];

/// Lengths offered when starting rest days (the server accepts 1..30).
const List<int> restDayChoices = [7, 14, 30];

class ProfileState {
  const ProfileState({
    this.zones = const [],
    this.radiusM = 200,
    this.freeze,
    this.loading = false,
    this.loadFailed = false,
    this.busy = false,
    this.message,
    this.messageSeq = 0,
  });

  final List<HomeZone> zones;
  final double radiusM;

  /// Rest days (decay freeze) as the server last reported them; null until GET /me answered.
  final FreezeStatus? freeze;

  /// GET /me is running.
  final bool loading;

  /// GET /me failed: the zones shown are the copy on this phone and the rest-day quota is unknown.
  final bool loadFailed;
  final bool busy;

  /// One-shot text for a snackbar; [messageSeq] changes every time a new one is set.
  final String? message;
  final int messageSeq;

  /// Epoch ms until which the cells do not fade, or null.
  int? get freezeUntil => freeze?.freezeUntil;

  ProfileState copyWith({
    List<HomeZone>? zones,
    double? radiusM,
    FreezeStatus? freeze,
    bool? loading,
    bool? loadFailed,
    bool? busy,
    String? message,
    int? messageSeq,
  }) {
    return ProfileState(
      zones: zones ?? this.zones,
      radiusM: radiusM ?? this.radiusM,
      freeze: freeze ?? this.freeze,
      loading: loading ?? this.loading,
      loadFailed: loadFailed ?? this.loadFailed,
      busy: busy ?? this.busy,
      message: message ?? this.message,
      messageSeq: messageSeq ?? this.messageSeq,
    );
  }
}

/// View model of the "You" tab. Auto-disposed: every visit starts from the phone's copy of the zones
/// and asks the server (GET /me) for the current zones and rest-day quota.
class ProfileViewModel extends AutoDisposeNotifier<ProfileState> {
  bool _alive = true;
  Future<void>? _loading;

  @override
  ProfileState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    final zones = ref.watch(profileRepositoryProvider).homeZones();
    // Registered at once (not inside the microtask), so an action started right away waits for it.
    _track(Future<void>.microtask(_load));
    return ProfileState(zones: zones, loading: true);
  }

  void _track(Future<void> f) {
    _loading = f;
    unawaited(f.whenComplete(() {
      if (identical(_loading, f)) _loading = null;
    }));
  }

  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  void _set(ProfileState Function(ProfileState s) change) {
    if (_alive) state = change(state);
  }

  void setRadius(double radiusM) => state = state.copyWith(radiusM: radiusM);

  void _say(String text) {
    _set((s) => s.copyWith(message: text, messageSeq: s.messageSeq + 1));
  }

  /// Reads zones and rest days from the server. Also the "Try again" action after a failure.
  Future<void> load() {
    final running = _loading;
    if (running != null) return running;
    final f = _load();
    _track(f);
    return f;
  }

  Future<void> _load() async {
    _set((s) => s.copyWith(loading: true, loadFailed: false));
    try {
      final me = await _repo.loadMe();
      _set((s) => s.copyWith(zones: me.homeZones, freeze: me.freeze, loading: false, loadFailed: false));
    } catch (_) {
      _set((s) => s.copyWith(loading: false, loadFailed: true));
    }
  }

  /// Runs [action] with the busy flag set; turns failures into a message. Returns true on success.
  Future<bool> _run(Future<String?> Function() action, {String? Function(ApiException e)? onApiError}) async {
    // Let a running GET /me finish first, so its answer cannot overwrite what this action changes.
    final pending = _loading;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    if (!_alive) return false;
    state = state.copyWith(busy: true);
    var ok = false;
    try {
      final text = await action();
      if (text != null) _say(text);
      ok = true;
    } on ApiException catch (e) {
      _say(onApiError?.call(e) ??
          (e.isNetwork ? "Can't reach the server. Check your connection." : 'That did not work: ${e.message}'));
    } on AppException catch (e) {
      _say(e.message);
    } catch (_) {
      _say('Something went wrong. Please try again.');
    } finally {
      _set((s) => s.copyWith(busy: false));
    }
    return ok;
  }

  /// Adds a zone of [radiusM] (default: the selected radius) centred on where the phone is now.
  Future<void> addZoneHere([double? radiusM]) {
    return _run(() async {
      final zones = await _repo.addZoneHere(radiusM ?? state.radiusM);
      _set((s) => s.copyWith(zones: zones, radiusM: radiusM));
      return 'Zone added. Cells inside it never show your name.';
    });
  }

  /// Removes the zone at [index] (0-based, in the order shown).
  Future<void> removeZone(int index) {
    return _run(() async {
      final zones = await _repo.removeZoneAt(index);
      _set((s) => s.copyWith(zones: zones));
      return 'Zone removed.';
    });
  }

  Future<void> clearZones() {
    return _run(() async {
      final zones = await _repo.clearZones();
      _set((s) => s.copyWith(zones: zones));
      return 'All home zones removed.';
    });
  }

  /// Starts rest days (days > 0) or ends them (0).
  Future<void> setFreeze(int days) {
    return _run(
      () async {
        final status = await _repo.setFreeze(days);
        _set((s) => s.copyWith(freeze: status));
        return days == 0 ? 'Rest days ended. Your cells fade again.' : 'Your cells will not fade for $days days.';
      },
      onApiError: (e) => e.statusCode == 409
          ? 'You do not have that many rest days left. Try fewer days.'
          : null,
    );
  }

  /// False (with a message) while a run is being recorded: signing out would leave the recording
  /// running with nobody to save it for (review F7).
  bool _blockedByRun(String what) {
    if (!ref.read(runRepositoryProvider).isRecording) return false;
    _say('Finish your run before you $what.');
    return true;
  }

  Future<void> signOut() async {
    if (_blockedByRun('sign out')) return;
    await ref.read(authRepositoryProvider).signOut();
  }

  /// Deletes the account and local data, then signs out (the router then shows the sign-in screen).
  Future<void> deleteAccount() async {
    if (_blockedByRun('delete your account')) return;
    await _run(
      () async {
        await _repo.deleteAccount();
        _set((s) => s.copyWith(zones: const []));
        await ref.read(authRepositoryProvider).signOut();
        return null;
      },
      onApiError: (e) => e.statusCode == 503
          ? 'The server is busy. Your account is not deleted yet; please try again in a minute.'
          : null,
    );
  }
}

final profileViewModelProvider =
    NotifierProvider.autoDispose<ProfileViewModel, ProfileState>(ProfileViewModel.new);
