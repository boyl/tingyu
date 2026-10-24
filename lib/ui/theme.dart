import 'dart:async';
import 'dart:ui' as ui;
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
  // Brand accents need not double as small text ink.
  Color get accentInk => accent == brandPink ? const Color(0xffa93660) : accent;
  bool get isDark => background.computeLuminance() < .1;
  Color get glassFill => surface.withValues(alpha: isDark ? .20 : .16);
  Color get glassEdge => onArtwork.withValues(alpha: isDark ? .16 : .65);
  Color get glassHighlight => onArtwork.withValues(alpha: isDark ? .06 : .12);
  Color get glassShadow => playerShadow.withValues(alpha: isDark ? .24 : .07);
  Color get atmosphereCool => isDark ? tint : discoveryPalettes[0][1];
  Color get atmosphereWarm => isDark ? accent : brandPink;
  // Mac workspace geometry; Android tokens and layout stay independent.
  static const batchDialogWidth = 420.0, batchDialogTitle = 18.0;
  static const batchProgressHeight = 4.0, batchStatusHeight = 64.0;
  static const macSidebar = 220.0, macSidebarCompact = 184.0;
  static const macPadding = 32.0, macHeader = 64.0;
  static const macDock = 80.0, macDockRadius = 14.0;
  static const macPlayerArt = 36.0, macBrand = 18.0;
  static const macDetailCover = 320.0, macLyricWidth = 560.0;
  static const macAccountWidth = 680.0, macAccountQr = 176.0;
  static const macLoginWidth = 420.0, macSettingsWidth = 680.0;
  static const macSettingsHeight = 560.0, macStorageRing = 156.0;
  static const macAccountRadius = 16.0, macAccountAction = 224.0;
  static const macAccountHeight = 560.0,
      macLoginHeight = 380.0,
      macResultHeight = 360.0;
  static const macQueueWidth = 384.0, macQueueHeight = 440.0;
  static const macVolumeHeight = 184.0, macOptionsHeight = 460.0;
  static const storageRingInset = 20.0, storageRingStroke = 38.0;
  static const macSliderTrack = 2.0,
      macSliderThumb = 5.0,
      macSliderOverlay = 14.0;
  static const macCover = 360.0, macCard = 156.0;
  static const macMetadata = 12.0,
      macCaption = 12.0,
      macTrackTitle = 13.0,
      macMenuTitle = 17.0,
      macDetailTitle = 24.0;
  static const macTitle = 26.0, macSectionTitle = 18.0;
  static const macWide = 1120.0, macCompact = 900.0;
  static const pillRadius = 100.0;
  static const detailBlur = 18.0;
  static const detailRadius = 22.0;
  static const recordBase = Color(0xff18181e);
  static const recordGroove = Color(0xff45434a);
  static const recordGlint = Color(0xffddd8db);
  static const recordCoverRatio = .84;
  static const recordPeek = .79;
  static const swipeThreshold = 45.0;
  static const recordDiameterRatio = .74;
  static const toggleWidth = 36.0, toggleHeight = 22.0, toggleThumb = 16.0;
  static const lyricMin = 16.0, lyricMax = 32.0, lyricDefault = 24.0;
  static const lyricFontSizes = [20.0, 24.0, 28.0];
  static const brandPink = Color(0xfffb7299);
  Color get downloadBadgeFill => playerShadow.withValues(alpha: .52);
  Color get downloadBadgeEdge => onArtwork.withValues(alpha: .48);
  Color get selectionSurface => accent.withValues(alpha: isDark ? .14 : .10);
  static const marqueeSpeed = 28.0;
  static const marqueeGap = 40.0;
  static const segmentRadius = 8.0;
  static const timerStatusSize = 16.0;
  static const timerWaitingSize = 16.0;
  static const downloadBadgeSize = 20.0;
  static const downloadBadgeRadius = 7.0;
  static const downloadBadgeInset = 2.0;
  static const glassBlur = 5.0;
  static const space = 8.0,
      radius = 12.0,
      iconSize = 22.0,
      controlSize = 48.0,
      avatarSize = 40.0,
      profileAvatarSize = 56.0,
      themePreviewHeight = 112.0,
      coverSize = 144.0,
      artworkRadius = 4.0,
      sheetRadius = 24.0,
      iconStroke = 1.7,
      heroRatio = 1.65,
      shelfVisibleCards = 2.15,
      playControlSize = 68.0,
      collectionRadius = 16.0,
      downloadTabWidth = 116.0,
      downloadTabHeight = 56.0,
      tabIndicatorHeight = 3.0,
      playerRadius = 28.0,
      playingPeriod = Duration(milliseconds: 900),
      recordTurn = Duration(seconds: 8),
      scrollReturn = Duration(milliseconds: 320),
      pressDuration = Duration(milliseconds: 100),
      transition = Duration(milliseconds: 180);
  // Editorial category artwork has its own palette, like album cover imagery.
  static const onArtwork = Color(0xffffffff);
  static const vinyl = Color(0xff171513);
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
    background: Color(0xffffffff),
    surface: Color(0xffffffff),
    sidebar: Color(0xfff5f5f7),
    text: Color(0xff19191b),
    muted: Color(0xff68686e),
    accent: brandPink,
    onAccent: Color(0xff361522),
    tint: Color(0xfff2f1f3),
    line: Color(0xffe7e7eb),
    danger: Color(0xffad334c),
    playerSurface: Color(0xffffffff),
    playerBorder: Color(0xffe7e7eb),
    onPlayer: Color(0xff19191b),
    playerMuted: Color(0xff515157),
    playerButton: brandPink,
    onPlayerButton: Color(0xff361522),
    playerTrack: Color(0xffdcd9de),
    playerShadow: Color(0x122a2230),
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

