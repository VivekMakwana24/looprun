import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/domain/recorder/run_recorder.dart';

void main() {
  late int now;
  late int idCounter;
  late RunRecorder r;

  GeoFix fix(double lat, double lng, {double acc = 5, int? t}) =>
      GeoFix(lat: lat, lng: lng, t: t ?? now, acc: acc);

  setUp(() {
    now = 1000000;
    idCounter = 0;
    r = RunRecorder(nowMs: () => now, newId: () => 'run-${idCounter++}');
  });

  test('starts idle with no run', () {
    expect(r.status, RecorderStatus.idle);
    expect(r.runId, isNull);
    expect(r.isActive, isFalse);
  });

  test('start moves to recording and assigns id and start time', () {
    r.start();
    expect(r.status, RecorderStatus.recording);
    expect(r.runId, 'run-0');
    expect(r.startedAt, 1000000);
  });

  test('fixes are ignored unless recording', () {
    expect(r.addFix(fix(0, 0)), isFalse);
    r.start();
    expect(r.addFix(fix(0, 0)), isTrue);
    r.pause();
    expect(r.addFix(fix(0, 0.001)), isFalse);
    expect(r.fixCount, 1);
  });

  test('pause, resume and finish transitions', () {
    r.start();
    r.pause();
    expect(r.status, RecorderStatus.paused);
    r.resume();
    expect(r.status, RecorderStatus.recording);
    now += 5000;
    r.stop();
    expect(r.status, RecorderStatus.stopping);
    expect(r.endedAt, now);
    r.finish();
    expect(r.status, RecorderStatus.finished);
  });

  test('can stop straight from paused', () {
    r.start();
    r.pause();
    r.stop();
    expect(r.status, RecorderStatus.stopping);
    r.finish();
    expect(r.status, RecorderStatus.finished);
  });

  test('stopping accepts no more fixes and cannot be reset or restarted', () {
    r.start();
    expect(r.addFix(fix(0, 0)), isTrue);
    r.stop();
    expect(r.addFix(fix(0, 0.001)), isFalse);
    expect(r.fixCount, 1);
    expect(() => r.reset(), throwsStateError);
    expect(() => r.start(), throwsStateError);
    expect(() => r.pause(), throwsStateError);
    expect(() => r.stop(), throwsStateError);
    expect(r.isActive, isFalse);
  });

  test('finish is only allowed from stopping', () {
    expect(() => r.finish(), throwsStateError);
    r.start();
    expect(() => r.finish(), throwsStateError);
  });

  test('illegal transitions throw StateError', () {
    expect(() => r.pause(), throwsStateError);
    expect(() => r.resume(), throwsStateError);
    expect(() => r.finish(), throwsStateError);
    expect(() => r.stop(), throwsStateError);
    r.start();
    expect(() => r.start(), throwsStateError);
    expect(() => r.resume(), throwsStateError);
    expect(() => r.reset(), throwsStateError);
    r.stop();
    r.finish();
    expect(() => r.start(), throwsStateError);
    expect(() => r.pause(), throwsStateError);
  });

  test('distance accumulates between accurate fixes', () {
    r.start();
    r.addFix(fix(0, 0));
    r.addFix(fix(0, 0.001));
    r.addFix(fix(0, 0.002));
    expect(r.distanceM, closeTo(222.4, 1.0));
    expect(r.fixCount, 3);
  });

  test('poor accuracy fixes are counted as fixes but not as distance', () {
    r.start();
    r.addFix(fix(0, 0));
    r.addFix(fix(0, 0.01, acc: 200));
    expect(r.fixCount, 2);
    expect(r.distanceM, 0);
  });

  test('the straight line across a pause is not counted', () {
    r.start();
    r.addFix(fix(0, 0));
    r.pause();
    r.resume();
    r.addFix(fix(0, 0.01));
    expect(r.distanceM, 0);
    r.addFix(fix(0, 0.011));
    expect(r.distanceM, closeTo(111.2, 1.0));
  });

  test('elapsed time excludes paused time', () {
    r.start();
    now += 10000;
    expect(r.elapsedMs, 10000);
    r.pause();
    now += 60000;
    expect(r.elapsedMs, 10000);
    r.resume();
    now += 5000;
    expect(r.elapsedMs, 15000);
    r.stop();
    r.finish();
    now += 99999;
    expect(r.elapsedMs, 15000);
  });

  test('reset after finish returns to idle with a fresh id on next start', () {
    r.start();
    r.addFix(fix(0, 0));
    r.stop();
    r.finish();
    r.reset();
    expect(r.status, RecorderStatus.idle);
    expect(r.fixCount, 0);
    expect(r.distanceM, 0);
    r.start();
    expect(r.runId, 'run-1');
  });
}
