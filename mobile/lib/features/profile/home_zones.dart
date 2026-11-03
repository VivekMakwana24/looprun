import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/api/models.dart';

const String _key = 'home_zones_v1';
const int maxHomeZones = 5;

/// Zones are kept on this phone too, because the API only supports replacing the whole list.
class HomeZonesController extends Notifier<List<HomeZone>> {
  @override
  List<HomeZone> build() {
    final raw = ref.watch(prefsProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => HomeZone.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(List<HomeZone> zones) async {
    await ref.read(prefsProvider).setString(_key, jsonEncode(zones.map((z) => z.toJson()).toList()));
  }

  /// Adds a zone and uploads the full list. Throws on API failure; local state is kept only on success.
  Future<void> add(HomeZone zone) async {
    final next = [...state, zone];
    if (next.length > maxHomeZones) {
      throw StateError('You can have at most $maxHomeZones home zones.');
    }
    await ref.read(apiClientProvider).putHomeZones(next);
    await _save(next);
    state = next;
  }

  Future<void> clear() async {
    await ref.read(apiClientProvider).putHomeZones(const []);
    await _save(const []);
    state = const [];
  }

  /// Local-only reset (account deleted).
  Future<void> forget() async {
    await _save(const []);
    state = const [];
  }
}

final homeZonesProvider =
    NotifierProvider<HomeZonesController, List<HomeZone>>(HomeZonesController.new);