/// Captured by dialogs opened from the Mac workspace; other platforms keep their feedback.
class PressableStyle extends InheritedTheme {
  const PressableStyle({
    super.key,
    required this.desktop,
    required super.child,
  });
  final bool desktop;
  static bool isDesktop(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PressableStyle>()?.desktop ??
      false;
  @override
  bool updateShouldNotify(PressableStyle oldWidget) =>
      oldWidget.desktop != desktop;
  @override
  Widget wrap(BuildContext context, Widget child) =>
      PressableStyle(desktop: desktop, child: child);
}

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onPressed,
    this.label,
    this.selected = false,
    this.selectionFill = true,
    this.dimWhenDisabled = true,
    this.padding = const EdgeInsets.all(12),
    this.color,
    this.minSize = 48,
    this.radius = TingyuTokens.radius,
  });
  final Widget child;
  final FutureOr<void> Function()? onPressed;
  final String? label;
  final bool selected, selectionFill, dimWhenDisabled;
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
    final desktop = PressableStyle.isDesktop(context);
    Widget surface({
      required BoxConstraints constraints,
      required EdgeInsets padding,
      required BoxDecoration decoration,
      required Widget child,
    }) => desktop
        ? AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : TingyuTokens.pressDuration,
            constraints: constraints,
            padding: padding,
            decoration: decoration,
            child: child,
          )
        : Container(
            constraints: constraints,
            padding: padding,
            decoration: decoration,
            child: child,
          );
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
            scale:
                (down && !desktop && !MediaQuery.disableAnimationsOf(context))
                ? 0.99
                : 1.0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : TingyuTokens.pressDuration,
            child: surface(
              constraints: BoxConstraints(
                minWidth: widget.minSize,
                minHeight: widget.minSize,
              ),
              padding: widget.padding,
              decoration: BoxDecoration(
                color: desktop && widget.onPressed != null && (down || hover)
                    ? Color.alphaBlend(
                        t.text.withValues(alpha: down ? .10 : .05),
                        widget.color ??
                            (widget.selected && widget.selectionFill
                                ? t.tint
                                : t.surface),
                      )
                    : widget.selected && widget.selectionFill
                    ? t.tint
                    : widget.color ?? (hover ? t.tint : null),
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(
                  color: focus ? t.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Opacity(
                opacity: widget.onPressed == null && widget.dimWhenDisabled
                    ? 0.4
                    : pending
                    ? 0.65
                    : 1.0,
                child: IconTheme(
                  data: IconThemeData(
                    color: widget.selected ? t.accent : t.text,
                    size: TingyuTokens.iconSize,
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: widget.selected ? t.accentInk : t.text,
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin optical layer: the scrolling scene stays behind the dock.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = TingyuTokens.playerRadius,
    this.blur = TingyuTokens.glassBlur,
    this.opacity,
  });
  final Widget child;
  final double radius, blur;
  final double? opacity;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final border = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: border,
        boxShadow: [
          BoxShadow(
            color: t.glassShadow,
            blurRadius: TingyuTokens.space * 2,
            offset: const Offset(0, TingyuTokens.space / 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: border,
        child: BackdropFilter.grouped(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: border,
              color: opacity == null
                  ? t.glassFill
                  : t.surface.withValues(alpha: opacity!),
              gradient: opacity == null
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [t.glassHighlight, t.glassFill],
                    )
                  : null,
              border: Border.all(color: t.glassEdge),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// One continuous atmosphere behind mobile content and glass groups.
class DetailAtmosphere extends StatelessWidget {
  const DetailAtmosphere({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(color: t.background),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-1, -.6),
                  radius: 1.5,
                  colors: [
                    t.atmosphereCool.withValues(alpha: .28),
                    t.background.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1, .6),
                  radius: 1.4,
                  colors: [
                    t.atmosphereWarm.withValues(alpha: .20),
                    t.background.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Branded switch: a stable touch target around a small track, with shared semantics.
class TingyuToggle extends StatelessWidget {
  const TingyuToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    child: Pressable(
      label: label,
      selected: value,
      selectionFill: false,
      padding: EdgeInsets.zero,
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : TingyuTokens.pressDuration,
          width: TingyuTokens.toggleWidth,
          height: TingyuTokens.toggleHeight,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? context.tokens.accent : context.tokens.line,
            borderRadius: BorderRadius.circular(TingyuTokens.pillRadius),
          ),
          child: AnimatedAlign(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : TingyuTokens.pressDuration,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: TingyuTokens.toggleThumb,
              height: TingyuTokens.toggleThumb,
              decoration: const BoxDecoration(
                color: TingyuTokens.onArtwork,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class TingyuSegmented extends StatelessWidget {
  const TingyuSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: context.tokens.tint,
      borderRadius: BorderRadius.circular(TingyuTokens.collectionRadius),
    ),
    child: Row(
      children: [
        for (final e in labels.indexed)
          Expanded(
            child: Pressable(
              key: ValueKey('segment-${e.$2}'),
              label: e.$2,
              selected: index == e.$1,
              selectionFill: false,
              color: index == e.$1
                  ? context.tokens.surface
                  : Colors.transparent,
              onPressed: () => onChanged(e.$1),
              child: Center(
                child: Text(
                  e.$2,
                  style: TextStyle(
                    color: index == e.$1
                        ? context.tokens.accentInk
                        : context.tokens.text,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
