import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/social_models.dart';
import '../../data/providers.dart';
import '../../data/repositories/report_repository.dart';
import 'error_text.dart';

export '../../data/repositories/report_repository.dart' show ReportKind;

/// The result of an action: a value, or a sentence for the user.
class Outcome<T> {
  const Outcome.ok([this.value]) : error = null;
  const Outcome.failed(String message)
      : value = null,
        error = message;
  final T? value;
  final String? error;
  bool get ok => error == null;
}

/// What the block dialogs say (spec 10): hidden in the feed, comments and search, but still on the map and board.
const String blockExplanation = 'You will not see each other in the feed, comments or search. You stop following each other. '
    'A blocked runner still appears as an owner on the map and on the leaderboard. '
    'You can still report them from BLOCKED in YOU.';

/// Follow, block, unblock and report, shared by every screen that offers them (profile, comment, run card,
/// lists). Stateless: the screens keep their own state.
class SocialActions extends Notifier<void> {
  @override
  void build() {}

  Future<Outcome<FollowState>> setFollowing(String userId, bool follow) async {
    try {
      return Outcome.ok(await ref.read(userRepositoryProvider).setFollowing(userId, follow));
    } catch (e) {
      return Outcome.failed(errorText(e));
    }
  }

  Future<Outcome<Object?>> block(String userId) async {
    try {
      await ref.read(userRepositoryProvider).block(userId);
      return const Outcome.ok();
    } catch (e) {
      return Outcome.failed(errorText(e));
    }
  }

  Future<Outcome<Object?>> unblock(String userId) async {
    try {
      await ref.read(userRepositoryProvider).unblock(userId);
      return const Outcome.ok();
    } catch (e) {
      return Outcome.failed(errorText(e));
    }
  }

  /// [kind] is one of [ReportKind].
  Future<Outcome<Object?>> report(String kind, String targetId, String reason) async {
    try {
      await ref.read(reportRepositoryProvider).submit(kind: kind, targetId: targetId, reason: reason);
      return const Outcome.ok();
    } catch (e) {
      return Outcome.failed(errorText(e));
    }
  }
}

final socialActionsProvider = NotifierProvider<SocialActions, void>(SocialActions.new);
