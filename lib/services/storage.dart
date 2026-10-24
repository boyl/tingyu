import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/music.dart';

class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);
  factory AppDatabase.open(File file) =>
      AppDatabase(NativeDatabase.createInBackground(file));
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE tracks (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
      );
    },
  );
  Future<Map<String, dynamic>?> readState(String key) async {
    final row = await customSelect(
      'SELECT value FROM app_state WHERE key = ?',
      variables: [Variable(key)],
    ).getSingleOrNull();
    return row == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(row.read<String>('value')));
  }

  Future<void> writeState(
    String key,
    Map<String, dynamic> value,
  ) => customStatement(
    'INSERT INTO app_state(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, jsonEncode(value)],
  );
  Future<void> saveTrack(Track track) => customStatement(
    'INSERT INTO tracks(id,payload) VALUES (?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
    [track.id, jsonEncode(track.toJson())],
  );
  Future<void> deleteTrack(String id) =>
      customStatement('DELETE FROM tracks WHERE id = ?', [id]);
  Future<List<Track>> loadTracks() async =>
      (await customSelect(
            'SELECT payload FROM tracks ORDER BY rowid DESC',
          ).get())
          .map(
            (r) => Track.fromJson(
              Map<String, dynamic>.from(jsonDecode(r.read<String>('payload'))),
            ),
          )
          .toList();
}

abstract interface class CredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureCredentials implements CredentialStore {
  SecureCredentials({
    bool macosPreview = const bool.fromEnvironment('TINGYU_MACOS_PREVIEW'),
  }) : _macosPreview = macosPreview,
       _storage = FlutterSecureStorage(
         // 本地 ad-hoc 预览没有共享钥匙串的 provisioning；仍使用系统加密钥匙串。
         mOptions: MacOsOptions(usesDataProtectionKeychain: !macosPreview),
       );
  final bool _macosPreview;
  final FlutterSecureStorage _storage;
  static const _key = 'bilibili.session';
  @override
  Future<String?> read() async {
    try {
      return await _storage.read(
        key: _key,
        // ad-hoc 重签可能触发旧记录的授权窗口，启动时只做非交互读取。
        mOptions: _macosPreview
            ? const MacOsOptions(
                usesDataProtectionKeychain: false,
                authenticationUIBehavior: 'u_AuthUIF',
              )
            : null,
      ).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      throw const AppFailure('读取登录状态超时，请在账号中重试或处理系统钥匙串提示');
    } on PlatformException {
      throw const AppFailure('无法读取登录状态，请在账号中重新登录或允许系统钥匙串访问');
    }
  }
  @override
  Future<void> write(String value) async {
    try {
      await _storage.write(key: _key, value: value);
    } on PlatformException {
      throw const AppFailure('无法安全保存登录状态，请检查系统安全存储权限后重试');
    }
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
