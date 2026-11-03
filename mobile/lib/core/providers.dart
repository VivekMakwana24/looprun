import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api/api_client.dart';
import '../data/db/app_database.dart';
import '../data/db/connection.dart';
import '../data/upload/drift_upload_store.dart';
import '../data/upload/upload_queue.dart';
import '../features/auth/auth_controller.dart';
import '../features/run/foreground_service.dart';
import 'config.dart';
import 'h3_cells.dart';
import 'permissions.dart';
import 'token_store.dart';

/// Overridden in main() (and in tests) with the loaded instance.
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider must be overridden'),
);

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// True only when built with --dart-define=DEV_AUTH=true. Tests override it.
final devAuthEnabledProvider = Provider<bool>((ref) => AppConfig.devAuth);

final permissionGatewayProvider =
    Provider<PermissionGateway>((ref) => DevicePermissionGateway());

final runServiceProvider = Provider<RunService>((ref) => AndroidRunService());

final cellLocatorProvider = Provider<CellLocator>((ref) => H3FlutterCellLocator());

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(openLooprunConnection());
  ref.onDispose(db.close);
  return db;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokenProvider: () => ref.read(authProvider).token,
    onUnauthorized: () {
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
    queue.tick();
  });
  ref.onDispose(timer.cancel);
  queue.tick();
});
