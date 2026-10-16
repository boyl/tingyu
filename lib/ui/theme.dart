import 'dart:async';
import 'package:flutter/material.dart';

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
      playerRadius = 20.0,
      pressDuration = Duration(milliseconds: 100),
      transition = Duration(milliseconds: 180);
  static const light = TingyuTokens(
    background: Color(0xffeeeae4),
    surface: Color(0xfffcfaf7),
    sidebar: Color(0xfff0efeb),
    text: Color(0xff272c30),
    muted: Color(0xff62676c),
    accent: Color(0xff4a687d),
    onAccent: Color(0xffffffff),
    tint: Color(0xffe5ebed),
    line: Color(0xffdedfdb),
    danger: Color(0xffb53b42),
    playerSurface: Color(0xff484640),
    playerBorder: Color(0xff57544c),
    onPlayer: Color(0xfffaf5e9),
    playerMuted: Color(0xffc8c1b3),
    playerButton: Color(0xfff5edda),
    onPlayerButton: Color(0xff484640),
    playerTrack: Color(0xff787267),
    playerShadow: Color(0x12000000),
  );
  static const dark = TingyuTokens(
    background: Color(0xff14181d),
    surface: Color(0xff20262e),
    sidebar: Color(0xff1c1f23),
    text: Color(0xffeef0f2),
    muted: Color(0xffacb2bc),
    accent: Color(0xffb1c8e8),
    onAccent: Color(0xff152238),
    tint: Color(0xff2b3743),
    line: Color(0xff383d45),
    danger: Color(0xffff9ba1),
    playerSurface: Color(0xff344251),
    playerBorder: Color(0xff495a6b),
    onPlayer: Color(0xfff5f7fa),
    playerMuted: Color(0xffbcc8d4),
    playerButton: Color(0xffb1c8e8),
    onPlayerButton: Color(0xff182638),
    playerTrack: Color(0xff596b7e),
    playerShadow: Color(0x2d000000),
  );
  static const pink = TingyuTokens(
    background: Color(0xffedf0f5),
    surface: Color(0xffffffff),
    sidebar: Color(0xfff3f5f8),
    text: Color(0xff282c35),
    muted: Color(0xff646b78),
    accent: Color(0xffa94368),
    onAccent: Color(0xffffffff),
    tint: Color(0xfff6eaf0),
    line: Color(0xffe0e3e9),
    danger: Color(0xffb13b40),
    playerSurface: Color(0xfff0dfe8),
    playerBorder: Color(0xffe2ccd8),
    onPlayer: Color(0xff4d3041),
    playerMuted: Color(0xff765b6c),
    playerButton: Color(0xffa94368),
    onPlayerButton: Color(0xffffffff),
    playerTrack: Color(0xffd7bdcb),
    playerShadow: Color(0x1c000000),
  );
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
  final t = name == 'b'
      ? TingyuTokens.dark
      : name == 'c'
      ? TingyuTokens.pink
      : TingyuTokens.light;
  return ThemeData(
    brightness: name == 'b' ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: t.background,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: t.accent,
          brightness: name == 'b' ? Brightness.dark : Brightness.light,
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
        fontSize: 26,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: t.text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accent,
      thumbColor: t.accent,
      inactiveTrackColor: t.line,
      trackHeight: 3,
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
    setState(() => pending = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => pending = false);
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
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : TingyuTokens.transition,
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
                    size: 20,
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
