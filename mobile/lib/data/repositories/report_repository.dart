import '../../core/app_exception.dart';
import '../services/api_service.dart';
import 'text_rules.dart';

/// What can be reported. `run` and `cell` are older kinds (cells are reported from the map).
class ReportKind {
  const ReportKind._();
  static const user = 'user';
  static const comment = 'comment';
  static const runCard = 'run_card';
  static const cell = 'cell';
}

class ReportRepository {
  ReportRepository({required ApiService api}) : _api = api;
  final ApiService _api;

  /// POST /reports. The server answers 202 also for a repeat report of the same target.
  Future<void> submit({required String kind, required String targetId, required String reason}) {
    final text = reason.trim();
    if (text.isEmpty) throw const AppException('Tell us what is wrong.');
    final cut = codePointLength(text) > maxReasonLength
        ? String.fromCharCodes(text.runes.take(maxReasonLength))
        : text;
    return _api.report(kind: kind, targetId: targetId, reason: cut);
  }
}
