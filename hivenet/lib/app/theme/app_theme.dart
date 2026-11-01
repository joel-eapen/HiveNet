import 'package:flutter/material.dart';

import 'color_tokens.dart';
import 'spacing_tokens.dart';
import 'typography.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: ColorTokens.brand,
      brightness: brightness,
      surface: dark ? ColorTokens.darkSurface : ColorTokens.lightSurface,
    );
    final base = ThemeData(brightness: brightness, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor:
          dark ? ColorTokens.darkBackground : ColorTokens.lightBackground,
      textTheme: buildTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor:
            dark ? ColorTokens.darkBackground : ColorTokens.lightBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(Sizes.minTouchTarget, Sizes.buttonHeight),
        ),
      ),
    );
  }
}
