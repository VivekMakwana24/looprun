import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../core/flag_text.dart';
import '../core/report_dialog.dart';
import '../core/widgets.dart';
import 'run_result_view_model.dart';

/// The result of one run, shaped like a race bib.
class RunResultScreen extends ConsumerWidget {
  const RunResultScreen({super.key, required this.runId});
  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.lr;
    final async = ref.watch(runResultProvider(runId));
    final run = async.valueOrNull;
    Widget body;
    if (run == null && async.isLoading) {
      body = Center(child: CircularProgressIndicator(color: c.accent));
    } else if (run == null) {
      body = const LrMessage(
        key: Key('result_missing'),
        title: 'This run is not on this phone',
        text: 'It may belong to another account or have been deleted.',
      );
    } else {
      body = _Body(run: run);
    }
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('RUN RESULT', style: LrText.label(14, color: c.muted)),
                          if (run != null) ...[
                            const SizedBox(height: 2),
                            Text(formatRunDate(DateTime.fromMillisecondsSinceEpoch(run.startedAt).toLocal()),
                                style: LrText.body(15, weight: FontWeight.w500, color: c.text)),
                          ],
                        ],
                      ),
                    ),
                    LrIconButton(
                      key: const Key('result_close_button'),
                      icon: Icons.close,
                      semanticLabel: 'Close and go to the map',
                      onTap: () => context.go(homePath),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which bib to show.
enum ResultView { accepted, pendingReview, rejected, processing, waiting, failed }

ResultView resultViewOf(RunSummary run) {
  if (run.uploadFailed) return ResultView.failed;
  final r = run.result;
  if (r == null || run.uploadQueued) return ResultView.waiting;
  switch (r.status) {
    case RunStatus.accepted:
      return ResultView.accepted;
    case RunStatus.pendingReview:
      return ResultView.pendingReview;
    case RunStatus.rejected:
      return ResultView.rejected;
    default:
      return ResultView.processing;
  }
}

/// "You stopped 60 m short of your start..." from the engine's flag detail
/// ("path ended 60 m from an earlier point; closed automatically"), or the general sentence.
String repairedNote(Flag f) {
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*m\b').firstMatch(f.detail);
  if (m == null) return describeFlag(f);
  final metres = double.parse(m.group(1)!).round();
  return 'You stopped $metres m short of your path, so we joined the gap for you.';
}

class _Body extends ConsumerWidget {
  const _Body({required this.run});
  final RunSummary run;

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final reason = await askReportReason(context, title: 'Report a problem with this run');
    if (reason == null || !context.mounted) return;
    final message = await ref.read(runResultViewModelProvider).report(run.id, reason);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.lr;
    final view = resultViewOf(run);
    final result = run.result;
    final done = view == ResultView.accepted || view == ResultView.pendingReview || view == ResultView.rejected;

    final notes = <_Note>[];
    if (result != null && done) {
      for (final f in result.flags) {
        if (f.code == 'near_closure_repaired') {
          notes.add(_Note(Icons.replay, repairedNote(f)));
        } else if (view != ResultView.pendingReview || !f.isHard) {
          notes.add(_Note(f.isHard ? Icons.flag_outlined : Icons.info_outline, describeFlag(f)));
        }
      }
      if (view == ResultView.accepted && result.cellsClaimed > 0) {
        notes.add(const _Note(Icons.schedule, 'Other runners see your new cells in about 30 minutes.'));
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bib(run: run, view: view),
        const SizedBox(height: 16),
        _Splits(result: done ? result : null, accepted: view == ResultView.accepted),
        if (view == ResultView.failed) ...[
          const SizedBox(height: 16),
          LrBigButton(
            key: const Key('retry_upload_button'),
            label: 'TRY AGAIN',
            background: c.accent,
            foreground: c.onAccent,
            onTap: () => ref.read(runResultViewModelProvider).retryUpload(run.id),
          ),
        ],
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(n.icon, size: 18, color: c.accentText),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(n.text, style: LrText.body(14, color: c.text2, height: 1.4))),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        LrBigButton(
          key: const Key('see_on_map_button'),
          label: 'SEE IT ON THE MAP',
          background: view == ResultView.failed ? c.raised : c.accent,
          foreground: view == ResultView.failed ? c.text : c.onAccent,
          borderColor: view == ResultView.failed ? c.line : null,
          onTap: () => context.go(homePath),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            key: const Key('report_run_button'),
            onPressed: () => _report(context, ref),
            child: Text('Report a problem with this run',
                style: LrText.body(15, weight: FontWeight.w500, color: c.text2, decoration: TextDecoration.underline)),
          ),
        ),
      ],
      ),
    );
  }
}

