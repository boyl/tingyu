import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tingyu/models/music.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tingyu/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android tabs preserve input, dismiss keyboard and survive repeated switching',
    (tester) async {
      await app.main();
      await tester.pumpAndSettle();
      expect(find.text('把喜欢的声音，留在身边。'), findsOneWidget);
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(app.TingyuApp)),
      ).read(app.libraryProvider);
      // Deterministic navigation acceptance: no live API or account dependency.
      controller.api.http.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: 'Acceptance offline fixture',
              ),
            );
          },
        ),
      );
      for (var i = 0; i < 40; i++) {
        final track = Track(
          bvid: 'acceptance-$i',
          cid: i + 1,
          title: '滚动验收 $i',
          artist: '本地测试',
          cover: '',
          duration: 30,
        );
        controller.library[track.id] = track;
      }
      controller.clearError();
      await tester.pumpAndSettle();
      final libraryScroll = find.byType(SingleChildScrollView).first;
      await tester.drag(libraryScroll, const Offset(0, -500));
      await tester.pumpAndSettle();
      final scrollState = tester.state<ScrollableState>(
        find
            .descendant(of: libraryScroll, matching: find.byType(Scrollable))
            .first,
      );
      final offset = scrollState.position.pixels;
      expect(offset, greaterThan(0));

      await tester.tap(find.byKey(const ValueKey('tab-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '验收保留输入');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('tab-downloads')));
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
      for (var i = 0; i < 5; i++) {
        for (final tab in ['likes', 'library', 'downloads', 'search']) {
          final target = find.byKey(ValueKey('tab-$tab'));
          expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
          await tester.tap(target);
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);
        }
      }
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '验收保留输入',
      );
      for (final theme in ['a', 'b', 'c']) {
        await controller.setTheme(theme);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await controller.setTheme('a');
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.byKey(const ValueKey('tab-library')));
      await tester.pumpAndSettle();
      expect(scrollState.position.pixels, closeTo(offset, 1));
      controller.library.removeWhere(
        (_, track) => track.bvid.startsWith('acceptance-'),
      );
      await controller.save();
      expect(find.text('把喜欢的声音，留在身边。'), findsOneWidget);
      controller.clearError();
      scrollState.position.jumpTo(0);
      await binding.convertFlutterSurfaceToImage();
      for (final theme in ['a', 'b', 'c']) {
        await controller.setTheme(theme);
        await tester.pumpAndSettle();
        await binding.takeScreenshot('android-$theme-library');
      }
      await controller.setTheme('a');
    },
  );
}
