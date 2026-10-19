import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

class UsageFile {
  const UsageFile(this.path, this.bytes, this.modified);
  final String path;
  final int bytes;
  final DateTime modified;
}

class StorageUsage {
  StorageUsage(this.bytes, this.temporary, {this.installUnavailable = false});
  final bool installUnavailable;
  static Future<StorageUsage> scanWithInstall(Directory root) async {
    final data = await scan(root);
    if (!Platform.isAndroid) return data;
    try {
      final bytes = await const MethodChannel(
        'app.tingyu/storage',
      ).invokeMethod<int>('installedBytes');
      if (bytes == null || bytes <= 0) {
        return StorageUsage(
          data.bytes,
          data.temporary,
          installUnavailable: true,
        );
      }
      return StorageUsage({...data.bytes, '应用安装': bytes}, data.temporary);
    } on PlatformException {
      return StorageUsage(data.bytes, data.temporary, installUnavailable: true);
    } on MissingPluginException {
      return StorageUsage(data.bytes, data.temporary, installUnavailable: true);
    }
  }

  final Map<String, int> bytes;
  final List<UsageFile> temporary;
  int get total => bytes.values.fold(0, (a, b) => a + b);
  static const categories = ['已下载音频', '封面缓存', '歌词', '临时文件', '其他资料'];
  static Future<StorageUsage> scan(Directory root) async {
    final sizes = {for (final key in categories) key: 0};
    final temporary = <UsageFile>[];
    if (!await root.exists()) return StorageUsage(sizes, temporary);
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      final stat = await entry.stat();
      final ext = path.extension(entry.path).toLowerCase();
      final category = switch (ext) {
        '.m4a' || '.mp3' || '.wav' || '.flac' => categories[0],
        '.cover' || '.jpg' || '.png' || '.webp' => categories[1],
        '.lyrics' || '.lrc' || '.spl' || '.yrc' => categories[2],
        '.part' || '.tmp' => categories[3],
        _ => categories[4],
      };
      sizes[category] = sizes[category]! + stat.size;
      if (category == categories[3]) {
        temporary.add(UsageFile(entry.path, stat.size, stat.modified));
      }
    }
    return StorageUsage(sizes, temporary);
  }

  Future<void> clearTemporary(
    Directory root, {
    required bool transferActive,
  }) async {
    if (transferActive) throw const FileSystemException('下载处理中，请稍后清理');
    final safeRoot = path.normalize(path.absolute(root.path));
    for (final item in temporary) {
      final file = File(item.path);
      if (!path.isWithin(safeRoot, path.normalize(path.absolute(item.path)))) {
        continue;
      }
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final resolved = await file.resolveSymbolicLinks();
      if (!path.isWithin(await root.resolveSymbolicLinks(), resolved)) continue;
      final stat = await file.stat();
      if (stat.size == item.bytes && stat.modified == item.modified) {
        await file.delete();
      }
    }
  }
}
