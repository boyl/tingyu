import 'package:flutter/material.dart';
import 'theme.dart';

/// One optical grid and stroke for navigation, transport and collection actions.
class TingyuIcon extends StatelessWidget {
  const TingyuIcon(this.icon, {super.key, this.size, this.color});
  final IconData icon;
  final double? size;
  final Color? color;
  static final _names = {
    Icons.arrow_back: 'back',
    Icons.chevron_left: 'back',
    Icons.keyboard_arrow_down: 'down',
    Icons.expand_more: 'down',
    Icons.chevron_right: 'right',
    Icons.vertical_align_top: 'up',
    Icons.arrow_upward: 'up',
    Icons.arrow_downward: 'down',
    Icons.search: 'search',
    Icons.add: 'plus',
    Icons.close: 'close',
    Icons.cancel_outlined: 'closeCircle',
    Icons.more_horiz: 'more',
    Icons.swap_vert: 'sort',
    Icons.download: 'download',
    Icons.download_outlined: 'download',
    Icons.download_rounded: 'download',
    Icons.file_download_outlined: 'download',
    Icons.check: 'check',
    Icons.check_circle: 'done',
    Icons.check_circle_outline: 'done',
    Icons.play_arrow: 'play',
    Icons.play_arrow_rounded: 'play',
    Icons.pause: 'pause',
    Icons.skip_next: 'next',
    Icons.skip_previous: 'previous',
    Icons.queue_music: 'queue',
    Icons.playlist_play: 'queue',
    Icons.library_music: 'music',
    Icons.library_music_outlined: 'music',
    Icons.favorite: 'heart',
    Icons.favorite_border: 'heart',
    Icons.favorite_rounded: 'heart',
    Icons.drag_handle: 'grip',
    Icons.drag_indicator: 'grip',
    Icons.my_location: 'locate',
    Icons.checklist: 'select',
    Icons.folder_copy_outlined: 'folder',
    Icons.info_outline: 'info',
    Icons.open_in_new: 'external',
    Icons.north_east: 'external',
    Icons.lyrics_outlined: 'lyrics',
    Icons.graphic_eq: 'wave',
    Icons.playlist_add: 'listPlus',
    Icons.refresh: 'refresh',
  };
  @override
  Widget build(BuildContext context) {
    final name = _names[icon];
    if (name == null) return Icon(icon, size: size, color: color);
    final theme = IconTheme.of(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size ?? theme.size ?? 24,
        child: CustomPaint(
          painter: _IconPainter(
            name,
            color ?? theme.color ?? context.tokens.text,
          ),
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.name, this.color);
  final String name;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = TingyuTokens.iconStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x, double y, double x2, double y2) =>
        canvas.drawLine(Offset(x, y), Offset(x2, y2), p);
    void path(List<Offset> points, {bool close = false}) {
      final a = Path()..moveTo(points.first.dx, points.first.dy);
      for (final b in points.skip(1)) {
        a.lineTo(b.dx, b.dy);
      }
      if (close) a.close();
      canvas.drawPath(a, p);
    }

    void circle(double x, double y, double r) =>
        canvas.drawCircle(Offset(x, y), r, p);
    void check() =>
        path([const Offset(7, 12), const Offset(10, 15), const Offset(17, 8)]);
    switch (name) {
      case 'back':
        path([const Offset(15, 5), const Offset(8, 12), const Offset(15, 19)]);
      case 'right':
        path([const Offset(9, 5), const Offset(16, 12), const Offset(9, 19)]);
      case 'up':
        path([const Offset(5, 15), const Offset(12, 8), const Offset(19, 15)]);
      case 'down':
        path([const Offset(5, 9), const Offset(12, 16), const Offset(19, 9)]);
      case 'search':
        circle(10.5, 10.5, 6.5);
        line(15.5, 15.5, 21, 21);
      case 'plus':
        line(12, 5, 12, 19);
        line(5, 12, 19, 12);
      case 'close':
        line(6, 6, 18, 18);
        line(18, 6, 6, 18);
      case 'closeCircle':
        circle(12, 12, 9);
        line(9, 9, 15, 15);
        line(15, 9, 9, 15);
      case 'more':
        for (final x in [5.0, 12.0, 19.0]) {
          canvas.drawCircle(Offset(x, 12), 1.2, Paint()..color = color);
        }
      case 'sort':
        line(3, 6, 17, 6);
        line(3, 12, 13, 12);
        line(3, 18, 9, 18);
        line(19, 11, 19, 20);
        path([
          const Offset(16, 17),
          const Offset(19, 20),
          const Offset(22, 17),
        ]);
      case 'download':
        line(12, 3, 12, 15);
        path([const Offset(7, 10), const Offset(12, 15), const Offset(17, 10)]);
        canvas.drawPath(
          Path()
            ..moveTo(4, 15)
            ..lineTo(4, 19)
            ..quadraticBezierTo(4, 21, 6, 21)
            ..lineTo(18, 21)
            ..quadraticBezierTo(20, 21, 20, 19)
            ..lineTo(20, 15),
          p,
        );
      case 'check':
        check();
      case 'done':
        circle(12, 12, 9);
        check();
      case 'play':
        canvas.drawPath(
          Path()
            ..moveTo(8, 5)
            ..lineTo(19, 12)
            ..lineTo(8, 19)
            ..close(),
          Paint()
            ..color = color
            ..style = PaintingStyle.fill,
        );
      case 'pause':
        for (final x in [8.0, 15.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, 5, 2.5, 14),
              const Radius.circular(1),
            ),
            Paint()..color = color,
          );
        }
      case 'next':
        path([
          const Offset(5, 5),
          const Offset(15, 12),
          const Offset(5, 19),
        ], close: true);
        line(19, 5, 19, 19);
      case 'previous':
        path([
          const Offset(19, 5),
          const Offset(9, 12),
          const Offset(19, 19),
        ], close: true);
        line(5, 5, 5, 19);
      case 'queue':
        line(3, 5, 19, 5);
        line(3, 10, 15, 10);
        line(3, 15, 12, 15);
        line(20, 10, 20, 19);
        line(20, 10, 23, 9);
        canvas.drawOval(const Rect.fromLTWH(15, 18, 5, 3), p);
      case 'music':
        line(10, 5, 10, 17);
        line(10, 5, 20, 3);
        line(20, 3, 20, 15);
        line(10, 8, 20, 6);
        canvas.drawOval(const Rect.fromLTWH(4, 16, 6, 4), p);
        canvas.drawOval(const Rect.fromLTWH(14, 14, 6, 4), p);
      case 'heart':
        canvas.drawPath(
          Path()
            ..moveTo(12, 20)
            ..cubicTo(9, 17, 3, 13, 3, 8)
            ..cubicTo(3, 3, 9, 2, 12, 7)
            ..cubicTo(15, 2, 21, 3, 21, 8)
            ..cubicTo(21, 13, 15, 17, 12, 20),
          p,
        );
      case 'grip':
        for (final x in [9.0, 15.0]) {
          for (final y in [6.0, 12.0, 18.0]) {
            canvas.drawCircle(Offset(x, y), 1, Paint()..color = color);
          }
        }
      case 'locate':
        circle(12, 12, 6);
        circle(12, 12, 1.5);
        line(12, 2, 12, 4);
        line(12, 20, 12, 22);
        line(2, 12, 4, 12);
        line(20, 12, 22, 12);
      case 'folder':
        path([
          const Offset(3, 20),
          const Offset(3, 5),
          const Offset(9, 5),
          const Offset(11, 8),
          const Offset(21, 8),
          const Offset(21, 20),
        ], close: true);
      case 'info':
        circle(12, 12, 9);
        line(12, 10, 12, 17);
        canvas.drawCircle(const Offset(12, 7), 1, Paint()..color = color);
      case 'external':
        line(7, 17, 19, 5);
        line(11, 5, 19, 5);
        line(19, 5, 19, 13);
      case 'select':
        for (final y in [5.0, 12.0, 19.0]) {
          path([Offset(3, y), Offset(5, y + 2), Offset(8, y - 2)]);
          line(12, y, 21, y);
        }
      case 'wave':
        for (var i = 0; i < 5; i++) {
          final h = [5.0, 11.0, 18.0, 9.0, 4.0][i];
          line(4 + i * 4, 12 - h / 2, 4 + i * 4, 12 + h / 2);
        }
      case 'lyrics':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 4, 18, 14),
            const Radius.circular(3),
          ),
          p,
        );
        path([const Offset(7, 18), const Offset(7, 22), const Offset(12, 18)]);
        line(7, 9, 17, 9);
        line(7, 13, 14, 13);
      case 'listPlus':
        line(3, 5, 18, 5);
        line(3, 10, 15, 10);
        line(3, 15, 11, 15);
        line(18, 14, 18, 22);
        line(14, 18, 22, 18);
      case 'refresh':
        canvas.drawArc(const Rect.fromLTWH(4, 4, 16, 16), .2, 5.2, false, p);
        path([const Offset(15, 3), const Offset(20, 5), const Offset(20, 0.5)]);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _IconPainter old) =>
      old.name != name || old.color != color;
}
