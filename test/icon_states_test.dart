import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/ui/icons.dart';
import 'package:tingyu/ui/theme.dart';

void main() {
  testWidgets('liked heart fills its center; next and enqueue remain distinct', (
    tester,
  ) async {
    Future<List<int>> pixels(IconData icon, {double size = 48}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: const ValueKey('icon-image'),
              child: TingyuIcon(icon, size: size, color: Colors.black),
            ),
          ),
        ),
      );
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('icon-image')),
      );
      final image = (await tester.runAsync(() => boundary.toImage()))!;
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final result = bytes!.buffer.asUint8List().toList();
      image.dispose();
      return result;
    }

    final outline = await pixels(Icons.favorite_border);
    final filled = await pixels(Icons.favorite);
    const centerAlpha = (24 * 48 + 24) * 4 + 3;
    expect(outline[centerAlpha], 0);
    expect(filled[centerAlpha], 255);
    expect(
      await pixels(Icons.playlist_play),
      isNot(await pixels(Icons.add_to_queue)),
    );
    expect(
      await pixels(Icons.check_box),
      isNot(await pixels(Icons.check_circle_outline)),
    );
    // Compare actual small-size raster silhouettes, not IconData or path names.
    // A tiny coordinate change must not count as a distinct action icon.
    final operations = <String, IconData>{
      'play next': Icons.playlist_play,
      'enqueue': Icons.add_to_queue,
      'add to playlist': Icons.playlist_add,
      'add tracks': Icons.library_add_outlined,
      'view playlist': Icons.featured_play_list_outlined,
      'view queue': Icons.queue_music,
      'skip now': Icons.skip_next,
      'move up': Icons.arrow_upward,
      'return to top': Icons.vertical_align_top,
      'move down': Icons.arrow_downward,
      'expand': Icons.keyboard_arrow_down,
    };
    final silhouettes = <String, List<int>>{};
    for (final entry in operations.entries) {
      final rgba = await pixels(entry.value, size: 24);
      silhouettes[entry.key] = [
        for (var i = 3; i < rgba.length; i += 4) rgba[i],
      ];
    }
    final names = silhouettes.keys.toList();
    for (var a = 0; a < names.length; a++) {
      for (var b = a + 1; b < names.length; b++) {
        final x = silhouettes[names[a]]!, y = silhouettes[names[b]]!;
        var union = 0, difference = 0;
        for (var i = 0; i < x.length; i++) {
          final left = x[i] > 64, right = y[i] > 64;
          if (left || right) union++;
          if (left != right) difference++;
        }
        expect(
          difference / union,
          greaterThan(.25),
          reason:
              '${names[a]} and ${names[b]} must remain distinguishable at 24px',
        );
      }
    }
    expect(TingyuTokens.bilibili.accent, const Color(0xfffb7299));
  });
}
