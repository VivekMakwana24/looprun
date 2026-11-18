import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../core/widgets.dart';
import 'battles_view_model.dart';

/// Opens the "take it back" sheet over the map.
Future<void> showTakeBackSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.lr.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => const TakeBackSheet(),
  );
}

/// Cells you lost in the last 7 days and do not hold now. "Show on map" draws them from their boundaries;
/// a row moves the map to that cell. Who took it is shown only when that runner's name is public.
class TakeBackSheet extends ConsumerWidget {
  const TakeBackSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.lr;
    final state = ref.watch(takeBackViewModelProvider);
    final vm = ref.read(takeBackViewModelProvider.notifier);
    final maxHeight = MediaQuery.of(context).size.height * 0.7;
    final n = state.cells.length;

    Widget body;
    if (state.error != null && state.cells.isEmpty) {
      body = LrMessage(
        key: const Key('take_back_error'),
        title: state.offline ? "Can't reach the server" : 'Lost cells could not be loaded',
        text: state.offline ? 'Check your connection.' : state.error,
        actionLabel: 'Try again',
        onAction: vm.refresh,
      );
    } else if (state.loading && state.cells.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(key: const Key('take_back_loading'), color: c.accent)),
      );
    } else if (state.cells.isEmpty) {
      body = const LrMessage(
        key: Key('take_back_empty'),
        title: 'Nothing to take back',
        text: 'You have not lost any cells in the last 7 days, or you already won them back.',
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            toggled: state.shown,
            label: 'Show lost cells on the map',
            child: LrBox(
              key: const Key('take_back_toggle'),
              onTap: () => vm.setShown(!state.shown),
              radius: 16,
              color: state.shown ? c.raised : null,
              borderColor: c.line,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(child: Text('Show on map', style: LrText.body(16, weight: FontWeight.w600, color: c.text))),
                  ExcludeSemantics(child: Switch(value: state.shown, onChanged: (v) => vm.setShown(v))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: n,
              separatorBuilder: (_, __) => Container(height: 1, color: c.line),
              itemBuilder: (context, i) {
                final cell = state.cells[i];
                final when = cell.lostAt == null
                    ? null
                    : formatAgo(DateTime.fromMillisecondsSinceEpoch(cell.lostAt!));
                final who = cell.lostTo == null ? 'a private runner' : cell.lostTo!.name;
                return LrBox(
                  key: Key('lost_cell_$i'),
                  onTap: () {
                    vm.focusOn(cell);
                    Navigator.of(context).pop();
                  },
                  semanticLabel: 'Lost cell ${i + 1}, to $who${when == null ? '' : ', $when'}. Show on the map',
                  radius: 0,
                  height: 56,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(Icons.hexagon_outlined, size: 22, color: c.accentText),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Taken by $who', style: LrText.body(15, weight: FontWeight.w500, color: c.text)),
                      ),
                      if (when != null) Text(when, style: LrText.body(13, color: c.muted)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('TAKE IT BACK', style: LrText.display(36, color: c.text, height: 1)),
              const SizedBox(height: 4),
              Text(
                n == 0
                    ? 'Cells you lost in the last 7 days.'
                    : (n == 1
                        ? '1 cell was taken from you this week. Run through it to win it back.'
                        : '$n cells were taken from you this week. Run through them to win them back.'),
                style: LrText.body(14, color: c.text2, height: 1.4),
              ),
              const SizedBox(height: 12),
              Flexible(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

