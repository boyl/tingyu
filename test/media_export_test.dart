import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/media_export.dart';
import 'support/fakes.dart';

String mediaHash(File file) {
  final input = file.openSync();
  final bytes = BytesBuilder();
  try {
    while (input.positionSync() < input.lengthSync()) {
      final header = input.readSync(8),
          size = ByteData.sublistView(header).getUint32(0);
      final at = input.positionSync();
      if (String.fromCharCodes(header.sublist(4)) == 'mdat') {
        bytes.add(input.readSync(size - 8));
      }
      input.setPositionSync(at + size - 8);
    }
  } finally {
    input.closeSync();
  }
  return sha256.convert(bytes.takeBytes()).toString();
}

File fastStart(File source, File target, {bool tail = false}) {
  final bytes = source.readAsBytesSync();
  final parts = <Uint8List>[];
  var position = 0;
  while (position < bytes.length) {
    final size = ByteData.sublistView(bytes).getUint32(position);
    parts.add(Uint8List.fromList(bytes.sublist(position, position + size)));
    position += size;
  }
  String type(Uint8List box) => String.fromCharCodes(box.sublist(4, 8));
  final moov = parts.singleWhere((box) => type(box) == 'moov');
  final before =
      parts.indexOf(moov) < parts.indexWhere((box) => type(box) == 'mdat');
  final delta = tail ? (before ? -moov.length : 0) : (before ? 0 : moov.length);
  void shift(Uint8List box, int from, int to) {
    var offset = from;
    while (offset + 8 <= to) {
      final data = ByteData.sublistView(box);
      final length = data.getUint32(offset);
      final name = String.fromCharCodes(box.sublist(offset + 4, offset + 8));
      if (name == 'stco') {
        final count = data.getUint32(offset + 12);
        for (var i = 0; i < count; i++) {
          final at = offset + 16 + i * 4;
          data.setUint32(at, data.getUint32(at) + delta);
        }
      } else if (['moov', 'trak', 'mdia', 'minf', 'stbl'].contains(name)) {
        shift(box, offset + 8, offset + length);
      }
      offset += length;
    }
  }

  shift(moov, 0, moov.length);
  target.writeAsBytesSync([
    ...parts.first,
    if (!tail) ...moov,
    for (final box in parts.skip(1))
      if (type(box) != 'moov') ...box,
    if (tail) ...moov,
  ]);
  return target;
}

void main() {
  test('fast-start M4A offsets stay decodable after metadata growth', () async {
    final dir = await Directory.systemTemp.createTemp('tingyu-export-fast-');
    final source = fastStart(
      File('test/fixtures/export-tone.m4a'),
      File('${dir.path}/fast.m4a'),
    );
    final result = await MediaExporter().prepare(
      audio: source,
      track: firstTrack,
      directory: dir,
      cover: File('assets/tray.png'),
      lyrics: '[00:00.00]歌词\n[00:00.50] ',
    );
    expect(mediaHash(result.file), mediaHash(source));
    expect(readMetadata(result.file).lyrics, '[00:00.00]歌词\n[00:00.50] ');
    if (Platform.isMacOS && File('/usr/bin/afconvert').existsSync()) {
      final decode = await Process.run('/usr/bin/afconvert', [
        '-f',
        'WAVE',
        '-d',
        'LEI16',
        result.file.path,
        '${dir.path}/decoded.wav',
      ]);
      expect(decode.exitCode, 0, reason: '${decode.stderr}');
      expect(
        await File('${dir.path}/decoded.wav').length(),
        greaterThan(40000),
      );
    }
    await dir.delete(recursive: true);
  });

  test('trailing-index M4A stays decodable after metadata growth', () async {
    final dir = await Directory.systemTemp.createTemp('tingyu-export-tail-');
    final source = fastStart(
      File('test/fixtures/export-tone.m4a'),
      File('${dir.path}/tail.m4a'),
      tail: true,
    );
    final result = await MediaExporter().prepare(
      audio: source,
      track: firstTrack,
      directory: dir,
      lyrics: '[00:00.00]尾部索引测试',
    );
    expect(mediaHash(result.file), mediaHash(source));
    if (Platform.isMacOS && File('/usr/bin/afconvert').existsSync()) {
      final decode = await Process.run('/usr/bin/afconvert', [
        '-f',
        'WAVE',
        '-d',
        'LEI16',
        result.file.path,
        '${dir.path}/decoded.wav',
      ]);
      expect(decode.exitCode, 0, reason: '${decode.stderr}');
    }
    await dir.delete(recursive: true);
  });
  test(
    'M4A exports real cover, lyrics and title, keeps audio bytes and original intact',
    () async {
      final dir = await Directory.systemTemp.createTemp('tingyu-export-');
      final audio = File('test/fixtures/export-tone.m4a');
      final original = sha256.convert(await audio.readAsBytes()).toString();
      final result = await MediaExporter().prepare(
        audio: audio,
        track: firstTrack,
        directory: dir,
        cover: File('assets/tray.png'),
        lyrics: '[00:00.00]测试歌词',
      );
      final tags = readMetadata(result.file, getImage: true);
      expect(tags.title, firstTrack.title);
      expect(tags.artist, 'UP主：${firstTrack.artist}');
      expect(tags.lyrics, '[00:00.00]测试歌词');
      expect(
        tags.pictures.single.bytes,
        await File('assets/tray.png').readAsBytes(),
      );
      expect(mediaHash(result.file), mediaHash(audio));
      expect(sha256.convert(await audio.readAsBytes()).toString(), original);
      expect(result.hasLyrics, isTrue);
      expect(result.hasCover, isTrue);
      expect(await MediaExporter.embeddedLyrics(result.file), '[00:00.00]测试歌词');
      final again = await MediaExporter().prepare(
        audio: result.file,
        track: firstTrack,
        directory: dir,
      );
      expect(again.hasCover, isTrue);
      expect(again.hasLyrics, isTrue);
      expect(readMetadata(again.file).lyrics, '[00:00.00]测试歌词');
      await dir.delete(recursive: true);
    },
  );
  test(
    'non-M4A fails honestly, missing attachments do not become fake metadata',
    () async {
      final dir = await Directory.systemTemp.createTemp('tingyu-export-empty-');
      final result = await MediaExporter().prepare(
        audio: File('test/fixtures/export-tone.m4a'),
        track: firstTrack,
        directory: dir,
      );
      expect(result.hasLyrics, isFalse);
      expect(result.hasCover, isFalse);
      final wrong = File('${dir.path}/wrong.m4a')
        ..writeAsBytesSync([82, 73, 70, 70]);
      await expectLater(
        MediaExporter().prepare(
          audio: wrong,
          track: firstTrack,
          directory: dir,
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(sanitizeFileName('../CON<>:/?.m4a'), isNot(contains('/')));
      expect(sanitizeFileName('CON'), '_CON.m4a');
      await dir.delete(recursive: true);
    },
  );
}
