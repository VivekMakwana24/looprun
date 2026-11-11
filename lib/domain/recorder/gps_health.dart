enum GpsHealth {
  /// Not recording.
  inactive,

  /// Recording started, first fix not received yet, and the timeout has not passed.
  searching,

  /// Fixes are arriving.
  good,

  /// No fix for [GpsHealthMonitor.timeoutMs] or longer.
  lost,
}

/// Decides the GPS indicator from fix timestamps. Pure Dart; times are epoch milliseconds.
class GpsHealthMonitor {
  GpsHealthMonitor({this.timeoutMs = 15000});

  final int timeoutMs;
  int? _startedAt;
  int? _lastFixAt;

  void start(int nowMs) {
    _startedAt = nowMs;
    _lastFixAt = null;
  }

  void onFix(int nowMs) {
    if (_startedAt == null) return;
    _lastFixAt = nowMs;
  }

  void stop() {
    _startedAt = null;
    _lastFixAt = null;
  }

  GpsHealth evaluate(int nowMs) {
    final started = _startedAt;
    if (started == null) return GpsHealth.inactive;
    final last = _lastFixAt;
    final reference = last ?? started;
    if (nowMs - reference >= timeoutMs) return GpsHealth.lost;
    return last == null ? GpsHealth.searching : GpsHealth.good;
  }
}

/// Text for the foreground-service notification.
String notificationTextFor(GpsHealth health) {
  switch (health) {
    case GpsHealth.lost:
      return 'GPS signal lost. Check that location is on and you have a clear view of the sky.';
    case GpsHealth.searching:
      return 'Looking for GPS signal...';
    case GpsHealth.good:
    case GpsHealth.inactive:
      return 'Recording your run';
  }
}
