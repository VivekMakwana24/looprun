import 'package:flutter/material.dart';

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF1B8A5A),
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

const Color mineColor = Color(0xFF1B8A5A);
const Color othersColor = Color(0xFFE5701B);
const Color hiddenColor = Color(0xFF7A7A8C);
const Color healthGood = Color(0xFF2E9E5B);
const Color healthWarn = Color(0xFFF2A100);
