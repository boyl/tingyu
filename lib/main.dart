import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'controllers/library_controller.dart';
import 'services/bilibili.dart';
import 'services/downloads.dart';
import 'services/desktop.dart';
import 'services/playback.dart';
import 'services/storage.dart';
import 'services/lyrics.dart';
import 'ui/app.dart';
import 'ui/theme.dart';

final libraryProvider = ChangeNotifierProvider<LibraryController>(
  (ref) => throw StateError('Application dependencies are not initialized'),
);
Future<void> main() => runTingyu();

/// Composition boundary: production uses native services; tests inject fixtures.
Future<void> runTingyu({
  BilibiliClient? client,
  Directory? dataDirectory,
  LyricsClient? lyricsClient,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final directory = dataDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final db = AppDatabase.open(
      File(path.join(directory.path, 'tingyu.sqlite')),
    );
    final api = client ?? BilibiliClient(SecureCredentials());
    final downloads = DownloadManager(
      api,
      db,
      Directory(path.join(directory.path, 'downloads')),
      lyricsClient: lyricsClient,
    );
    final playback = await PlaybackHandler.initialize();
    final controller = LibraryController(
      api,
      db,
      downloads,
      playback,
      lyricsClient: lyricsClient,
    );
    await controller.initialize();
    if (Platform.isMacOS || Platform.isWindows) {
      await DesktopIntegration(controller).initialize();
    }
    runApp(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((ref) => controller)],
        child: const TingyuApp(),
      ),
    );
  } on Exception catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('听屿暂时无法启动，请检查系统播放器及本地存储配置。\n错误类型：${e.runtimeType}'),
            ),
          ),
        ),
      ),
    );
  }
}

final _router = createRouter();
GoRouter createRouter() => GoRouter(
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => shell,
      branches: [
        for (final route in ['library', 'search', 'downloads', 'likes'])
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: route == 'library' ? '/' : '/$route',
                pageBuilder: (_, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: AppShell(page: route),
                ),
                routes: [
                  if (route == 'library')
                    GoRoute(
                      path: 'playlist/:id',
                      builder: (_, state) => AppShell(
                        page: 'playlist',
                        playlistId: state.pathParameters['id'],
                      ),
                    ),
                ],
              ),
            ],
          ),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (_, _) => const SettingsScreen(),
      routes: [
        GoRoute(
          path: 'downloads',
          builder: (_, _) => const SettingsStorageScreen(),
        ),
      ],
    ),
    GoRoute(path: '/player', builder: (_, _) => const PlayerScreen()),
  ],
);

class TingyuApp extends ConsumerWidget {
  const TingyuApp({super.key, this.router});
  final GoRouter? router;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(libraryProvider.select((v) => v.theme));
    return MaterialApp.router(
      title: '听屿',
      debugShowCheckedModeBanner: false,
      theme: tingyuTheme(theme),
      themeAnimationDuration: Duration.zero,
      routerConfig: router ?? _router,
    );
  }
}
