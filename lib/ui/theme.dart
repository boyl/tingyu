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
      danger;
  static const space = 8.0,
      radius = 12.0,
      pressDuration = Duration(milliseconds: 100),
      transition = Duration(milliseconds: 180);
  static const light = TingyuTokens(
    background: Color(0xfff7f6f2),
    surface: Color(0xfffdfcf9),
    sidebar: Color(0xfff0efeb),
    text: Color(0xff24272b),
    muted: Color(0xff62676c),
    accent: Color(0xff4c678e),
    onAccent: Color(0xffffffff),
    tint: Color(0xffe4e9ef),
    line: Color(0xffdedfdb),
    danger: Color(0xffb53b42),
  );
  static const dark = TingyuTokens(
    background: Color(0xff17191c),
    surface: Color(0xff202327),
    sidebar: Color(0xff1c1f23),
    text: Color(0xffeef0f2),
    muted: Color(0xffacb2bc),
    accent: Color(0xff9ab8e6),
    onAccent: Color(0xff152238),
    tint: Color(0xff2c3a4e),
    line: Color(0xff383d45),
    danger: Color(0xffff9ba1),
  );
  static const pink = TingyuTokens(
    background: Color(0xfffafbfd),
    surface: Color(0xffffffff),
    sidebar: Color(0xfff3f5f8),
    text: Color(0xff282c35),
    muted: Color(0xff646b78),
    accent: Color(0xffb93e65),
    onAccent: Color(0xffffffff),
    tint: Color(0xfff5e6ec),
    line: Color(0xffe0e3e9),
    danger: Color(0xffb13b40),
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
    this.padding = const EdgeInsets.all(12),
    this.color,
    this.minSize = 48,
    this.radius = TingyuTokens.radius,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final String? label;
  final bool selected;
  final EdgeInsets padding;
  final Color? color;
  final double minSize;
  final double radius;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false, hover = false, focus = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      selected: widget.selected,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: widget.onPressed != null,
        onShowFocusHighlight: (v) => setState(() => focus = v),
        onShowHoverHighlight: (v) => setState(() => hover = v),
        mouseCursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          onTapDown: widget.onPressed == null
              ? null
              : (_) => setState(() => down = true),
          onTapCancel: () => setState(() => down = false),
          onTapUp: (_) => setState(() => down = false),
          child: AnimatedScale(
            scale: (down && !MediaQuery.disableAnimationsOf(context))
                ? 0.99
                : 1.0,
            duration: TingyuTokens.pressDuration,
            child: AnimatedContainer(
              duration: TingyuTokens.transition,
              constraints: BoxConstraints(
                minWidth: widget.minSize,
                minHeight: widget.minSize,
              ),
              padding: widget.padding,
              decoration: BoxDecoration(
                color: widget.selected
                    ? t.tint
                    : widget.color ?? (hover ? t.tint : null),
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(
                  color: focus ? t.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Opacity(
                opacity: widget.onPressed == null ? 0.4 : 1.0,
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
