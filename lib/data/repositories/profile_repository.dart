import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_exception.dart';
import '../db/run_store.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/permission_service.dart';

/// Home zones are kept per account: the key is this prefix plus the user id.
const String homeZonesPrefKeyPrefix = 'home_zones_v2_';

/// The old key shared by all accounts. It is deleted the first time zones are read.
const String legacyHomeZonesPrefKey = 'home_zones_v1';
const String disclosurePrefKey = 'location_disclosure_accepted_v1';
const int maxHomeZones = 5;

/// Per-user settings: home zones, decay freeze, account deletion, and whether the location disclosure
/// was accepted on this phone.
class ProfileRepository {
  ProfileRepository({
    required ApiService api,
    required SharedPreferences prefs,
    required RunStore runs,
    required LocationService location,
    required PermissionService permissions,
    String? Function()? currentUserId,
  })  : _currentUserId = currentUserId ?? (() => null),
        _api = api,
        _prefs = prefs,
        _runs = runs,
        _location = location,
        _permissions = permissions;

  final String? Function() _currentUserId;
  final ApiService _api;
  final SharedPreferences _prefs;
  final RunStore _runs;
  final LocationService _location;
  final PermissionService _permissions;

  // ------------------------------------------------------------------ disclosure

  bool get disclosureAccepted => _prefs.getBool(disclosurePrefKey) ?? false;

  Future<void> acceptDisclosure() async {
    await _prefs.setBool(disclosurePrefKey, true);
  }

  // ------------------------------------------------------------------ home zones

  /// Zones are also kept on this phone because the API only offers "replace the whole list".
  List<HomeZone> homeZones() {
    final key = _zonesKey();
    if (key == null) return const [];
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => HomeZone.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Preference key of the signed-in account's zones, or null when nobody is signed in.
  /// Also drops the old shared key, whose zones may belong to a different account.
  String? _zonesKey() {
    if (_prefs.containsKey(legacyHomeZonesPrefKey)) {
      unawaited(_prefs.remove(legacyHomeZonesPrefKey));
    }
    final uid = _currentUserId();
    if (uid == null || uid.isEmpty) return null;
    return '$homeZonesPrefKeyPrefix$uid';
  }

  Future<void> _saveZones(List<HomeZone> zones) async {
    final key = _zonesKey();
    if (key == null) throw const AppException('Sign in to change your home zones.');
    await _prefs.setString(key, jsonEncode(zones.map((z) => z.toJson()).toList()));
  }

  /// Adds a zone centred on the current position and uploads the full list.
  /// Throws [AppException] for user-fixable problems and ApiException on server errors;
  /// the local list changes only after the server accepted it.
  Future<List<HomeZone>> addZoneHere(double radiusM) async {
    if (_zonesKey() == null) throw const AppException('Sign in to change your home zones.');
    final current = homeZones();
    if (current.length >= maxHomeZones) {
      throw const AppException('You can have at most $maxHomeZones home zones.');
    }
    if (!await _permissions.hasLocation() && !await _permissions.requestLocation()) {
      throw const AppException('Location permission is needed to place a zone at your position.');
    }
    final here = await _location.currentPosition();
    final next = [...current, HomeZone(lat: here.lat, lng: here.lng, radiusM: radiusM)];
    await _api.putHomeZones(next);
    await _saveZones(next);
    return next;
  }

  Future<List<HomeZone>> clearZones() async {
    if (_zonesKey() == null) throw const AppException('Sign in to change your home zones.');
    await _api.putHomeZones(const []);
    await _saveZones(const []);
    return const [];
  }

  // ------------------------------------------------------------------ freeze, deletion

  /// Starts (days > 0) or ends (0) a decay freeze. Returns freeze_until in epoch ms, or null.
  Future<int?> setFreeze(int days) => _api.setFreeze(days);

  /// Deletes the account on the server, then the runs and zones on this phone.
  /// The caller signs out afterwards.
  Future<void> deleteAccount() async {
    await _api.deleteAccount();
    final key = _zonesKey(); // read before the wipe: it needs the signed-in account
    await _runs.wipe();
    if (key != null) await _prefs.remove(key);
  }
}
