import '../models/social_models.dart';
import '../services/social_api.dart';

/// Summary and rivalry numbers together.
class BattleOverview {
  const BattleOverview({required this.summary, required this.rivalry});
  final BattleSummary summary;
  final Rivalry rivalry;
}

/// Cells taken and lost, rivalries and the "take it back" list.
class BattleRepository {
  BattleRepository({required SocialApi api}) : _api = api;
  final SocialApi _api;

  /// Last 7 days summary and the per-opponent list of the last [days] days, asked together.
  Future<BattleOverview> overview({int days = 30}) async {
    final results = await Future.wait<Object>([_api.battleSummary(), _api.rivalry(days: days)]);
    return BattleOverview(summary: results[0] as BattleSummary, rivalry: results[1] as Rivalry);
  }

  /// Cells lost in the last 7 days that somebody else (or nobody) holds now, newest first.
  /// Only cells that have a boundary or a centre can be drawn; the rest are dropped.
  Future<List<LostCell>> takeBack() async {
    final cells = await _api.takeBack();
    return [
      for (final c in cells)
        if (c.boundary.length >= 3 || (c.lat != null && c.lng != null)) c,
    ];
  }
}
