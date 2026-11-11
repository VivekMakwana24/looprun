import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces the layering rules of docs/MOBILE_ARCHITECTURE.md ("Rules that CI and reviews enforce").
/// flutter test runs with the package root as working directory.
List<File> _dartFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      .toList();
}

List<String> _imports(File f) {
  final re = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);
  return re.allMatches(f.readAsStringSync()).map((m) => m.group(1)!).toList();
}

String _name(File f) => f.path.replaceAll('\\', '/');

void main() {
  test('ui never imports data/services or data/db', () {
    final bad = <String>[];
    for (final f in _dartFiles('lib/ui')) {
      for (final i in _imports(f)) {
        if (i.contains('data/services/') || i.contains('data/db/')) bad.add('${_name(f)} -> $i');
      }
    }
    expect(bad, isEmpty);
  });

  test('views (screens, sheets, dialogs) import view models, not providers or repositories', () {
    final bad = <String>[];
    for (final f in _dartFiles('lib/ui')) {
      final n = _name(f);
      final isView = n.endsWith('_screen.dart') || n.endsWith('_sheet.dart') || n.endsWith('_dialog.dart');
      if (!isView) continue;
      for (final i in _imports(f)) {
        if (i.contains('data/providers.dart') ||
            i.contains('data/repositories/') ||
            i.contains('data/upload/')) {
          bad.add('$n -> $i');
        }
      }
    }
    expect(bad, isEmpty);
  });

  test('domain imports nothing from Flutter or from data', () {
    final bad = <String>[];
    for (final f in _dartFiles('lib/domain')) {
      for (final i in _imports(f)) {
        if (i.startsWith('package:flutter') ||
            i.startsWith('dart:ui') ||
            i.contains('/data/') ||
            i.contains('/ui/')) {
          bad.add('${_name(f)} -> $i');
        }
      }
    }
    expect(bad, isEmpty);
  });

  test('repositories do not import each other', () {
    final bad = <String>[];
    for (final f in _dartFiles('lib/data/repositories')) {
      for (final i in _imports(f)) {
        if (i.contains('_repository.dart')) bad.add('${_name(f)} -> $i');
      }
    }
    expect(bad, isEmpty);
  });

  test('no BuildContext in view models or repositories', () {
    final bad = <String>[];
    final files = [
      ..._dartFiles('lib/data/repositories'),
      ..._dartFiles('lib/ui').where((f) => _name(f).endsWith('_view_model.dart')),
    ];
    for (final f in files) {
      if (f.readAsStringSync().contains('BuildContext')) bad.add(_name(f));
    }
    expect(bad, isEmpty);
  });

  test('data layer does not import ui', () {
    final bad = <String>[];
    for (final f in _dartFiles('lib/data')) {
      for (final i in _imports(f)) {
        if (i.contains('/ui/') || i.startsWith('../ui') || i.contains('../../ui')) {
          bad.add('${_name(f)} -> $i');
        }
      }
    }
    expect(bad, isEmpty);
  });
}
