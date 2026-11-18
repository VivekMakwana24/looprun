import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';

/// A round avatar with the initials of a name. There are no profile photos in Looprun. The ring colour
/// is one of three theme colours picked from the name, so the same person always looks the same.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 44});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final ring = [c.accentText, c.rival, c.text2][name.runes.fold<int>(0, (a, r) => (a + r) % 3)];
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.raised,
          border: Border.all(color: ring, width: 2),
        ),
        child: Text(initialsOf(name), style: LrText.display(size * 0.42, color: c.text, height: 1)),
      ),
    );
  }
}
