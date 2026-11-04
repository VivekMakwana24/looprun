import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/providers.dart';

final weeklyLeaderboardProvider = FutureProvider.autoDispose<Leaderboard>(
  (ref) => ref.watch(cellRepositoryProvider).weeklyLeaderboard(),
);
