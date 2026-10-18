import 'dart:async';
import 'package:flutter/material.dart';
import '../models/appearance.dart';

@immutable
class TingyuTokens extends ThemeExtension<TingyuTokens> {
  const TingyuTokens({
    required this.background,
    required this.surface,
    required this.sidebar,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.tint,
    required this.line,
    required this.playerSurface,
    required this.playerBorder,
    required this.onPlayer,
    required this.playerMuted,
    required this.playerButton,
    required this.onPlayerButton,
    required this.playerTrack,
    required this.playerShadow,
    required this.danger,
  });
  final Color background,
      surface,
      sidebar,
      text,
      muted,
      accent,
      onAccent,
      tint,
      line,
      playerSurface,
      playerBorder,
      onPlayer,
      playerMuted,
      playerButton,
      onPlayerButton,
      playerTrack,
      playerShadow,
      danger;
  static const space = 8.0,
      radius = 12.0,
      iconSize = 22.0,
      controlSize = 48.0,
      avatarSize = 40.0,
      profileAvatarSize = 56.0,
      themePreviewHeight = 112.0,
      coverSize = 144.0,
      sheetRadius = 24.0,
      iconStroke = 1.7,
      heroRatio = 1.65,
      shelfVisibleCards = 2.35,
      playControlSize = 68.0,
      collectionRadius = 16.0,
      downloadTabWidth = 116.0,
      downloadTabHeight = 56.0,
      tabIndicatorHeight = 3.0,
      playerRadius = 28.0,
      playingPeriod = Duration(milliseconds: 900),
      scrollReturn = Duration(milliseconds: 320),
      pressDuration = Duration(milliseconds: 100),
      transition = Duration(milliseconds: 180);
  // Editorial category artwork has its own palette, like album cover imagery.
  static const onArtwork = Color(0xffffffff);
  static const discoveryPalettes = [
    [Color(0xff182847), Color(0xff526387), Color(0xff171d35)],
    [Color(0xffaa6986), Color(0xffe3ab93), Color(0xff514563)],
    [Color(0xff526e64), Color(0xffa4b5a0), Color(0xff293e40)],
    [Color(0xff946583), Color(0xffd2a3b5), Color(0xff554161)],
  ];
  static const sunrise = TingyuTokens(
    background: Color(0xfffff9f3),
    surface: Color(0xfffffdfa),
    sidebar: Color(0xfffcf1e7),
    text: Color(0xff33281f),
    muted: Color(0xff746453),
    accent: Color(0xffa54b0a),
    onAccent: Color(0xffffffff),
    tint: Color(0xfffff0df),
    line: Color(0xffefdfcd),
    danger: Color(0xffa43835),
    playerSurface: Color(0xffffead5),
    playerBorder: Color(0xffefd4b5),
    onPlayer: Color(0xff3d2b1e),
    playerMuted: Color(0xff7a5437),
    playerButton: Color(0xffeea15c),
    onPlayerButton: Color(0xff452708),
    playerTrack: Color(0xffdcb68f),
    playerShadow: Color(0x182d1808),
  );
  static const moon = TingyuTokens(
    background: Color(0xfff5f8fd),
    surface: Color(0xfffbfdff),
    sidebar: Color(0xffedf3fb),
    text: Color(0xff202c3e),
    muted: Color(0xff596a81),
    accent: Color(0xff355d98),
    onAccent: Color(0xffffffff),
    tint: Color(0xffe8effa),
    line: Color(0xffdce5f1),
    danger: Color(0xffa52f49),
    playerSurface: Color(0xffe4edfb),
    playerBorder: Color(0xffccd9ed),
    onPlayer: Color(0xff203149),
    playerMuted: Color(0xff536a87),
    playerButton: Color(0xff8daee0),
    onPlayerButton: Color(0xff162e50),
    playerTrack: Color(0xffb5c9e5),
    playerShadow: Color(0x14213a5b),
  );
  static const night = TingyuTokens(
    background: Color(0xff15151b),
    surface: Color(0xff202128),
    sidebar: Color(0xff1a1b22),
    text: Color(0xfff1f0f6),
    muted: Color(0xffaaa8b8),
    accent: Color(0xffc8b4ef),
    onAccent: Color(0xff271a3e),
    tint: Color(0xff2d2a38),
    line: Color(0xff3a3745),
    danger: Color(0xffff9ca9),
    playerSurface: Color(0xff282633),
    playerBorder: Color(0xff454050),
    onPlayer: Color(0xfff4efff),
    playerMuted: Color(0xffb9b0cb),
    playerButton: Color(0xffc8b4ef),
    onPlayerButton: Color(0xff271a3e),
    playerTrack: Color(0xff635a74),
    playerShadow: Color(0x3d000000),
  );
  static const bilibili = TingyuTokens(
    background: Color(0xfffffafb),
    surface: Color(0xffffffff),
    sidebar: Color(0xfffcf3f6),
    text: Color(0xff29232a),
    muted: Color(0xff766b73),
    accent: Color(0xffbf3565),
    onAccent: Color(0xffffffff),
    tint: Color(0xfffff0f5),
    line: Color(0xfff1e5e9),
    danger: Color(0xffad334c),
    playerSurface: Color(0xffffedf3),
    playerBorder: Color(0xfff5d5e1),
    onPlayer: Color(0xff38242d),
    playerMuted: Color(0xff795665),
    playerButton: Color(0xfffb7299),
    onPlayerButton: Color(0xff46172a),
    playerTrack: Color(0xffe5bbca),
    playerShadow: Color(0x125e2440),
  );
  static const themes = [
    ('bili', '哔哩粉', bilibili),
    ('sunrise', '日出橙', sunrise),
    ('moon', '月影蓝', moon),
    ('night', '夜间暗', night),
  ];
  @override
  TingyuTokens copyWith({
    Color? background,
    Color? surface,
    Color? sidebar,
    Color? text,
    Color? muted,
    Color? accent,
    Color? onAccent,
    Color? tint,
    Color? line,
    Color? playerSurface,
    Color? playerBorder,
    Color? onPlayer,
    Color? playerMuted,
    Color? playerButton,
    Color? onPlayerButton,
    Color? playerTrack,
    Color? playerShadow,
    Color? danger,
  }) => TingyuTokens(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    sidebar: sidebar ?? this.sidebar,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    tint: tint ?? this.tint,
    line: line ?? this.line,
    playerSurface: playerSurface ?? this.playerSurface,
    playerBorder: playerBorder ?? this.playerBorder,
    onPlayer: onPlayer ?? this.onPlayer,
    playerMuted: playerMuted ?? this.playerMuted,
    playerButton: playerButton ?? this.playerButton,
    onPlayerButton: onPlayerButton ?? this.onPlayerButton,
    playerTrack: playerTrack ?? this.playerTrack,
    playerShadow: playerShadow ?? this.playerShadow,
    danger: danger ?? this.danger,
  );
  @override
  TingyuTokens lerp(covariant TingyuTokens? other, double t) {
    if (other == null) return this;
    return TingyuTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      tint: Color.lerp(tint, other.tint, t)!,
      line: Color.lerp(line, other.line, t)!,
      playerSurface: Color.lerp(playerSurface, other.playerSurface, t)!,
      playerBorder: Color.lerp(playerBorder, other.playerBorder, t)!,
      onPlayer: Color.lerp(onPlayer, other.onPlayer, t)!,
      playerMuted: Color.lerp(playerMuted, other.playerMuted, t)!,
      playerButton: Color.lerp(playerButton, other.playerButton, t)!,
      onPlayerButton: Color.lerp(onPlayerButton, other.onPlayerButton, t)!,
      playerTrack: Color.lerp(playerTrack, other.playerTrack, t)!,
      playerShadow: Color.lerp(playerShadow, other.playerShadow, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension TingyuContext on BuildContext {
  TingyuTokens get tokens => Theme.of(this).extension<TingyuTokens>()!;
}

ThemeData tingyuTheme(String name) {
  final t =
      TingyuTokens.themes.where((item) => item.$1 == name).firstOrNull?.$3 ??
      TingyuTokens.themes.firstWhere((item) => item.$1 == defaultTheme).$3;
  return ThemeData(
    brightness: name == 'night' ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: t.background,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: t.accent,
          brightness: name == 'night' ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: t.accent,
          onPrimary: t.onAccent,
          surface: t.surface,
          onSurface: t.text,
          error: t.danger,
        ),
    extensions: [t],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    dividerColor: t.line,
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: t.text, fontSize: 14),
      bodySmall: TextStyle(color: t.muted, fontSize: 12),
      titleLarge: TextStyle(
        color: t.text,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      titleMedium: TextStyle(
        color: t.text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.tint,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: TingyuTokens.space * 2,
        vertical: TingyuTokens.space * 2,
      ),
      prefixIconColor: t.muted,
      hintStyle: TextStyle(color: t.muted, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TingyuTokens.collectionRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TingyuTokens.collectionRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TingyuTokens.collectionRadius),
        borderSide: BorderSide(color: t.accent),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accent,
      thumbColor: t.accent,
      inactiveTrackColor: t.line,
      trackHeight: 3,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TingyuTokens.sheetRadius),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TingyuTokens.radius),
      ),
    ),
  );
}

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onPressed,
    this.label,
    this.selected = false,
    this.selectionFill = true,
    this.padding = const EdgeInsets.all(12),
    this.color,
    this.minSize = 48,
    this.radius = TingyuTokens.radius,
  });
  final Widget child;
  final FutureOr<void> Function()? onPressed;
  final String? label;
  final bool selected, selectionFill;
  final EdgeInsets padding;
  final Color? color;
  final double minSize;
  final double radius;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false, hover = false, focus = false, pending = false;
  Future<void> _invoke() async {
    if (pending || widget.onPressed == null) return;
    final result = widget.onPressed!();
    if (result is Future) {
      if (!mounted) return;
      setState(() => pending = true);
      try {
        await result;
      } finally {
        if (mounted) setState(() => pending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      enabled: widget.onPressed != null && !pending,
      selected: widget.selected,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: widget.onPressed != null && !pending,
        onShowFocusHighlight: (v) => setState(() => focus = v),
        onShowHoverHighlight: (v) => setState(() => hover = v),
        mouseCursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              unawaited(_invoke());
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onPressed == null || pending ? null : _invoke,
          onTapDown: widget.onPressed == null || pending
              ? null
              : (_) => setState(() => down = true),
          onTapCancel: () => setState(() => down = false),
          onTapUp: (_) => setState(() => down = false),
          child: AnimatedScale(
            scale: (down && !MediaQuery.disableAnimationsOf(context))
                ? 0.99
                : 1.0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : TingyuTokens.pressDuration,
            child: Container(
              constraints: BoxConstraints(
                minWidth: widget.minSize,
                minHeight: widget.minSize,
              ),
              padding: widget.padding,
              decoration: BoxDecoration(
                color: widget.selected && widget.selectionFill
                    ? t.tint
                    : widget.color ?? (hover ? t.tint : null),
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(
                  color: focus ? t.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Opacity(
                opacity: widget.onPressed == null
                    ? 0.4
                    : pending
                    ? 0.65
                    : 1.0,
                child: IconTheme(
                  data: IconThemeData(
                    color: widget.selected ? t.accent : t.text,
                    size: TingyuTokens.iconSize,
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
