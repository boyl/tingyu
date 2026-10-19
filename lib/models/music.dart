import 'dart:convert';
import 'lyrics.dart';
export 'lyrics.dart';

class Track {
  const Track({
    required this.bvid,
    required this.cid,
    required this.title,
    required this.artist,
    required this.cover,
    required this.duration,
    this.part = 1,
  });
  final String bvid, title, artist, cover;
  final int cid, duration, part;
  String get id => '$bvid:$cid';
  Map<String, dynamic> toJson() => {
    'bvid': bvid,
    'cid': cid,
    'title': title,
    'artist': artist,
    'cover': cover,
    'duration': duration,
    'part': part,
  };
  factory Track.fromJson(Map<String, dynamic> j) => Track(
    bvid: j['bvid'],
    cid: j['cid'] ?? 0,
    title: j['title'],
    artist: j['artist'] ?? '',
    cover: j['cover'] ?? '',
    duration: j['duration'] ?? 0,
    part: j['part'] ?? 1,
  );
  static List<Track> decodeList(String value) => (jsonDecode(value) as List)
      .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

class AudioStream {
  const AudioStream(this.url, this.headers, this.quality);
  final String url, quality;
  final Map<String, String> headers;
}

class Playlist {
  const Playlist(this.id, this.name, this.trackIds, {this.description = ''});
  final String id, name, description;
  final List<String> trackIds;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tracks': trackIds,
    'description': description,
  };
  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
    j['id'],
    j['name'],
    List<String>.from(j['tracks']),
    description: j['description'] ?? '',
  );
}

enum DownloadStatus { waiting, downloading, completed, failed, paused }

enum DownloadLyricStatus { waiting, fetching, available, missing, failed }

class DownloadTask {
  DownloadTask(
    this.track, {
    this.status = DownloadStatus.waiting,
    this.lyricStatus = DownloadLyricStatus.waiting,
    this.received = 0,
    this.total = 0,
    this.filePath,
    this.completedAt,
    this.error,
  });
  final Track track;
  DownloadStatus status;
  DownloadLyricStatus lyricStatus;
  int received, total;
  String? filePath, error;
  DateTime? completedAt;
  double? get progress => total > 0 ? (received / total).clamp(0, 1) : null;
  Map<String, dynamic> toJson() => {
    'track': track.toJson(),
    'status': status.name,
    'lyricStatus': lyricStatus.name,
    'received': received,
    'total': total,
    'filePath': filePath,
    'completedAt': completedAt?.toUtc().toIso8601String(),
    'error': error,
  };
  factory DownloadTask.fromJson(Map<String, dynamic> j) => DownloadTask(
    Track.fromJson(Map<String, dynamic>.from(j['track'])),
    status: DownloadStatus.values.byName(j['status']),
    lyricStatus: DownloadLyricStatus.values.byName(
      j['lyricStatus'] ?? 'waiting',
    ),
    received: j['received'] ?? 0,
    total: j['total'] ?? 0,
    filePath: j['filePath'],
    completedAt: j['completedAt'] == null
        ? null
        : DateTime.parse(j['completedAt']),
    error: j['error'],
  );
}

class AppFailure implements Exception {
  const AppFailure(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => message;
}

/// Latest non-empty line that has already started. Blank gap markers stay in
/// the list but do not replace the readable lyric.
int focusedLyricLine(List<LyricLine> lines, int positionMillis) {
  var index = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].time.inMilliseconds > positionMillis) break;
    if (lines[i].text.isNotEmpty) index = i;
  }
  if (index >= 0) return index;
  final first = lines.indexWhere((line) => line.text.isNotEmpty);
  return first < 0 ? 0 : first;
}

double centeredLyricOffset({
  required int index,
  required double viewport,
  required double maxScroll,
  double padding = 12,
  double lineExtent = 64,
}) {
  final raw = padding + index * lineExtent - (viewport - lineExtent) / 2;
  if (maxScroll.isNaN || maxScroll <= 0) return 0;
  return raw.clamp(0.0, maxScroll);
}

String clock(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
