import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/ui/playing_indicator.dart';
import 'package:tingyu/ui/theme.dart';

void main() {
  testWidgets(
    'playing indicator schedules paint animation and reduced motion stops it',
    (tester) async {
      Widget view(bool reduced) => MaterialApp(
        theme: tingyuTheme('a'),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: const Center(child: PlayingIndicator()),
        ),
      );
      await tester.pumpWidget(view(false));
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.hasRunningAnimations, isTrue);
      expect(
        find.descendant(
          of: find.byType(PlayingIndicator),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(view(true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byType(PlayingIndicator), findsOneWidget);
      await tester.pumpWidget(view(false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    },
  );
}
