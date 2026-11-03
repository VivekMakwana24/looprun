import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/upload/backoff.dart';

void main() {
  const policy = BackoffPolicy();

  test('delay doubles per failure', () {
    expect(policy.delayFor(1), const Duration(seconds: 2));
    expect(policy.delayFor(2), const Duration(seconds: 4));
    expect(policy.delayFor(3), const Duration(seconds: 8));
    expect(policy.delayFor(4), const Duration(seconds: 16));
  });

  test('delay is capped at max', () {
    expect(policy.delayFor(10), const Duration(minutes: 5));
    expect(policy.delayFor(500), const Duration(minutes: 5));
  });

  test('failure count below 1 is treated as 1', () {
    expect(policy.delayFor(0), const Duration(seconds: 2));
  });

  test('jitter stays inside the band and under max', () {
    const j = BackoffPolicy(jitter: 0.5);
    expect(j.delayFor(3, random: () => 0.0), const Duration(seconds: 4));
    expect(j.delayFor(3, random: () => 0.5), const Duration(seconds: 8));
    expect(j.delayFor(3, random: () => 1.0), const Duration(seconds: 12));
    expect(j.delayFor(12, random: () => 1.0), const Duration(minutes: 5));
  });

  test('retryable statuses', () {
    expect(BackoffPolicy.isRetryableStatus(null), isTrue);
    expect(BackoffPolicy.isRetryableStatus(408), isTrue);
    expect(BackoffPolicy.isRetryableStatus(429), isTrue);
    expect(BackoffPolicy.isRetryableStatus(500), isTrue);
    expect(BackoffPolicy.isRetryableStatus(503), isTrue);
    expect(BackoffPolicy.isRetryableStatus(401), isFalse);
    expect(BackoffPolicy.isRetryableStatus(404), isFalse);
    expect(BackoffPolicy.isRetryableStatus(413), isFalse);
    expect(BackoffPolicy.isRetryableStatus(422), isFalse);
  });

  test('shouldRetry stops at maxAttempts', () {
    const p = BackoffPolicy(maxAttempts: 3);
    expect(p.shouldRetry(null, 1), isTrue);
    expect(p.shouldRetry(null, 2), isTrue);
    expect(p.shouldRetry(null, 3), isFalse);
    expect(p.shouldRetry(422, 1), isFalse);
  });
}
