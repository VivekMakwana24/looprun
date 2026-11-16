import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config.dart';
import 'data/providers.dart';
import 'data/services/foreground_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    final problems = currentReleaseConfigProblems();
    if (problems.isNotEmpty) {
      runApp(ConfigErrorApp(problems: problems));
      return;
    }
  }
  initForegroundTask();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [preferencesProvider.overrideWithValue(prefs)],
    child: const LooprunApp(),
  ));
}
