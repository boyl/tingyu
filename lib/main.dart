import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
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
  final launchClock = Stopwatch();
  runApp(const TingyuLaunch());
  WidgetsBinding.instance.addPostFrameCallback((_) => launchClock.start());
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
    if (!launchClock.isRunning) await WidgetsBinding.instance.endOfFrame;
    final remaining = const Duration(milliseconds: 900) - launchClock.elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
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
              child: Text(
                'tingyu 暂时无法启动，请检查系统播放器及本地存储配置。\n错误类型：${e.runtimeType}',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Page<void> collectionPage(
  BuildContext context, {
  required LocalKey key,
  required Widget child,
}) {
  final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return CustomTransitionPage<void>(
    key: key,
    child: RepaintBoundary(child: child),
    transitionDuration: reduced ? Duration.zero : TingyuTokens.transition,
    reverseTransitionDuration: reduced
        ? Duration.zero
        : TingyuTokens.transition,
    transitionsBuilder: (context, animation, secondary, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: eased,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(.035, 0),
            end: Offset.zero,
          ).animate(eased),
          child: child,
        ),
      );
    },
  );
}

final _router = createRouter(macOS: Platform.isMacOS);
GoRouter createRouter({bool macOS = false}) => GoRouter(
  routes: [
    if (macOS)
      GoRoute(
        path: '/',
        builder: (_, _) => const MacWorkspace(),
        routes: [
          GoRoute(
            path: 'playlist/:id/add',
            builder: (_, state) =>
                PlaylistAddScreen(playlistId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'search',
                builder: (_, state) => AppShell(
                  page: 'search',
                  playlistId: state.pathParameters['id'],
                ),
              ),
            ],
          ),
        ],
      )
    else
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
                    child: AppShell(
                      page: route,
                      downloadSection: state.uri.queryParameters['section'],
                    ),
                  ),
                  routes: [
                    if (route == 'library')
                      GoRoute(
                        path: 'playlists',
                        builder: (_, _) => const PlaylistsScreen(),
                      ),
                    if (route == 'library')
                      GoRoute(
                        path: 'playlist/:id',
                        pageBuilder: (context, state) => collectionPage(
                          context,
                          key: state.pageKey,
                          child: AppShell(
                            page: 'playlist',
                            playlistId: state.pathParameters['id'],
                          ),
                        ),
                        routes: [
                          GoRoute(
                            path: 'add',
                            pageBuilder: (context, state) => collectionPage(
                              context,
                              key: state.pageKey,
                              child: PlaylistAddScreen(
                                playlistId: state.pathParameters['id']!,
                              ),
                            ),
                            routes: [
                              GoRoute(
                                path: 'search',
                                pageBuilder: (context, state) => collectionPage(
                                  context,
                                  key: state.pageKey,
                                  child: AppShell(
                                    page: 'search',
                                    playlistId: state.pathParameters['id'],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
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
    GoRoute(
      path: '/settings/account',
      builder: (_, _) => const AccountScreen(),
    ),
    GoRoute(
      path: '/settings/glass',
      builder: (_, _) => const GlassPreferencesScreen(),
    ),
    GoRoute(path: '/lyrics', builder: (_, _) => const LyricsScreen()),
    GoRoute(
      path: '/player',
      builder: (_, _) => macOS
          ? const MacWorkspace(initialPage: 'details')
          : const PlayerScreen(),
    ),
  ],
);

class TingyuApp extends ConsumerWidget {
  const TingyuApp({super.key, this.router});
  final GoRouter? router;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(libraryProvider.select((v) => v.theme));
    return MaterialApp.router(
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: child!,
        );
      },
      title: 'tingyu',
      debugShowCheckedModeBanner: false,
      theme: tingyuTheme(theme),
      themeAnimationDuration: Duration.zero,
      routerConfig: router ?? _router,
    );
  }
}

class TingyuLaunch extends StatelessWidget {
  const TingyuLaunch({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: tingyuTheme('bili'),
    home: Builder(
      builder: (context) => Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        context.tokens.accentInk,
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        'assets/branding/ribbon-outline.png',
                        width: TingyuTokens.space * 15,
                        height: TingyuTokens.space * 15,
                      ),
                    ),
                    const SizedBox(height: TingyuTokens.space * 2),
                    const Text(
                      'tingyu',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: TingyuTokens.space * 6,
                left: 0,
                right: 0,
                child: Text(
                  'v$tingyuVersion',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.tokens.muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
