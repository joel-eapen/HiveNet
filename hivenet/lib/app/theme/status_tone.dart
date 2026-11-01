import 'package:flutter/material.dart';

import 'color_tokens.dart';

/// Semantic status colour. Always paired with text and an icon in the UI so
/// colour is never the only signal.
enum StatusTone { success, warning, error, info, neutral }

extension StatusToneColors on StatusTone {
  Color foreground(Brightness b) {
    final dark = b == Brightness.dark;
    return switch (this) {
      StatusTone.success =>
        dark ? ColorTokens.successDark : ColorTokens.successLight,
      StatusTone.warning =>
        dark ? ColorTokens.warningDark : ColorTokens.warningLight,
      StatusTone.error => dark ? ColorTokens.errorDark : ColorTokens.errorLight,
      StatusTone.info => dark ? ColorTokens.infoDark : ColorTokens.infoLight,
      StatusTone.neutral =>
        dark ? ColorTokens.neutralDark : ColorTokens.neutralLight,
    };
  }

  Color background(Brightness b) => foreground(b).withValues(alpha: 0.14);
}
