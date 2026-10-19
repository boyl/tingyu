import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/music.dart';

void main() {
  test('SPL word timestamps are not repeated lyric lines', () {
    final lines = parseLrc('[00:01.00]你[00:02.00]好[00:03.00]\n[00:04.00]下一句');
    expect(lines.map((line) => line.text), ['你好', '下一句']);
    expect(lines.first.words.map((word) => word.text), ['你', '好']);
    expect(lines.first.words.first.progress(1500), 0.5);
    expect(lines.first.words.last.progress(1500), 0);
    expect(lines.first.end?.inMilliseconds, 3000);
  });

  test('angle-bracket words keep spacing and an explicit line end', () {
    final line = parseLrc('[00:12.00]Hello<00:12.50> World<00:13.00>').single;
    expect(line.words.map((word) => word.text), ['Hello', ' World']);
    expect(line.words.map((word) => word.start.inMilliseconds), [12000, 12500]);
    expect(line.end?.inMilliseconds, 13000);
  });

  test('same timestamps and adjacent plain lines attach translations', () {
    final lines = parseRichLyrics(
      '[00:01.00]Hello\n[00:01.00]你好\n[00:01.00]こんにちは\n[00:04.00]World\n世界',
      romaji: '[00:01.00]heroo\n[00:04.00]warudo',
    );
    expect(lines.map((line) => line.text), ['Hello', 'World']);
    expect(lines.map((line) => line.translation), ['你好\nこんにちは', '世界']);
    expect(lines.map((line) => line.romaji), ['heroo', 'warudo']);
  });

  test('YRC absolute word times become one synchronized line', () {
    final line = parseLrc('[1000,2000](1000,1000,0)你(2000,1000,0)好').single;
    expect(line.text, '你好');
    expect(line.time.inMilliseconds, 1000);
    expect(line.end?.inMilliseconds, 3000);
    expect(line.words.map((word) => word.start.inMilliseconds), [1000, 2000]);
  });

  test('metadata, offset and JSON lines do not become lyrics', () {
    final lines = parseLrc(
      '[offset:500]\n[ar:test]\n{"t":0,"c":[{"tx":"作词"}]}\n[00:01.00]你好',
    );
    expect(lines.single.text, '你好');
    expect(lines.single.time.inMilliseconds, 500);
  });
}
