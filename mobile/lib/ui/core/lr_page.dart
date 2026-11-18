import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'widgets.dart';

/// A full-screen page above the lanes (profile, lists, inbox): back button, big italic title, optional
/// actions, then [child]. Colours come from the theme.
class LrPage extends StatelessWidget {
  const LrPage({super.key, required this.title, required this.child, this.actions = const [], this.onBack});

  final String title;
  final Widget child;
  final List<Widget> actions;

  /// Called instead of popping the route.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  LrIconButton(
                    key: const Key('page_back'),
                    icon: Icons.arrow_back,
                    semanticLabel: 'Back',
                    onTap: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LrText.display(40, color: c.text, tracking: 0.01, height: 0.95),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
