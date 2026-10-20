import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import '../models/music.dart';

class PreparedExport {
  const PreparedExport(
    this.file, {
    required this.hasCover,
    required this.hasLyrics,
  });
  final File file;
  final bool hasCover, hasLyrics;
}

/// Only edits a staging copy. Metadata is small; audio boxes are streamed unchanged.
class MediaExporter {
  static const channel = MethodChannel('app.tingyu/export');
  static Future<String?> embeddedLyrics(File file) => Isolate.run(() {
    final input = file.openSync();
    try {
      if (input.lengthSync() < 8) return null;
      final header = input.readSync(8);
      if (String.fromCharCodes(header.sublist(4)) != 'ftyp') return null;
    } finally {
      input.closeSync();
    }
    try {
      final text = readMetadata(file, getImage: false).lyrics;
      return text != null && text.trim().isNotEmpty ? text : null;
    } on MetadataParserException {
      return null;
    } on FormatException {
      return null;
    }
  });

  Future<PreparedExport> prepare({
    required File audio,
    required Track track,
    required Directory directory,
    File? cover,
    String? lyrics,
  }) async {
    await directory.create(recursive: true);
    final work = await directory.createTemp('export-');
    final destination = File(path.join(work.path, 'audio.m4a'));
    try {
      final details = await Isolate.run(
        () => _prepare(
          audio.path,
          destination.path,
          track.title,
          track.artist,
          track.part,
          cover?.path,
          lyrics,
        ),
      );
      return PreparedExport(
        destination,
        hasCover: details.$1,
        hasLyrics: details.$2,
      );
    } on MetadataParserException {
      await work.delete(recursive: true);
      throw const AppFailure('音频标签无法解析，原下载文件保留');
    } on FormatException {
      await work.delete(recursive: true);
      throw const AppFailure('音频容器格式异常，原下载文件保留');
    } catch (_) {
      await work.delete(recursive: true);
      rethrow;
    }
  }

  Future<String?> save(PreparedExport prepared, String suggestedName) async {
    final name = sanitizeFileName(suggestedName);
    if (Platform.isAndroid) {
      final result = await channel.invokeMapMethod<String, dynamic>('saveM4a', {
        'path': prepared.file.path,
        'name': name,
      });
      return result?['uri'] as String?;
    }
    final selected = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'M4A',
          extensions: ['m4a'],
          uniformTypeIdentifiers: ['com.apple.m4a-audio'],
        ),
      ],
    );
    if (selected == null) return null;
    var target = selected.path;
    if (!target.toLowerCase().endsWith('.m4a')) target = '$target.m4a';
    final temp = File(
      '$target.tingyu-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await prepared.file.copy(temp.path);
      await temp.rename(target);
      return target;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}

String sanitizeFileName(String title) {
  var clean = title
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (clean.toLowerCase().endsWith('.m4a')) {
    clean = clean.substring(0, clean.length - 4);
  }
  if (clean.isEmpty) clean = 'tingyu 音频';
  if (RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
    caseSensitive: false,
  ).hasMatch(clean)) {
    clean = '_$clean';
  }
  clean = String.fromCharCodes(clean.runes.take(80));
  return '$clean.m4a';
}

class _Box {
  const _Box(this.start, this.size, this.type, this.header);
  final int start, size, header;
  final String type;
}

List<_Box> _boxes(RandomAccessFile input, int start, int end) {
  final result = <_Box>[];
  var at = start;
  while (at < end) {
    if (end - at < 8) throw const AppFailure('音频容器不完整，无法导出');
    input.setPositionSync(at);
    final bytes = input.readSync(8);
    final data = ByteData.sublistView(bytes);
    var size = data.getUint32(0), header = 8;
    if (size == 1) {
      if (end - at < 16) throw const AppFailure('音频扩展头不完整');
      size = ByteData.sublistView(input.readSync(8)).getUint64(0);
      header = 16;
    }
    if (size == 0) size = end - at;
    if (size < header || size > end - at) {
      throw const AppFailure('音频容器长度异常，无法导出');
    }
    result.add(_Box(at, size, latin1.decode(bytes.sublist(4)), header));
    at += size;
  }
  return result;
}

Uint8List _readBox(RandomAccessFile input, _Box box) {
  if (box.size > 16 * 1024 * 1024 || box.header != 8) {
    throw const AppFailure('音频索引格式暂不支持导出');
  }
  input.setPositionSync(box.start);
  return input.readSync(box.size);
}

void _copy(
  RandomAccessFile input,
  RandomAccessFile output,
  int start,
  int length,
) {
  input.setPositionSync(start);
  var remaining = length;
  while (remaining > 0) {
    final bytes = input.readSync(
      remaining < 1024 * 1024 ? remaining : 1024 * 1024,
    );
    if (bytes.isEmpty) throw const AppFailure('音频读取中断，请重试');
    output.writeFromSync(bytes);
    remaining -= bytes.length;
  }
}

