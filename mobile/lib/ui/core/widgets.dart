import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A label that is drawn in capitals. The text keeps its normal spelling (for tests, for the
/// compliance documents and for screen readers); only the drawing is upper case, like CSS
/// `text-transform: uppercase`.
class CapsLabel extends StatelessWidget {
  const CapsLabel(this.text, {super.key, required this.style, this.textAlign});
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), semanticsLabel: text, style: style, textAlign: textAlign);
  }
}

/// A tappable box with the design's flat look: fill, optional 1 px border, rounded corners, ink splash.
/// Never smaller than 48 x 48 logical pixels.
class LrBox extends StatelessWidget {
  const LrBox({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = 18,
    this.height,
    this.width,
    this.padding = EdgeInsets.zero,
    this.semanticLabel,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final double? height;
  final double? width;
  final EdgeInsetsGeometry padding;

  /// For icon-only buttons: what a screen reader says.
  final String? semanticLabel;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: borderColor == null ? BorderSide.none : BorderSide(color: borderColor!),
    );
    final box = Material(
      color: color ?? Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Container(
            height: height,
            width: width,
            padding: padding,
            alignment: alignment,
            child: child,
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: box,
    );
  }
}

/// The big italic call-to-action of the design (68 px high, radius 24), e.g. "FINISH RUN".
class LrBigButton extends StatelessWidget {
  const LrBigButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.onTap,
    this.leading,
    this.borderColor,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final Widget? leading;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return LrBox(
      onTap: onTap,
      color: background,
      borderColor: borderColor,
      radius: 24,
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Text(label, style: LrText.display(28, color: foreground, tracking: 0.03, height: 1)),
          ],
        ),
      ),
    );
  }
}

/// Small square icon button with a border (close, recentre). 48 x 48, radius 16.
class LrIconButton extends StatelessWidget {
  const LrIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  /// True: surface fill (on top of the map). False: transparent with a border.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return LrBox(
      onTap: onTap,
      semanticLabel: semanticLabel,
      color: filled ? c.surface : null,
      borderColor: c.line,
      radius: 16,
      width: 48,
      height: 48,
      child: Icon(icon, size: 22, color: c.text),
    );
  }
}

/// A card: surface fill, 1 px line, radius 22.
class LrCard extends StatelessWidget {
  const LrCard({super.key, required this.child, this.padding = EdgeInsets.zero, this.radius = 22});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

/// A big number with a small spaced label under it ("128 / CELLS HELD").
class LrStat extends StatelessWidget {
  const LrStat({
    super.key,
    required this.value,
    required this.label,
    this.size = 52,
    this.accent = false,
  });

  final String value;
  final String label;
  final double size;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: LrText.display(size, color: accent ? c.accentText : c.text, height: 0.95)),
          const SizedBox(height: 2),
          Text(label, style: LrText.label(13, color: c.muted, tracking: 0.14)),
        ],
      ),
    );
  }
}

/// The pill with the week number.
class WeekChip extends StatelessWidget {
  const WeekChip({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: Text(label, style: LrText.label(14, color: c.muted, tracking: 0.12)),
    );
  }
}

/// "No connection" strip. Shown where the screen's data could not be fetched.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.text = "You're offline. Showing what was loaded before."});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('offline_banner'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 18, color: c.danger),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: LrText.body(13, weight: FontWeight.w500, color: c.text2))),
          ],
        ),
      ),
    );
  }
}

/// Centred message with an optional retry button: loading failed, or there is nothing to show.
class LrMessage extends StatelessWidget {
  const LrMessage({super.key, required this.title, this.text, this.actionLabel, this.onAction});
  final String title;
  final String? text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              textAlign: TextAlign.center, style: LrText.body(17, weight: FontWeight.w600, color: c.text)),
          if (text != null) ...[
            const SizedBox(height: 6),
            Text(text!, textAlign: TextAlign.center, style: LrText.body(14, color: c.muted, height: 1.4)),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 14),
            LrBox(
              onTap: onAction,
              color: c.raised,
              borderColor: c.line,
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              alignment: null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!, style: LrText.body(16, weight: FontWeight.w600, color: c.text)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The three numbered lanes at the bottom: 1 MAP, 2 BOARD, 3 YOU. The active lane carries a 3 px
/// accent line on top.
class LaneNav extends StatelessWidget {
  const LaneNav({super.key, required this.current, required this.onSelect});

  /// 0, 1 or 2.
  final int current;
  final ValueChanged<int> onSelect;

  static const List<String> labels = ['MAP', 'BOARD', 'YOU'];

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Material(
      color: c.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: _Lane(
                    key: Key('lane_${labels[i].toLowerCase()}'),
                    number: i + 1,
                    label: labels[i],
                    active: i == current,
                    divider: i > 0,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Lane extends StatelessWidget {
  const _Lane({
    super.key,
    required this.number,
    required this.label,
    required this.active,
    required this.divider,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool active;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final color = active ? c.text : c.muted;
    return Semantics(
      button: true,
      selected: active,
      label: 'Lane $number, $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            border: Border(
              left: divider ? BorderSide(color: c.line) : BorderSide.none,
            ),
          ),
          child: Column(
            children: [
              // The active lane's start line.
              Container(height: 3, color: active ? c.accent : Colors.transparent),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$number',
                        style: LrText.display(13, color: active ? c.accentText : c.muted, height: 1)),
                    const SizedBox(height: 3),
                    Text(label, style: LrText.label(16, color: color, tracking: 0.12, height: 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A short question with two answers. Returns true for [confirmLabel].
Future<bool> askConfirm(
  BuildContext context, {
  required String title,
  required String text,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  Key? confirmKey,
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.lr;
      return AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel)),
          FilledButton(
            key: confirmKey,
            style: danger ? FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: c.bg) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return ok == true;
}

/// Opens the Privacy Policy, or shows its address as text when no browser took it.
Future<void> showPrivacyPolicyFallback(BuildContext context, String url) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Privacy Policy'),
      content: SelectableText(url),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ),
  );
}
