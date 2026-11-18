import '../../core/app_exception.dart';
import '../models/social_models.dart';
import '../services/social_api.dart';
import 'text_rules.dart';

/// Run cards (feed and own history), kudos and comments.
class FeedRepository {
  FeedRepository({required SocialApi api}) : _api = api;
  final SocialApi _api;

  Future<PagedResult<RunCard>> feed({String? cursor}) => _api.feed(cursor: cursor);

  /// The caller's own runs, newest first.
  Future<PagedResult<RunCard>> history({String? cursor}) => _api.runHistory(cursor: cursor);

  /// Gives ([give] true) or removes kudos. Idempotent on the server.
  Future<KudosState> setKudos(String runId, bool give) =>
      give ? _api.giveKudos(runId) : _api.removeKudos(runId);

  Future<PagedResult<Comment>> comments(String runId, {String? cursor}) =>
      _api.comments(runId, cursor: cursor);

  /// The text a comment would be sent as, or an [AppException] saying what is wrong.
  static String checkComment(String raw) {
    final text = raw.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    if (text.isEmpty) throw const AppException('Write something first.');
    if (codePointLength(text) > maxCommentLength) {
      throw const AppException('Comments can have at most 500 characters.');
    }
    if (hasForbiddenCharacter(text)) throw const AppException('That text has characters that cannot be sent.');
    return text;
  }

  Future<Comment> addComment(String runId, String raw) => _api.addComment(runId, checkComment(raw));

  /// The author and the owner of the run may delete; a comment that is already gone is fine.
  Future<void> deleteComment(String runId, String commentId) => _api.deleteComment(runId, commentId);
}
