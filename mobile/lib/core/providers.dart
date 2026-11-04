import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/services/api_service.dart';
import '../data/db/app_database.dart';
import '../data/db/connection.dart';
import '../data/upload/drift_upload_store.dart';
import '../data/upload/upload_queue.dart';
import '../features/auth/auth_controller.dart';
import '../data/services/foreground_service.dart';
import '../features/run/run_controller.dart';
import 'config.dart';
import '../data/services/permission_service.dart';
import '../data/services/token_store.dart';

/// Overridden in main() (and in tests) with the loaded instance.
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider must be overridden'),
);

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// True only when built with --dart-define=DEV_AUTH=true. Tests override it.
final devAuthEnabledProvider = Provider<bool>((ref) => AppConfig.devAuth);

final permissionGatewayProvider =
    Provider<PermissionService>((ref) => DevicePermissionService());

final runServiceProvider = Provider<ForegroundService>((ref) => AndroidForegroundService());

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(openLooprunConnection());
  ref.onDispose(db.close);
  return db;
});

final apiClientProvider = Provider<ApiService>((ref) {
  return DioApiService(
    baseUrl: AppConfig.apiBaseUrl,
    tokenProvider: () => ref.read(authProvider).token,
    onUnauthorized: () {
      // Do not sign the user out in the middle of a run; the next request after the run will retry.
      if (ref.read(runControllerProvider).isActive) return;
      if (ref.read(authProvider).status == AuthStatus.signedIn) {
        ref.read(authProvider.notifier).signOut();
      }
    },
  );
});

final uploadQueueProvider = Provider<UploadQueue>((ref) {
  return UploadQueue(
    store: DriftUploadStore(ref.watch(databaseProvider)),
    api: ref.watch(apiClientProvider),
  );
});

/// Keeps the upload queue ticking while it is watched (the home screen watches it).
final uploadTickerProvider = Provider<void>((ref) {
  final queue = ref.watch(uploadQueueProvider);
  final timer = Timer.periodic(const Duration(seconds: 5), (_) {
    unawaited(queue.tick().catchError((Object _) => 0));
  });
  ref.onDispose(timer.cancel);
  unawaited(queue.tick().catchError((Object _) => 0));
});
