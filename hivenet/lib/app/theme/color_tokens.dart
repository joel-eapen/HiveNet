import 'package:flutter/material.dart';

/// Centralized colour tokens (frontend PRD section 4.1). Single teal accent,
/// warm near-white light surface and charcoal dark surface.
abstract final class ColorTokens {
  static const Color brand = Color(0xFF0F766E);
  static const Color brandDark = Color(0xFF2DD4BF);

  static const Color lightBackground = Color(0xFFFAF8F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color darkBackground = Color(0xFF121615);
  static const Color darkSurface = Color(0xFF1B2120);

  // Status foreground colours, light / dark.
  static const Color successLight = Color(0xFF166534);
  static const Color successDark = Color(0xFF86EFAC);
  static const Color warningLight = Color(0xFF92400E);
  static const Color warningDark = Color(0xFFFCD34D);
  static const Color errorLight = Color(0xFF991B1B);
  static const Color errorDark = Color(0xFFFCA5A5);
  static const Color infoLight = Color(0xFF1E40AF);
  static const Color infoDark = Color(0xFF93C5FD);
  static const Color neutralLight = Color(0xFF44403C);
  static const Color neutralDark = Color(0xFFD6D3D1);
}