class _Note {
  const _Note(this.icon, this.text);
  final IconData icon;
  final String text;
}

/// The paper card with two pin holes.
class _Bib extends StatelessWidget {
  const _Bib({required this.run, required this.view});
  final RunSummary run;
  final ResultView view;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final r = run.result;
    final ink = c.onPaper;
    final title = LrText.label(18, weight: FontWeight.w700, color: ink);

    Widget top;
    Widget? band;
    switch (view) {
      case ResultView.accepted:
        final claimed = r?.cellsClaimed ?? 0;
        final taken = r?.cellsTakenFromOthers ?? 0;
        final noLoop = (r?.loops.isEmpty ?? true) && claimed == 0;
        top = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(noLoop ? 'NO LOOP FOUND' : 'LOOP CLOSED', style: title)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: ink, width: 1.5),
                  ),
                  child: Text('ACCEPTED', style: LrText.label(13, color: ink, tracking: 0.14)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: Text('$claimed',
                        key: const Key('cells_claimed'),
                        style: LrText.display(168, color: ink, tracking: -0.02, height: 0.82)),
                  ),
                ),
                const SizedBox(width: 14),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.all_inclusive, size: 48, color: ink),
                      const SizedBox(height: 10),
                      Text(claimed == 1 ? 'CELL\nCLAIMED' : 'CELLS\nCLAIMED',
                          style: LrText.label(20, weight: FontWeight.w700, color: ink, tracking: 0.12, height: 1.05)),
                    ],
                  ),
                ),
              ],
            ),
            if (noLoop) ...[
              const SizedBox(height: 10),
              Text('The run is saved, but its path did not close a loop, so no cells were claimed.',
                  style: LrText.body(15, weight: FontWeight.w500, color: ink, height: 1.4)),
            ],
          ],
        );
        if (taken > 0) {
          band = Container(
            key: const Key('taken_band'),
            color: c.accent,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              children: [
                Text('$taken', style: LrText.display(28, color: c.onAccent, height: 1)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('taken from other runners',
                      style: LrText.body(16, weight: FontWeight.w600, color: c.onAccent)),
                ),
              ],
            ),
          );
        }
      case ResultView.pendingReview:
      case ResultView.rejected:
        final pending = view == ResultView.pendingReview;
        Flag? hard;
        for (final f in r?.flags ?? const <Flag>[]) {
          if (f.isHard) {
            hard = f;
            break;
          }
        }
        top = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pending ? 'UNDER REVIEW' : 'NOT COUNTED', style: title),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(pending ? 'ON HOLD' : 'NO CELLS', style: LrText.display(92, color: ink, height: 0.86)),
            ),
            const SizedBox(height: 10),
            Text(
              pending
                  ? 'No cells yet. This run is waiting for a review before any cells are given.'
                  : 'This run could not be counted, so it gives no cells.',
              style: LrText.body(16, weight: FontWeight.w500, color: ink, height: 1.4),
            ),
          ],
        );
        band = Container(
          color: ink,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.flag_outlined, size: 20, color: c.paper),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hard != null ? describeFlag(hard) : 'Something in the GPS data looked unusual.',
                  style: LrText.body(15, color: c.paper, height: 1.4),
                ),
              ),
            ],
          ),
        );
      case ResultView.processing:
        top = _BigText(
          title: 'RUN UPLOADED',
          big: 'COUNTING CELLS',
          text: 'We are finding your loop and the cells inside it. You can leave this screen. '
              'The result will be here when it is ready.',
          ink: ink,
          progress: true,
        );
      case ResultView.waiting:
        final retrying = run.attempts > 0;
        top = _BigText(
          title: 'SAVED ON THIS PHONE',
          big: retrying ? 'WAITING FOR A CONNECTION' : 'UPLOADING',
          text: retrying
              ? 'No connection yet. Your run is safe on this phone and Looprun keeps trying while the app is open.'
              : 'Sending your run to the server. You can leave this screen.',
          ink: ink,
          progress: !retrying,
        );
      case ResultView.failed:
        top = _BigText(
          title: 'SAVED ON THIS PHONE',
          big: 'UPLOAD FAILED',
          text: 'The server did not take this run${run.lastError == null ? '' : ': ${run.lastError}'}. '
              'It is still on this phone; you can try again.',
          ink: ink,
        );
    }

    return Semantics(
      container: true,
      child: Container(
        key: Key('bib_${view.name}'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(24)),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(24, 30, 24, 18), child: top),
                if (band != null) band,
              ],
            ),
            // Pin holes.
            Positioned(left: 12, top: 12, child: _Hole(color: c.bg)),
            Positioned(right: 12, top: 12, child: _Hole(color: c.bg)),
          ],
        ),
      ),
    );
  }
}