void _checkFragment(RandomAccessFile input, _Box box) {
  for (final child in _boxes(
    input,
    box.start + box.header,
    box.start + box.size,
  )) {
    if (child.type == 'traf') _checkFragment(input, child);
    if (child.type == 'tfhd') {
      input.setPositionSync(child.start + child.header);
      if (child.size < child.header + 4 ||
          ByteData.sublistView(input.readSync(4)).getUint32(0) & 1 != 0) {
        throw const AppFailure('该分段音频需要重封装后才能导出，原下载不受影响');
      }
    }
  }
}

(bool, bool) _prepare(
  String sourcePath,
  String destinationPath,
  String title,
  String artist,
  int part,
  String? coverPath,
  String? lyrics,
) {
  final source = File(sourcePath).openSync();
  final skeleton = File('$destinationPath.tags.m4a');
  try {
    final boxes = _boxes(source, 0, source.lengthSync());
    final moovs = boxes.where((b) => b.type == 'moov').toList();
    final media = boxes.where((b) => b.type == 'mdat').toList();
    if (boxes.isEmpty ||
        boxes.first.type != 'ftyp' ||
        moovs.length != 1 ||
        media.isEmpty) {
      throw const AppFailure('当前下载并非可直接导出的 M4A 音频，不会仅修改扩展名');
    }
    final moov = moovs.single;
    final before = moov.start < media.first.start;
    if (!before && moov.start < media.last.start) {
      throw const AppFailure('该音频索引布局暂不支持导出');
    }
    if (before &&
        boxes.any(
          (b) => b.type == 'mfra' || (b.type == 'sidx' && b.start < moov.start),
        )) {
      throw const AppFailure('该分段音频索引暂不支持导出');
    }
    for (final fragment in boxes.where((b) => b.type == 'moof')) {
      _checkFragment(source, fragment);
    }
    final ftyp = _readBox(source, boxes.first),
        oldMoov = _readBox(source, moov);
    final dummyMdat = Uint8List.fromList([0, 0, 0, 8, 109, 100, 97, 116]);
    skeleton.writeAsBytesSync([
      ...ftyp,
      if (!before) ...dummyMdat,
      ...oldMoov,
      if (before) ...dummyMdat,
    ]);
    Uint8List? cover;
    String? mime;
    if (coverPath != null && File(coverPath).existsSync()) {
      final bytes = File(coverPath).readAsBytesSync();
      if (bytes.length >= 8 &&
          bytes[0] == 137 &&
          bytes[1] == 80 &&
          bytes[2] == 78 &&
          bytes[3] == 71) {
        cover = bytes;
        mime = 'image/png';
      } else if (bytes.length >= 3 &&
          bytes[0] == 255 &&
          bytes[1] == 216 &&
          bytes[2] == 255) {
        cover = bytes;
        mime = 'image/jpeg';
      }
    }
    final hasLyrics = lyrics?.trim().isNotEmpty == true;
    updateMetadata(skeleton, (tag) {
      if (tag is! Mp4Metadata) throw const AppFailure('音频标签格式不支持');
      tag.setTitle(title);
      // Preserve the uploader identity without claiming it is the performer.
      tag.setArtist('UP主：$artist');
      tag.setTrackNumber(part);
      if (hasLyrics) tag.setLyrics(lyrics);
      if (cover != null) {
        tag.setPictures([Picture(cover, mime!, PictureType.coverFront)]);
      }
    });
    final tagged = skeleton.openSync();
    late Uint8List updated;
    try {
      updated = _readBox(
        tagged,
        _boxes(
          tagged,
          0,
          tagged.lengthSync(),
        ).singleWhere((b) => b.type == 'moov'),
      );
    } finally {
      tagged.closeSync();
    }
    final output = File(destinationPath).openSync(mode: FileMode.write);
    try {
      for (final box in boxes) {
        if (box == moov) {
          output.writeFromSync(updated);
        } else {
          _copy(source, output, box.start, box.size);
        }
      }
      output.flushSync();
    } finally {
      output.closeSync();
    }
    final verified = readMetadata(File(destinationPath), getImage: true);
    if (verified.title != title ||
        (hasLyrics && verified.lyrics != lyrics) ||
        (cover != null && verified.pictures.isEmpty)) {
      throw const AppFailure('导出文件标签校验失败，请重试');
    }
    return (
      verified.pictures.isNotEmpty,
      verified.lyrics?.trim().isNotEmpty == true,
    );
  } finally {
    source.closeSync();
    if (skeleton.existsSync()) skeleton.deleteSync();
  }
}
