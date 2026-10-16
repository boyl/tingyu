import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/ui/theme.dart';

void main() {
  test('all theme text and selected states meet 4.5 contrast', () {
    for (final tokens in [
      TingyuTokens.light,
      TingyuTokens.dark,
      TingyuTokens.pink,
    ]) {
      for (final background in [
        tokens.background,
        tokens.surface,
        tokens.sidebar,
      ]) {
        for (final text in [
          tokens.text,
          tokens.muted,
          tokens.accent,
          tokens.danger,
        ]) {
          expect(
            contrast(text, background),
            greaterThanOrEqualTo(4.5),
            reason: '$text on $background',
          );
        }
      }
      expect(contrast(tokens.accent, tokens.tint), greaterThanOrEqualTo(4.5));
      expect(
        contrast(tokens.onAccent, tokens.accent),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance(), b = background.computeLuminance();
  return (max(a, b) + .05) / (min(a, b) + .05);
}