class _Hole extends StatelessWidget {
  const _Hole({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _BigText extends StatelessWidget {
  const _BigText({required this.title, required this.big, required this.text, required this.ink, this.progress = false});
  final String title;
  final String big;
  final String text;
  final Color ink;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: LrText.label(18, weight: FontWeight.w700, color: ink))),
            if (progress)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: ink)),
          ],
        ),
        const SizedBox(height: 10),
        Text(big, style: LrText.display(64, color: ink, height: 0.88)),
        const SizedBox(height: 10),
        Text(text, style: LrText.body(16, weight: FontWeight.w500, color: ink, height: 1.4)),
      ],
    );
  }
}

/// The 2 x 2 grid: distance, moving time, average pace, loop area. Only server numbers are shown;
/// until the server has answered every value is "Not yet".
class _Splits extends StatelessWidget {
  const _Splits({required this.result, required this.accepted});
  final RunStatus? result;
  final bool accepted;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final r = result;
    final distance = r?.distanceM;
    final moving = r?.movingSeconds;
    String? pace;
    if (distance != null && moving != null) {
      final p = formatPace(moving * 1000, distance);
      if (p != noValue) pace = p;
    }
    var area = 0.0;
    for (final l in r?.loops ?? const <LoopInfo>[]) {
      area += l.areaKm2;
    }
    final hasArea = accepted && (r?.loops.isNotEmpty ?? false);
    Widget cell(String label, String? value, String unit, {bool right = false, bool bottom = false}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            right: right ? BorderSide(color: c.line) : BorderSide.none,
            bottom: bottom ? BorderSide(color: c.line) : BorderSide.none,
          ),
        ),
        child: Semantics(
          label: '$label ${value ?? 'not yet'} ${value == null ? '' : unit}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: LrText.label(13, color: c.muted)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value ?? 'Not yet', style: LrText.display(38, color: c.text, height: 1)),
                    if (value != null && unit.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(unit, style: LrText.body(14, color: c.text2)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LrCard(
      key: const Key('result_splits'),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: cell('DISTANCE', distance == null ? null : formatKm(distance), 'km', right: true, bottom: true)),
              Expanded(child: cell('MOVING TIME', moving == null ? null : formatDuration(moving * 1000), '', bottom: true)),
            ],
          ),
          Row(
            children: [
              Expanded(child: cell('AVERAGE PACE', pace, '/km', right: true)),
              Expanded(child: cell('LOOP AREA', hasArea ? area.toStringAsFixed(2) : null, 'km²')),
            ],
          ),
        ],
      ),
    );
  }
}
