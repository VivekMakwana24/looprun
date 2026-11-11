import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/ui/core/flag_text.dart';

void main() {
  test('known flags get plain-language text', () {
    final f = Flag.fromJson({'code': 'mock_location', 'severity': 'hard', 'detail': ''});
    expect(describeFlag(f), contains('mock'));
  });

  test('unknown flag falls back to detail then code', () {
    expect(describeFlag(const Flag(code: 'x_new', severity: 'soft', detail: 'hello')), 'hello');
    expect(describeFlag(const Flag(code: 'x_new', severity: 'soft', detail: '')), 'x_new');
  });
}
