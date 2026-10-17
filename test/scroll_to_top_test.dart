import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/ui/scroll_to_top.dart';
import 'package:tingyu/ui/theme.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('return to top threshold, action and reduced motion $reduced', (
      tester,
    ) async {
      final controller = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('a'),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: ScrollToTop(
              controller: controller,
              builder: (scroll) => ListView.builder(
                controller: scroll,
                itemExtent: 72,
                itemCount: 100,
                itemBuilder: (_, i) => Text('Song $i'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final button = find.byKey(const ValueKey('scroll-to-top'));
      expect(button, findsNothing);
      controller.jumpTo(300);
      await tester.pump();
      expect(button, findsNothing);
      controller.jumpTo(2000);
      await tester.pump();
      expect(button, findsOneWidget);
      expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(48));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      expect(button, findsNothing);
      controller.jumpTo(2000);
      await tester.pump();
      expect(button, findsOneWidget);
      // Disposal releases listeners even while the overlay is visible.
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      expect(tester.takeException(), isNull);
    });
  }
}
