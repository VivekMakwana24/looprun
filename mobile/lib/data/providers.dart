import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';
import 'auth/session_expiry_policy.dart';
import 'db/app_database.dart';
import 'db/connection.dart';
import 'db/drift_run_store.dart';
import 'db/run_store.dart';
import 'repositories/auth_repository.dart';
import 'repositories/cell_repository.dart';
import 'repositories/location_repository.dart';
import 'repositories/profile_repository.dart';
import 'repositories/run_repository.dart';
import 'services/api_service.dart';
import 'services/foreground_service.dart';
import 'services/google_auth_service.dart';
import 'services/live_service.dart';
import 'services/location_service.dart';
import 'services/permission_service.dart';
import 'services/token_store.dart';
import 'upload/drift_upload_store.dart';
import 'upload/upload_queue.dart';

/// Dependency injection for the data layer. Tests override these providers with fakes.

// ---------------------------------------------------------------- services

/// Overridden in main() (and in tests) with the loaded instance.
final preferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('preferencesProvider must be overridden'),
);

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// True only when built with --dart-define=DEV_AUTH=true. Tests override it.
final devAuthEnabledProvider = Provider<bool>((ref) => AppConfig.devAuth);

final googleAuthServiceProvider =
    Provider<GoogleAuthService>((ref) => PluginGoogleAuthService());

final permissionServiceProvider =
    Provider<PermissionService>((ref) => DevicePermissionService());

final locationServiceProvider =
    Provider<LocationService>((ref) => GeolocatorLocationService());

final foregroundServiceProvider =
    Provider<ForegroundService>((ref) => AndroidForegroundService());

final liveServiceProvider =
    Provider<LiveService>((ref) => SocketLiveService(baseUrl: AppConfig.apiBaseUrl));

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(openLooprunConnection());
  ref.onDispose(db.close);
  return db;
});

final runStoreProvider =
    Provider<RunStore>((ref) => DriftRunStore(ref.watch(appDatabaseProvider)));

final uploadStoreProvider =
    Provider<UploadStore>((ref) => DriftUploadStore(ref.watch(appDatabaseProvider)));

final Provider<ApiService> apiServiceProvider = Provider<ApiService>((ref) {
  return DioApiService(
    baseUrl: AppConfig.apiBaseUrl,
    tokenProvider: () => ref.read(authRepositoryProvider).token,
    onUnauthorized: () => ref.read(sessionExpiryPolicyProvider).onUnauthorized(),
  );
});

/// The rule for when a 401 signs the user out lives in [SessionExpiryPolicy] (unit tested).
final Provider<SessionExpiryPolicy> sessionExpiryPolicyProvider = Provider<SessionExpiryPolicy>((ref) {
  return SessionExpiryPolicy(
    isRecording: () => ref.read(runRepositoryProvider).isRecording,
    lastStoppedAtMs: () => ref.read(runRepositoryProvider).lastStoppedAtMs,
    expire: () => unawaited(ref.read(authRepositoryProvider).expireSession()),
  );
});

final uploadQueueProvider = Provider<UploadQueue>((ref) {
  final queue = UploadQueue(
    store: ref.watch(uploadStoreProvider),
    api: ref.watch(apiServiceProvider),
  );
  // After a 401 the queue waits; a new sign-in releases it.
  final sub = ref.read(authRepositoryProvider).changes.listen((session) {
    if (session == null) return;
    ref.read(sessionExpiryPolicyProvider).clear();
    queue.resumeAfterAuth();
    unawaited(ref.read(runRepositoryProvider).tickUploads());
  });
  ref.onDispose(sub.cancel);
  return queue;
});

// ---------------------------------------------------------------- repositories

final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repo = AuthRepository(
    api: ref.watch(apiServiceProvider),
    tokens: ref.watch(tokenStoreProvider),
    google: ref.watch(googleAuthServiceProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final Provider<RunRepository> runRepositoryProvider = Provider<RunRepository>((ref) {
  final repo = RunRepository(
    store: ref.watch(runStoreProvider),
    location: ref.watch(locationServiceProvider),
    permissions: ref.watch(permissionServiceProvider),
    foreground: ref.watch(foregroundServiceProvider),
    uploads: ref.watch(uploadQueueProvider),
    api: ref.watch(apiServiceProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final cellRepositoryProvider = Provider<CellRepository>((ref) {
  final repo = CellRepository(
    api: ref.watch(apiServiceProvider),
    live: ref.watch(liveServiceProvider),
    tokenProvider: () => ref.read(authRepositoryProvider).token,
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(
    api: ref.watch(apiServiceProvider),
    prefs: ref.watch(preferencesProvider),
    runs: ref.watch(runStoreProvider),
    location: ref.watch(locationServiceProvider),
    permissions: ref.watch(permissionServiceProvider),
  );
});

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(
    location: ref.watch(locationServiceProvider),
    permissions: ref.watch(permissionServiceProvider),
  );
});

/// Keeps the upload queue ticking while it is watched (the home screen watches it).
final uploadTickerProvider = Provider<void>((ref) {
  final runs = ref.watch(runRepositoryProvider);
  final policy = ref.watch(sessionExpiryPolicyProvider);
  final timer = Timer.periodic(const Duration(seconds: 5), (_) {
    policy.recheck();
    unawaited(runs.tickUploads());
  });
  ref.onDispose(timer.cancel);
  unawaited(runs.tickUploads());
});
