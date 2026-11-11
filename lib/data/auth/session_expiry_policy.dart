/// Decides when a 401 from the server may sign the user out. Pure Dart, no Flutter or IO.
///
/// A 401 must never end a run in progress, and it must not sign the user out in the middle of the
/// stop-and-upload that follows a run (the finished run stays queued and uploads after the next
/// sign-in, but the user should see their result first). Such a 401 is remembered and handled by
/// [recheck], which the upload ticker calls every few seconds.
class SessionExpiryPolicy {
  SessionExpiryPolicy({
    required bool Function() isRecording,
    required int? Function() lastStoppedAtMs,
    required void Function() expire,
    this.grace = const Duration(seconds: 30),
    int Function()? nowMs,
  })  : _isRecording = isRecording,
        _lastStoppedAtMs = lastStoppedAtMs,
        _expire = expire,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final bool Function() _isRecording;
  final int? Function() _lastStoppedAtMs;
  final void Function() _expire;
  final int Function() _nowMs;

  /// How long after a run stops that a 401 is held back.
  final Duration grace;

  bool _deferred = false;

  /// True when a 401 arrived but signing out was held back.
  bool get hasDeferred => _deferred;

  bool get _mustWait {
    if (_isRecording()) return true;
    final stopped = _lastStoppedAtMs();
    return stopped != null && _nowMs() - stopped < grace.inMilliseconds;
  }

  /// Called for every 401 response.
  void onUnauthorized() {
    if (_mustWait) {
      _deferred = true;
      return;
    }
    _deferred = false;
    _expire();
  }

  /// Signs out if a held-back 401 can be acted on now. Safe to call often.
  void recheck() {
    if (!_deferred || _mustWait) return;
    _deferred = false;
    _expire();
  }

  /// A new session started; an old 401 no longer applies.
  void clear() => _deferred = false;
}
