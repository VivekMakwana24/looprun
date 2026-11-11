import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/auth/session_expiry_policy.dart';

void main() {
  late int now;
  late bool recording;
  late int? stoppedAt;
  late int expired;
  late SessionExpiryPolicy policy;

  setUp(() {
    now = 1000000;
    recording = false;
    stoppedAt = null;
    expired = 0;
    policy = SessionExpiryPolicy(
      isRecording: () => recording,
      lastStoppedAtMs: () => stoppedAt,
      expire: () => expired++,
      grace: const Duration(seconds: 30),
      nowMs: () => now,
    );
  });

  test('a 401 with no run around signs out at once', () {
    policy.onUnauthorized();
    expect(expired, 1);
    expect(policy.hasDeferred, isFalse);
  });

  test('a 401 while recording is held back and not forgotten', () {
    recording = true;
    policy.onUnauthorized();
    expect(expired, 0);
    expect(policy.hasDeferred, isTrue);

    policy.recheck();
    expect(expired, 0, reason: 'still recording');

    recording = false;
    now += 60000; // not stopped recently either
    policy.recheck();
    expect(expired, 1);
    expect(policy.hasDeferred, isFalse);
  });

  test('a 401 right after stop is held until the grace window has passed', () {
    stoppedAt = now - 2000;
    policy.onUnauthorized();
    expect(expired, 0);

    now += 20000;
    policy.recheck();
    expect(expired, 0);

    now += 11000; // 33 s after stop
    policy.recheck();
    expect(expired, 1);
  });

  test('recheck does nothing without a held-back 401', () {
    policy.recheck();
    expect(expired, 0);
  });

  test('a new sign-in drops a held-back 401', () {
    recording = true;
    policy.onUnauthorized();
    policy.clear();
    recording = false;
    policy.recheck();
    expect(expired, 0);
  });

  test('repeated 401s sign out once per call outside a run, never during one', () {
    recording = true;
    policy.onUnauthorized();
    policy.onUnauthorized();
    expect(expired, 0);
  });
}
