import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/core/theme.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/upload/upload_queue.dart';
import 'package:looprun/domain/recorder/run_recorder.dart';
import 'package:looprun/ui/core/theme_view_model.dart';
import 'package:looprun/ui/core/widgets.dart';
import 'package:looprun/ui/leaderboard/leaderboard_screen.dart';
import 'package:looprun/ui/map/map_screen.dart';
import 'package:looprun/ui/map/map_view_model.dart';
import 'package:looprun/ui/profile/profile_screen.dart';
import 'package:looprun/ui/run/run_screen.dart';
import 'package:looprun/ui/run/run_view_model.dart';
import 'package:looprun/ui/run_result/run_result_screen.dart';

import 'screen_harness.dart';

const _me = UserRef(id: 'u1', name: 'Vivek');
const _bob = UserRef(id: 'u2', name: 'Bob');

Leaderboard _board() => const Leaderboard(
      week: '2026-W47',
      entries: [
        LeaderboardEntry(rank: 1, user: UserRef(id: 'a', name: 'Asha'), cells: 212),
        LeaderboardEntry(rank: 2, user: UserRef(id: 'm', name: 'Meera'), cells: 141),
        LeaderboardEntry(rank: 3, user: _me, cells: 128),
      ],
      me: LeaderboardMe(rank: 3, cells: 128),
    );

