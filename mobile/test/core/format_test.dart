import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/core/format.dart';

void main() {
  test('pace from the server, in m:ss', () {
    expect(formatPaceSeconds(317.3), '5:17');
    expect(formatPaceSeconds(null), noValue);
    expect(formatPaceSeconds(0), noValue);
    expect(formatPaceSeconds(3600), noValue);
    expect(formatPaceSeconds(double.infinity), noValue);
  });

  test('moving time', () {
    expect(formatMovingSeconds(1650), '27:30');
    expect(formatMovingSeconds(3725), '1:02:05');
    expect(formatMovingSeconds(null), noValue);
  });

  test('relative time', () {
    final now = DateTime(2026, 11, 18, 12);
    expect(formatAgo(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
    expect(formatAgo(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
    expect(formatAgo(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
    expect(formatAgo(now.subtract(const Duration(days: 2)), now: now), '2 d ago');
    expect(formatAgo(DateTime(2026, 11, 1), now: now), '1 Nov');
  });

  test('initials', () {
    expect(initialsOf('Anna Lee'), 'AL');
    expect(initialsOf('mia'), 'M');
    expect(initialsOf('Runner-1a2b'), 'R1');
    expect(initialsOf('  '), '?');
    expect(initialsOf(''), '?');
    expect(initialsOf('émile zola'), 'ÉZ');
  });
}
