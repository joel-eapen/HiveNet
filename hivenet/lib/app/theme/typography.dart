import 'package:flutter/material.dart';

/// Monospaced style for content IDs, node IDs and hashes. Full hashes are not
/// shown by default; use `CopyableIdentifier`.
const TextStyle monoMetadataStyle = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: ['Roboto Mono', 'Courier New', 'monospace'],
  fontSize: 12.5,
  letterSpacing: 0.2,
);

TextTheme buildTextTheme(TextTheme base) {
  return base.copyWith(
    displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w700),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
}
