import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/social_models.dart';
import '../../data/providers.dart';
import '../../data/repositories/battle_repository.dart';
import '../auth/auth_view_model.dart';
import '../core/error_text.dart';

class BattlesState {
  const BattlesState({this.overview, this.loading = false, this.error, this.offline = false});

  final BattleOverview? overview;
  final bool loading;
  final String? error;
  final bool offline;

  BattlesState copyWith({
    BattleOverview? overview,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? offline,
  }) {
    return BattlesState(
      overview: overview ?? this.overview,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      offline: offline ?? this.offline,
    );
  }
}

/// Battles summary (7 days) and the rivalry list (30 days).
class BattlesViewModel extends AutoDisposeNotifier<BattlesState> {
  bool _alive = true;
  int _seq = 0;

  @override
  BattlesState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    ref.watch(authViewModelProvider.select((s) => s.user?.id));
    Future<void>.microtask(refresh);
    return const BattlesState(loading: true);
  }

  Future<void> refresh() async {
    final seq = ++_seq;
    if (_alive) state = state.copyWith(loading: true, clearError: true);
    try {
      final o = await ref.read(battleRepositoryProvider).overview();
      if (_alive && seq == _seq) state = BattlesState(overview: o);
    } catch (e) {
      if (_alive && seq == _seq) state = state.copyWith(loading: false, error: errorText(e), offline: isOffline(e));
    }
  }
}

final battlesViewModelProvider =
    NotifierProvider.autoDispose<BattlesViewModel, BattlesState>(BattlesViewModel.new);

// ---------------------------------------------------------------- take it back

class TakeBackState {
  const TakeBackState({
    this.cells = const [],
    this.loading = false,
    this.error,
    this.offline = false,
    this.shown = false,
    this.focus,
    this.focusSeq = 0,
  });

  /// Cells lost in the last 7 days that somebody else holds now.
  final List<LostCell> cells;
  final bool loading;
  final String? error;
  final bool offline;

  /// The map draws the lost cells.
  final bool shown;

  /// Where the map should look when [focusSeq] changes.
  final LostCell? focus;
  final int focusSeq;

  TakeBackState copyWith({
    List<LostCell>? cells,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? offline,
    bool? shown,
    LostCell? focus,
    int? focusSeq,
  }) {
    return TakeBackState(
      cells: cells ?? this.cells,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      offline: offline ?? this.offline,
      shown: shown ?? this.shown,
      focus: focus ?? this.focus,
      focusSeq: focusSeq ?? this.focusSeq,
    );
  }
}

/// The "take it back" list: cells the caller lost in the last 7 days. The map draws them from their boundaries.
/// Failures are quiet on the map (no notice); the sheet offers "Try again".
class TakeBackViewModel extends AutoDisposeNotifier<TakeBackState> {
  bool _alive = true;
  int _seq = 0;

  @override
  TakeBackState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    ref.watch(authViewModelProvider.select((s) => s.user?.id));
    Future<void>.microtask(refresh);
    return const TakeBackState(loading: true);
  }

  Future<void> refresh() async {
    final seq = ++_seq;
    if (_alive) state = state.copyWith(loading: true, clearError: true);
    try {
      final cells = await ref.read(battleRepositoryProvider).takeBack();
      if (!_alive || seq != _seq) return;
      state = state.copyWith(cells: cells, loading: false, offline: false);
    } catch (e) {
      if (_alive && seq == _seq) state = state.copyWith(loading: false, error: errorText(e), offline: isOffline(e));
    }
  }

  /// Draws (or hides) the lost cells on the map. Showing also moves the camera to the newest one.
  void setShown(bool shown) {
    if (shown && state.cells.isNotEmpty) {
      state = state.copyWith(shown: true, focus: state.cells.first, focusSeq: state.focusSeq + 1);
    } else {
      state = state.copyWith(shown: shown && state.cells.isNotEmpty);
    }
  }

  /// Moves the map to one lost cell and makes sure they are drawn.
  void focusOn(LostCell cell) {
    state = state.copyWith(shown: true, focus: cell, focusSeq: state.focusSeq + 1);
  }
}

final takeBackViewModelProvider =
    NotifierProvider.autoDispose<TakeBackViewModel, TakeBackState>(TakeBackViewModel.new);