void main() {
  group('lane bar', () {
    testWidgets('shows three numbered lanes and marks the active one', (tester) async {
      final h = Harness();
      var picked = -1;
      await pumpScreen(tester, h, LaneNav(current: 1, onSelect: (i) => picked = i));
      expect(find.text('MAP'), findsOneWidget);
      expect(find.text('BOARD'), findsOneWidget);
      expect(find.text('YOU'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('lane_you'))).height, greaterThanOrEqualTo(48));
      await tester.tap(find.byKey(const Key('lane_you')));
      expect(picked, 2);
    });
  });

  group('map screen', () {
    testWidgets('shows my cells and rank from the board, and a truthful fading notice', (tester) async {
      final h = Harness()
        ..api.board = _board()
        ..api.cells = const [
          Cell(id: 'a', lat: 50.0, lng: 8.7, owner: _me, mine: true, strength: 0.3),
          Cell(id: 'b', lat: 50.0, lng: 8.701, owner: _me, mine: true, strength: 0.2),
          Cell(id: 'c', lat: 50.0, lng: 8.702, owner: _me, mine: true, strength: 0.9),
          Cell(id: 'd', lat: 50.0, lng: 8.703, owner: _bob),
        ];
      final c = await pumpScreen(tester, h, const MapScreen());
      await pumpABit(tester);
      expect(find.text('128'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);
      expect(find.text('WEEK 47'), findsOneWidget);
      expect(find.byKey(const Key('fading_notice')), findsNothing, reason: 'no cells loaded yet');

      await c.read(mapViewModelProvider.notifier).onCameraIdle(south: 49.99, west: 8.69, north: 50.01, east: 8.71);
      await pumpABit(tester);
      expect(find.text('2 cells are fading'), findsOneWidget);
      expect(find.text('Run through them again to hold them'), findsOneWidget);
      expect(find.textContaining('days'), findsNothing, reason: 'no invented day counts');
      expect(find.text('START RUN'), findsOneWidget);
      expect(find.text('ON YOUR MARKS'), findsOneWidget);
    });

    testWidgets('no fading notice when nothing fades; a failed load offers a retry', (tester) async {
      final h = Harness()..api.cells = const [Cell(id: 'a', lat: 50.0, lng: 8.7, owner: _me, mine: true, strength: 1)];
      final c = await pumpScreen(tester, h, const MapScreen());
      await c.read(mapViewModelProvider.notifier).onCameraIdle(south: 49.99, west: 8.69, north: 50.01, east: 8.71);
      await pumpABit(tester);
      expect(find.byKey(const Key('fading_notice')), findsNothing);

      h.api.cellsError = const ApiException(null, "Can't reach the server. Check your connection.");
      await c.read(mapViewModelProvider.notifier).onCameraIdle(south: 49.99, west: 8.69, north: 50.01, east: 8.71);
      await pumpABit(tester);
      expect(find.byKey(const Key('offline_banner')), findsOneWidget);
      expect(find.byKey(const Key('map_error_notice')), findsOneWidget);

      h.api.cellsError = null;
      h.api.cells = const [];
      await c.read(mapViewModelProvider.notifier).retry();
      await pumpABit(tester);
      expect(find.byKey(const Key('offline_banner')), findsNothing);
      expect(find.text(MapState.emptyNotice), findsOneWidget);
    });

    testWidgets('a run waiting to upload is shown', (tester) async {
      final h = Harness();
      await h.store.createRun('r1', 1);
      await h.store.markFinished('r1', 2);
      // Two failed tries, next one far away (otherwise the queue would upload it right after sign-in).
      h.store.jobs['r1'] = UploadJob(
        runId: 'r1',
        stage: UploadStage.queued,
        attempts: 2,
        nextAttemptAt: DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      await pumpScreen(tester, h, const MapScreen());
      await pumpABit(tester);
      expect(find.text('1 run is waiting to upload'), findsOneWidget);
      expect(find.textContaining('No connection yet'), findsOneWidget);
    });

    testWidgets('unknown numbers are a dash, never zero', (tester) async {
      final h = Harness()..api.boardError = const ApiException(null, 'offline');
      await pumpScreen(tester, h, const MapScreen());
      await pumpABit(tester);
      expect(find.text('--'), findsNWidgets(2));
    });
  });

  group('board', () {
    testWidgets('lanes, my highlighted row and the lane-up card', (tester) async {
      final h = Harness()..api.board = _board();
      await pumpScreen(tester, h, const LeaderboardScreen());
      await pumpABit(tester);
      expect(find.text('THE BOARD'), findsOneWidget);
      expect(find.text('WEEK 47'), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Vivek'), findsNothing);
      expect(find.byKey(const Key('board_my_row')), findsOneWidget);
      expect(find.text('13'), findsOneWidget);
      expect(find.text('Meera holds lane 2 with 141'), findsOneWidget);
    });

    testWidgets('empty board and failed board', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, const LeaderboardScreen());
      await pumpABit(tester);
      expect(find.byKey(const Key('board_empty')), findsOneWidget);
      expect(find.byKey(const Key('lane_up_card')), findsNothing);
    });

    testWidgets('a failed load has a retry that works', (tester) async {
      final h = Harness()..api.boardError = const ApiException(null, 'offline');
      await pumpScreen(tester, h, const LeaderboardScreen());
      await pumpABit(tester);
      expect(find.byKey(const Key('board_error')), findsOneWidget);
      h.api.boardError = null;
      h.api.board = _board();
      await tester.tap(find.text('Try again'));
      await pumpABit(tester);
      expect(find.text('THE BOARD'), findsOneWidget);
      expect(find.byKey(const Key('board_my_row')), findsOneWidget);
    });
  });

  group('profile', () {
    testWidgets('theme swatches switch the theme', (tester) async {
      final h = Harness();
      final c = await pumpScreen(tester, h, const ProfileScreen());
      await pumpABit(tester);
      expect(c.read(themeViewModelProvider), AppThemeId.night);
      await tester.tap(find.byKey(const Key('theme_swatch_dawn')));
      await pumpABit(tester);
      await tester.pump(const Duration(milliseconds: 500)); // MaterialApp animates the theme change
      expect(c.read(themeViewModelProvider), AppThemeId.dawn);
      expect(Theme.of(tester.element(find.text('YOU'))).extension<LooprunColors>(), LooprunColors.dawn);
    });

    testWidgets('zones from the server, n of 5 used, remove; rest-day quota', (tester) async {
      final h = Harness()
        ..api.serverZones = const [
          HomeZone(lat: 1, lng: 2, radiusM: 300),
          HomeZone(lat: 1, lng: 2, radiusM: 150),
        ]
        ..api.freezeStatus = const FreezeStatus(usedDays: 12, quotaDays: 30, windowDays: 90);
      await pumpScreen(tester, h, const ProfileScreen());
      await pumpABit(tester);
      expect(find.text('Zone 1'), findsOneWidget);
      expect(find.text('300 m radius'), findsOneWidget);
      expect(find.text('2 of 5 used'), findsOneWidget);
      expect(find.text('12 of 30 days used'), findsOneWidget);
      expect(find.text('in the last 90 days'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('remove_zone_0'))).height, greaterThanOrEqualTo(48));

      await tester.tap(find.byKey(const Key('remove_zone_0')));
      await pumpABit(tester);
      expect(find.text('1 of 5 used'), findsOneWidget);
      expect(find.text('150 m radius'), findsOneWidget);
    });

    testWidgets('the Privacy Policy opens in the browser', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, const ProfileScreen());
      await pumpABit(tester);
      await tester.ensureVisible(find.byKey(const Key('privacy_policy_link')));
      await tester.tap(find.byKey(const Key('privacy_policy_link')));
      await pumpABit(tester);
      expect(h.links.opened, ['https://looprun.example/privacy']);
    });
  });

  group('result', () {
    Future<void> seed(Harness h, UploadJob job) async {
      await h.store.createRun('r1', DateTime(2026, 11, 16, 6, 42).millisecondsSinceEpoch);
      await h.store.markFinished('r1', 2);
      h.store.jobs['r1'] = job;
    }

    testWidgets('accepted: cells claimed, taken band, splits, joined gap note', (tester) async {
      final h = Harness();
      await seed(
        h,
        const UploadJob(
          runId: 'r1',
          stage: UploadStage.done,
          result: RunStatus(
            id: 'r1',
            status: RunStatus.accepted,
            distanceM: 5210,
            movingSeconds: 1908,
            loops: [LoopInfo(cells: 42, areaKm2: 0.63)],
            cellsClaimed: 42,
            cellsTakenFromOthers: 9,
            flags: [
              Flag(
                code: 'near_closure_repaired',
                severity: 'soft',
                detail: 'path ended 60 m from an earlier point; closed automatically',
              ),
            ],
          ),
        ),
      );
      await pumpScreen(tester, h, const RunResultScreen(runId: 'r1'));
      await pumpABit(tester);
      expect(find.byKey(const Key('bib_accepted')), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('taken from other runners'), findsOneWidget);
      expect(find.text('5.21'), findsOneWidget);
      expect(find.text('31:48'), findsOneWidget);
      expect(find.text('6:06'), findsOneWidget);
      expect(find.text('0.63'), findsOneWidget);
      expect(find.text('Mon 16 Nov, 06:42'), findsOneWidget);
      expect(find.text('You stopped 60 m short of your path, so we joined the gap for you.'), findsOneWidget);
      expect(find.text('Other runners see your new cells in about 30 minutes.'), findsOneWidget);
    });

    testWidgets('on hold, and waiting for a connection, show no invented numbers', (tester) async {
      final h = Harness();
      await seed(
        h,
        const UploadJob(
          runId: 'r1',
          stage: UploadStage.done,
          result: RunStatus(id: 'r1', status: RunStatus.pendingReview, flags: [
            Flag(code: 'vehicle_speed', severity: 'hard', detail: ''),
          ]),
        ),
      );
      await pumpScreen(tester, h, const RunResultScreen(runId: 'r1'));
      await pumpABit(tester);
      expect(find.text('ON HOLD'), findsOneWidget);
      expect(find.textContaining('vehicle'), findsOneWidget);
      expect(find.text('Not yet'), findsNWidgets(4));
    });

    testWidgets('a failed upload offers try again', (tester) async {
      final h = Harness();
      await seed(h, const UploadJob(runId: 'r1', stage: UploadStage.failed, lastError: 'too big'));
      await pumpScreen(tester, h, const RunResultScreen(runId: 'r1'));
      await pumpABit(tester);
      expect(find.text('UPLOAD FAILED'), findsOneWidget);
      expect(find.byKey(const Key('retry_upload_button')), findsOneWidget);
    });
  });

  group('live run', () {
    testWidgets('recording, paused and the loop gap', (tester) async {
      final h = Harness();
      final semantics = tester.ensureSemantics();
      final c = await pumpScreen(tester, h, const RunScreen());
      // Commands are not awaited in the test body: the fake clock only moves when the tester pumps.
      unawaited(c.read(runViewModelProvider.notifier).start());
      await pumpABit(tester);
      expect(find.text('RECORDING'), findsOneWidget);
      expect(find.text('FINISH RUN'), findsOneWidget);
      expect(find.text('Lock your screen. Looprun keeps recording.'), findsOneWidget);
      expect(find.bySemanticsLabel('Pause run'), findsOneWidget);

      h.location.emit(const GeoFix(lat: 50.0, lng: 8.7, t: 1, acc: 6));
      h.location.emit(const GeoFix(lat: 50.003, lng: 8.7, t: 2, acc: 6));
      await pumpABit(tester);
      expect(find.text('GPS ±6 m'), findsOneWidget);
      expect(find.text('to close the loop'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pause_run_button')));
      await pumpABit(tester);
      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('RESUME'), findsOneWidget);
      expect(find.text('FINISH'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stop_run_button')));
      await tester.pump();
      expect(find.byKey(const Key('saving_run_button')), findsOneWidget);
      // stop() waits at most 5 s for fix writes still in flight; let the fake clock pass it.
      await tester.pump(const Duration(seconds: 6));
      await pumpABit(tester, 10);
      expect(c.read(runViewModelProvider).status, RecorderStatus.finished);
      expect(find.byKey(const Key('saving_run_button')), findsOneWidget, reason: 'no "no run" flash');
      semantics.dispose();
    });

    testWidgets('without a run the screen explains and leads back', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, const RunScreen());
      await pumpABit(tester);
      expect(find.text('NO RUN'), findsOneWidget);
      expect(find.byKey(const Key('back_to_map_button')), findsOneWidget);
    });
  });
}
