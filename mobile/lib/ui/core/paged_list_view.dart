import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'paged_view_model.dart';
import 'widgets.dart';

/// Draws a [PagedState]: spinner on the first load, a message with "Try again" when it failed, a message
/// when it is empty, otherwise the items with pull-to-refresh, "load more" at the end and an offline strip.
class PagedListView<T> extends StatelessWidget {
  const PagedListView({
    super.key,
    required this.state,
    required this.itemBuilder,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onRetry,
    required this.emptyTitle,
    this.emptyText,
    this.emptyAction,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
    this.header,
    this.separator = 12,
  });

  final PagedState<T> state;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final String emptyTitle;
  final String? emptyText;
  final Widget? emptyAction;
  final EdgeInsets padding;

  /// Shown above the items (and above the messages).
  final Widget? header;
  final double separator;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final items = state.items;
    final children = <Widget>[];
    if (header != null) children.add(header!);

    if (items.isEmpty && !state.loaded && state.error == null) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Semantics(
            label: 'Loading',
            child: CircularProgressIndicator(key: const Key('list_loading'), color: c.accent),
          ),
        ),
      ));
    } else if (items.isEmpty && state.error != null) {
      children.add(LrMessage(
        key: const Key('list_error'),
        title: state.offline ? "Can't reach the server" : 'This could not be loaded',
        text: state.offline ? 'Check your connection.' : state.error,
        actionLabel: 'Try again',
        onAction: onRetry,
      ));
    } else if (state.isEmpty) {
      children.add(LrMessage(key: const Key('list_empty'), title: emptyTitle, text: emptyText));
      if (emptyAction != null) children.add(Center(child: emptyAction!));
    } else {
      if (state.error != null && state.offline) {
        children.add(const Padding(padding: EdgeInsets.only(bottom: 12), child: OfflineBanner()));
      }
      for (var i = 0; i < items.length; i++) {
        if (i > 0) children.add(SizedBox(height: separator));
        children.add(itemBuilder(context, items[i]));
      }
      if (state.loadingMore) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: c.accent)),
          ),
        ));
      } else if (state.error != null) {
        children.add(LrMessage(
          key: const Key('list_more_error'),
          title: 'Could not load more',
          text: state.offline ? null : state.error,
          actionLabel: 'Try again',
          onAction: onRetry,
        ));
      } else if (state.hasMore) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Center(
            child: LrBox(
              key: const Key('list_load_more'),
              onTap: onLoadMore,
              color: c.raised,
              borderColor: c.line,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('Load more', style: LrText.body(15, weight: FontWeight.w600, color: c.text)),
            ),
          ),
        ));
      }
    }

    return RefreshIndicator(
      color: c.accent,
      backgroundColor: c.surface,
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (state.error == null && n.metrics.extentAfter < 240) onLoadMore();
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          children: children,
        ),
      ),
    );
  }
}
