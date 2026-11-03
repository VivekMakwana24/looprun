/// Pure exponential backoff policy. No Flutter or IO imports.
class BackoffPolicy {
  const BackoffPolicy({
    this.base = const Duration(seconds: 2),
    this.max = const Duration(minutes: 5),
    this.maxAttempts = 12,
    this.jitter = 0.0,
  });

  final Duration base;
  final Duration max;

  /// Failures allowed before the job is given up (and shown as failed to the user).
  final int maxAttempts;

  /// 0..1: fraction by which the delay may vary randomly (0 = deterministic).
  final double jitter;

  /// Delay after the [failureCount]-th consecutive failure (1 = first failure).
  /// [random] returns a value in [0, 1) and is only used when [jitter] > 0.
  Duration delayFor(int failureCount, {double Function()? random}) {
    final n = failureCount < 1 ? 1 : failureCount;
    final shift = n - 1 > 20 ? 20 : n - 1;
    var ms = base.inMilliseconds * (1 << shift);
    if (jitter > 0 && random != null) {
      final factor = 1 + jitter * (random() * 2 - 1);
      ms = (ms * factor).round();
    }
    if (ms > max.inMilliseconds) ms = max.inMilliseconds;
    if (ms < 0) ms = 0;
    return Duration(milliseconds: ms);
  }

  /// Network failures, timeouts, 408/425/429 and 5xx are worth retrying.
  /// Other 4xx (including 401, 413 and 422) will not get better by retrying.
  static bool isRetryableStatus(int? statusCode) {
    if (statusCode == null) return true;
    if (statusCode == 408 || statusCode == 425 || statusCode == 429) return true;
    return statusCode >= 500;
  }

  /// [failuresSoFar] counts the failure that just happened.
  bool shouldRetry(int? statusCode, int failuresSoFar) {
    return isRetryableStatus(statusCode) && failuresSoFar < maxAttempts;
  }
}
