import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/recorder/gps_health.dart';

void main() {
  test('inactive until started', () {
    final m = GpsHealthMonitor();
    expect(m.evaluate(0), GpsHealth.inactive);
    m.onFix(10); // ignored
    expect(m.evaluate(20), GpsHealth.inactive);
  });

  test('searching right after start, lost after 15 s without a first fix', () {
    final m = GpsHealthMonitor()..start(1000);
    expect(m.evaluate(1000), GpsHealth.searching);
    expect(m.evaluate(1000 + 14999), GpsHealth.searching);
    expect(m.evaluate(1000 + 15000), GpsHealth.lost);
  });

  test('good while fixes arrive, lost 15 s after the last one', () {
    final m = GpsHealthMonitor()..start(0);
    m.onFix(2000);
    expect(m.evaluate(3000), GpsHealth.good);
    expect(m.evaluate(2000 + 14999), GpsHealth.good);
    expect(m.evaluate(2000 + 15000), GpsHealth.lost);
  });

  test('recovers to good when a fix arrives again', () {
    final m = GpsHealthMonitor()..start(0);
    m.onFix(1000);
    expect(m.evaluate(30000), GpsHealth.lost);
    m.onFix(30500);
    expect(m.evaluate(31000), GpsHealth.good);
  });

  test('stop returns to inactive', () {
    final m = GpsHealthMonitor()..start(0);
    m.onFix(100);
    m.stop();
    expect(m.evaluate(200), GpsHealth.inactive);
  });

  test('timeout can be changed', () {
    final m = GpsHealthMonitor(timeoutMs: 5000)..start(0);
    m.onFix(0);
    expect(m.evaluate(4999), GpsHealth.good);
    expect(m.evaluate(5000), GpsHealth.lost);
  });

  test('notification text says GPS signal lost when lost', () {
    expect(notificationTextFor(GpsHealth.lost), contains('GPS signal lost'));
    expect(notificationTextFor(GpsHealth.good), isNot(contains('lost')));
  });
}
