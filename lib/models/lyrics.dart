/// Application-owned lyric timeline. Supports LRC, SPL/enhanced LRC and YRC.
/// Format reference: https://github.com/bbplayer-app/BBPlayer (SPL / splash).
class LyricWord {
  const LyricWord(this.text, this.start, this.end);
  final String text;
  final Duration start, end;
  double progress(int milliseconds) {
    if (milliseconds < start.inMilliseconds) return 0;
    final length = end.inMilliseconds - start.inMilliseconds;
    return length <= 0
        ? 1
        : ((milliseconds - start.inMilliseconds) / length).clamp(0.0, 1.0);
  }
}

class LyricLine {
  const LyricLine(
    this.time,
    this.text, {
    this.end,
    this.words = const [],
    this.translation = '',
    this.romaji = '',
  });
  final Duration time;
  final String text, translation, romaji;
  final Duration? end;
  final List<LyricWord> words;
  LyricLine withSecondary({
    String? translation,
    String? romaji,
    Duration? end,
    List<LyricWord>? words,
  }) => LyricLine(
    time,
    text,
    end: end ?? this.end,
    words: words ?? this.words,
    translation: translation ?? this.translation,
    romaji: romaji ?? this.romaji,
  );
}

final _stamp = RegExp(r'[\[<](\d{1,3}):(\d{1,2}(?:\.\d{1,6})?)[\]>]');
int? _milliseconds(Match match) {
  final seconds = double.tryParse(match[2]!);
  if (seconds == null || seconds >= 60) return null;
  return ((int.parse(match[1]!) * 60 + seconds) * 1000).round();
}

List<LyricLine> parseLrc(String text) => parseRichLyrics(text);

List<LyricLine> parseRichLyrics(
  String text, {
  String translation = '',
  String romaji = '',
}) {
  final offset =
      int.tryParse(
        RegExp(
              r'\[offset:([+-]?\d+)\]',
              caseSensitive: false,
            ).firstMatch(text)?[1] ??
            '',
      ) ??
      0;
  final result = <LyricLine>[];
  void append(LyricLine line) {
    final i = result.indexWhere(
      (item) => item.time == line.time && item.text.isNotEmpty,
    );
    if (i >= 0 && line.text.isNotEmpty) {
      final before = result[i];
      result[i] = before.withSecondary(
        translation: [
          before.translation,
          line.text,
        ].where((s) => s.isNotEmpty).join('\n'),
      );
    } else {
      result.add(line);
    }
  }

  for (final raw in text.replaceAll('\r', '').split('\n')) {
    final row = raw.trim();
    if (row.isEmpty ||
        row.startsWith('{') ||
        RegExp(r'^\[[a-zA-Z]+:').hasMatch(row)) {
      continue;
    }
    final yrc = RegExp(r'^\[(\d+),(\d+)\]').firstMatch(row);
    if (yrc != null) {
      final start = int.parse(yrc[1]!) - offset;
      final end = start + int.parse(yrc[2]!);
      final words = <LyricWord>[];
      final spans = RegExp(
        r'\((\d+),(\d+),\d+\)([^\(]*)',
      ).allMatches(row.substring(yrc.end));
      for (final span in spans) {
        final at = int.parse(span[1]!) - offset;
        words.add(
          LyricWord(
            span[3]!,
            Duration(milliseconds: at),
            Duration(milliseconds: at + int.parse(span[2]!)),
          ),
        );
      }
      if (words.isNotEmpty) {
        append(
          LyricLine(
            Duration(milliseconds: start),
            words.map((word) => word.text).join(),
            end: Duration(milliseconds: end),
            words: words,
          ),
        );
      }
      continue;
    }
    final stamps = _stamp.allMatches(row).toList();
    if (stamps.isEmpty || stamps.first.start != 0) {
      // SPL allows an adjacent untimed translation, but malformed tags are not text.
      if (result.isNotEmpty && !row.startsWith('[') && !row.startsWith('<')) {
        final before = result.last;
        result[result.length - 1] = before.withSecondary(
          translation: [
            before.translation,
            row,
          ].where((s) => s.isNotEmpty).join('\n'),
        );
      }
      continue;
    }
    final leading = <RegExpMatch>[];
    var cursor = 0;
    for (final stamp in stamps) {
      if (stamp.start != cursor || row[stamp.start] != '[') break;
      leading.add(stamp);
      cursor = stamp.end;
    }
    if (leading.isEmpty) continue;
    final body = row.substring(cursor);
    final inside = _stamp.allMatches(body).toList();
    final content = body.replaceAll(_stamp, '').trim();
    for (final lead in leading) {
      final rawStart = _milliseconds(lead);
      if (rawStart == null) continue;
      final start = rawStart - offset;
      var at = start, position = 0;
      final words = <LyricWord>[];
      Duration? end;
      for (final stamp in inside) {
        final rawNext = _milliseconds(stamp);
        final next = rawNext == null ? null : rawNext - offset;
        final segment = body.substring(position, stamp.start);
        if (next != null && next >= at) {
          if (segment.isNotEmpty) {
            words.add(
              LyricWord(
                segment,
                Duration(milliseconds: at),
                Duration(milliseconds: next),
              ),
            );
          }
          at = next;
          if (stamp.end == body.length) end = Duration(milliseconds: next);
        }
        position = stamp.end;
      }
      final tail = body.substring(position);
      if (inside.isNotEmpty && tail.isNotEmpty) {
        words.add(
          LyricWord(
            tail,
            Duration(milliseconds: at),
            Duration(milliseconds: at),
          ),
        );
      }
      append(
        LyricLine(
          Duration(milliseconds: start),
          content,
          end: end,
          words: words,
        ),
      );
    }
  }
  result.sort((a, b) => a.time.compareTo(b.time));
  for (var i = 0; i < result.length; i++) {
    final line = result[i];
    final end = line.end ?? (i + 1 < result.length ? result[i + 1].time : null);
    final words = line.words
        .map(
          (word) => word.end <= word.start && end != null && end > word.start
              ? LyricWord(word.text, word.start, end)
              : word,
        )
        .toList();
    result[i] = line.withSecondary(end: end, words: words);
  }
  Map<int, String> secondary(String raw) => raw.trim().isEmpty
      ? {}
      : {
          for (final line in parseRichLyrics(raw))
            line.time.inMilliseconds: line.text,
        };
  final translated = secondary(translation), romanized = secondary(romaji);
  return [
    for (final line in result)
      line.withSecondary(
        translation: translated[line.time.inMilliseconds] ?? line.translation,
        romaji: romanized[line.time.inMilliseconds] ?? line.romaji,
      ),
  ];
}

String lyricSourceLabel(String source) => switch (source) {
  'netease' => '网易云音乐',
  'qqmusic' => 'QQ 音乐',
  'lrclib' => 'LRCLIB',
  'bilibili-ai-subtitle' => 'B 站 AI 字幕',
  'bilibili-cc-subtitle' => 'B 站字幕',
  'embedded' => '内嵌歌词',
  'manual' => '手动歌词',
  _ => source.isEmpty ? '歌词' : source,
};
