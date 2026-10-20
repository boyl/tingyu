part of 'app.dart';

String rateLabel(double speed) =>
    '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}×';
String timerLabel(LibraryController p) {
  if (p.waitingForTrack) return '本首结束后暂停';
  if (!p.sleepTimer.active) return '';
  final seconds = p.sleepTimer.remaining.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// The route owns the draft; only a completed user dismissal applies it.
class SleepTimerDraft {
  SleepTimerDraft(LibraryController p)
    : minutes = p.sleepTimer.active
          ? (p.sleepTimer.remaining.inSeconds / 60).ceil().clamp(1, 180)
          : null,
      finish = p.sleepTimer.finishTrack;
  int? minutes;
  bool finish;
  bool changed = false;
}

Future<void> showPlaybackSettings(
  BuildContext context,
  LibraryController p, {
  required bool timer,
}) async {
  final draft = SleepTimerDraft(p);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.tokens.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TingyuTokens.detailRadius),
      ),
    ),
    builder: (ctx) => PlaybackSettingsPanel(p, timer: timer, draft: draft),
  );
  final lifecycle = WidgetsBinding.instance.lifecycleState;
  if (timer &&
      draft.changed &&
      context.mounted &&
      (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
    p.setSleepTimer(
      draft.minutes == null ? null : Duration(minutes: draft.minutes!),
      finishTrack: draft.finish,
    );
  }
}

class PlaybackSettingsPanel extends StatefulWidget {
  const PlaybackSettingsPanel(
    this.p, {
    super.key,
    required this.timer,
    this.draft,
  });
  final LibraryController p;
  final bool timer;
  final SleepTimerDraft? draft;
  @override
  State<PlaybackSettingsPanel> createState() => _PlaybackSettingsPanelState();
}

class _PlaybackSettingsPanelState extends State<PlaybackSettingsPanel> {
  late final SleepTimerDraft draft = widget.draft ?? SleepTimerDraft(widget.p);
  int get minutes => draft.minutes ?? 30;
  bool get finish => draft.finish;
  late final FixedExtentScrollController hoursWheel =
      FixedExtentScrollController(initialItem: minutes ~/ 60);
  late final FixedExtentScrollController minutesWheel =
      FixedExtentScrollController(initialItem: minutes % 60);
  bool movingWheels = false;
  bool customDuration = false;
  late bool customSelection =
      draft.minutes != null && ![15, 30, 45, 60].contains(minutes);
  String get customLabel {
    if (draft.minutes == null || !(customSelection || customDuration)) {
      return '未选择';
    }
    final h = minutes ~/ 60, m = minutes % 60;
    return h == 0
        ? '$m 分钟'
        : m == 0
        ? '$h 小时'
        : '$h 小时 $m 分钟';
  }

  @override
  void dispose() {
    hoursWheel.dispose();
    minutesWheel.dispose();
    super.dispose();
  }

  void start(int value, {bool fromWheel = false, bool syncWheels = true}) {
    draft.minutes = value;
    draft.changed = true;
    customSelection = fromWheel;
    if (!syncWheels) {
      setState(() {});
      return;
    }
    movingWheels = true;
    if (hoursWheel.hasClients && hoursWheel.selectedItem != minutes ~/ 60) {
      hoursWheel.jumpToItem(minutes ~/ 60);
    }
    if (minutesWheel.hasClients && minutesWheel.selectedItem != minutes % 60) {
      minutesWheel.jumpToItem(minutes % 60);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) movingWheels = false;
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.p,
    builder: (context, _) {
      final p = widget.p, t = context.tokens;
      final hasTimer = draft.changed
          ? draft.minutes != null
          : p.sleepTimer.active || p.waitingForTrack;
      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            TingyuTokens.space * 3,
            TingyuTokens.space * 2,
            TingyuTokens.space * 3,
            MediaQuery.viewInsetsOf(context).bottom + TingyuTokens.space * 3,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.timer)
                Center(
                  child: Container(
                    width: TingyuTokens.space * 4,
                    height: TingyuTokens.space / 2,
                    margin: const EdgeInsets.only(
                      bottom: TingyuTokens.space * 2,
                    ),
                    decoration: BoxDecoration(
                      color: t.line,
                      borderRadius: BorderRadius.circular(TingyuTokens.radius),
                    ),
                  ),
                ),
              Row(
                children: [
                  if (!widget.timer)
                    TingyuIcon(
                      widget.timer ? Icons.schedule : Icons.speed,
                      color: t.muted,
                    ),
                  if (!widget.timer) const SizedBox(width: TingyuTokens.space),
                  Expanded(
                    child: Text(
                      widget.timer ? '定时关闭' : '播放倍速',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!widget.timer)
                    action(
                      Icons.keyboard_arrow_down,
                      '收起设置',
                      () => Navigator.pop(context),
                    ),
                ],
              ),
              const SizedBox(height: TingyuTokens.space * 2),
              if (!widget.timer) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rateLabel(p.speed),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    action(Icons.refresh, '恢复正常倍速', () => p.setSpeed(1)),
                  ],
                ),
                Row(
                  children: [
                    for (final value in [.5, .75, 1.0, 1.25, 1.5, 2.0])
                      Expanded(
                        child: Pressable(
                          key: ValueKey('speed-$value'),
                          label: rateLabel(value),
                          selected: p.speed == value,
                          selectionFill: false,
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              report(context, () => p.setSpeed(value)),
                          child: Center(
                            child: Text(
                              rateLabel(value),
                              style: TextStyle(
                                fontSize: 12,
                                color: p.speed == value ? t.accentInk : t.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: TingyuTokens.space * 2),
                Row(
                  children: [
                    action(
                      Icons.remove,
                      '减慢0.05倍',
                      p.speed > .5
                          ? () => p.setSpeed((p.speed - .05).clamp(.5, 2))
                          : null,
                    ),
                    Expanded(
                      child: Slider(
                        value: p.speed,
                        min: .5,
                        max: 2,
                        onChanged: (value) =>
                            report(context, () => p.setSpeed(value)),
                      ),
                    ),
                    action(
                      Icons.add,
                      '加快0.05倍',
                      p.speed < 2
                          ? () => p.setSpeed((p.speed + .05).clamp(.5, 2))
                          : null,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TingyuTokens.space * 6,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0.5×',
                        style: TextStyle(color: t.muted, fontSize: 11),
                      ),
                      Text(
                        '2×',
                        style: TextStyle(color: t.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final running = !draft.changed && p.sleepTimer.active;
                    final status = !hasTimer
                        ? '定时已关闭'
                        : !draft.changed && p.waitingForTrack
                        ? '本首结束后暂停'
                        : running
                        ? timerLabel(p)
                        : '$minutes 分钟后';
                    final note = !hasTimer
                        ? ''
                        : !draft.changed && p.waitingForTrack
                        ? ''
                        : running
                        ? '剩余时间'
                        : '';
                    final stacked =
                        constraints.maxWidth < 300 ||
                        MediaQuery.textScalerOf(
                              context,
                            ).scale(TingyuTokens.timerStatusSize) >
                            20;
                    final statusRow = Row(
                      children: [
                        TingyuIcon(
                          Icons.schedule,
                          color: !hasTimer ? t.muted : t.accentInk,
                        ),
                        const SizedBox(width: TingyuTokens.space * 1.5),
                        Expanded(
                          child: Text(
                            status,
                            key: const ValueKey('timer-status'),
                            style: TextStyle(
                              fontSize: !draft.changed && p.waitingForTrack
                                  ? TingyuTokens.timerWaitingSize
                                  : TingyuTokens.timerStatusSize,
                              color: !hasTimer ? t.muted : t.text,
                            ),
                          ),
                        ),
                        if (!stacked && note.isNotEmpty)
                          Text(
                            note,
                            style: TextStyle(fontSize: 12, color: t.muted),
                          ),
                        SizedBox(
                          width: TingyuTokens.controlSize,
                          height: TingyuTokens.controlSize,
                          child: hasTimer
                              ? Tooltip(
                                  message: '关闭定时',
                                  child: Pressable(
                                    key: const ValueKey('timer-off'),
                                    label: '关闭定时',
                                    selectionFill: false,
                                    padding: EdgeInsets.zero,
                                    onPressed: () => setState(() {
                                      draft.minutes = null;
                                      draft.changed = true;
                                      customSelection = false;
                                    }),
                                    child: const Center(
                                      child: TingyuIcon(
                                        Icons.timer_off_outlined,
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    );
                    return SizedBox(
                      height: stacked
                          ? TingyuTokens.controlSize * 1.5
                          : TingyuTokens.controlSize,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          statusRow,
                          if (stacked && note.isNotEmpty)
                            Text(
                              note,
                              style: TextStyle(fontSize: 12, color: t.muted),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: TingyuTokens.space * 2),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        constraints.maxWidth < 300 ||
                            MediaQuery.textScalerOf(context).scale(14) > 18
                        ? 2
                        : 4;
                    return Wrap(
                      spacing: TingyuTokens.space,
                      runSpacing: TingyuTokens.space,
                      children: [
                        for (final value in [15, 30, 45, 60])
                          SizedBox(
                            width:
                                (constraints.maxWidth -
                                    TingyuTokens.space * (columns - 1)) /
                                columns,
                            child: Pressable(
                              key: ValueKey('timer-$value'),
                              label: '$value分钟',
                              selected: hasTimer && draft.minutes == value,
                              selectionFill: false,
                              color: hasTimer && draft.minutes == value
                                  ? t.selectionSurface
                                  : t.sidebar,
                              radius: TingyuTokens.radius,
                              padding: const EdgeInsets.symmetric(
                                horizontal: TingyuTokens.space / 2,
                              ),
                              onPressed: () => start(value),
                              child: Center(
                                child: Text(
                                  '$value 分钟',
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: hasTimer && draft.minutes == value
                                        ? t.accentInk
                                        : t.text,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: TingyuTokens.space * 2),
                Pressable(
                  key: const ValueKey('timer-custom'),
                  label: '自定义时长',
                  selectionFill: false,
                  onPressed: () =>
                      setState(() => customDuration = !customDuration),
                  child: Row(
                    children: [
                      const Expanded(child: Text('自定义时长')),
                      Text(customLabel, style: TextStyle(color: t.muted)),
                      const SizedBox(width: TingyuTokens.space),
                      const TingyuIcon(Icons.chevron_right),
                    ],
                  ),
                ),
                if (customDuration)
                  SizedBox(
                    height: TingyuTokens.space * 18,
                    child: Row(
                      children: [
                        Expanded(
                          child: ListWheelScrollView.useDelegate(
                            key: const ValueKey('timer-hours'),
                            controller: hoursWheel,
                            itemExtent: 48,
                            diameterRatio: 1.4,
                            overAndUnderCenterOpacity: .25,
                            physics: const FixedExtentScrollPhysics(),
                            onSelectedItemChanged: (h) {
                              if (movingWheels) return;
                              final total = h * 60 + minutes % 60;
                              start(
                                total.clamp(1, 180),
                                fromWheel: true,
                                syncWheels: total < 1 || total > 180,
                              );
                            },
                            childDelegate: ListWheelChildListDelegate(
                              children: [
                                for (var h = 0; h <= 3; h++)
                                  Center(
                                    child: Text(
                                      '$h 小时',
                                      style: const TextStyle(fontSize: 23),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListWheelScrollView.useDelegate(
                            key: const ValueKey('timer-minutes'),
                            controller: minutesWheel,
                            itemExtent: 48,
                            diameterRatio: 1.4,
                            overAndUnderCenterOpacity: .25,
                            physics: const FixedExtentScrollPhysics(),
                            onSelectedItemChanged: (m) {
                              if (movingWheels) return;
                              final total = minutes ~/ 60 * 60 + m;
                              start(
                                total.clamp(1, 180),
                                fromWheel: true,
                                syncWheels: total < 1 || total > 180,
                              );
                            },
                            childDelegate: ListWheelChildListDelegate(
                              children: [
                                for (var m = 0; m < 60; m++)
                                  Center(
                                    child: Text(
                                      '$m 分钟',
                                      style: const TextStyle(fontSize: 23),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: TingyuTokens.space,
                  ),
                  child: Text(
                    '结束方式',
                    style: TextStyle(color: t.muted, fontSize: 13),
                  ),
                ),
                Container(
                  height: TingyuTokens.controlSize,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: t.sidebar,
                    borderRadius: BorderRadius.circular(
                      TingyuTokens.segmentRadius,
                    ),
                  ),
                  child: Row(
                    children: [
                      for (final value in [false, true])
                        Expanded(
                          child: Pressable(
                            key: ValueKey('timer-finish-$value'),
                            padding: EdgeInsets.zero,
                            radius: TingyuTokens.segmentRadius,
                            selected: finish == value,
                            selectionFill: false,
                            color: finish == value
                                ? t.selectionSurface
                                : Colors.transparent,
                            label: value ? '播完本首' : '到时暂停',
                            onPressed: () {
                              setState(() {
                                draft.finish = value;
                                if (draft.minutes != null) draft.changed = true;
                              });
                            },
                            child: Center(
                              child: Text(
                                value ? '播完本首' : '到时暂停',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: finish == value ? t.accentInk : t.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class LyricVisibilityControl extends StatelessWidget {
  const LyricVisibilityControl(this.p, {super.key});
  final LibraryController p;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('歌词', style: TextStyle(color: context.tokens.muted, fontSize: 12)),
      TingyuToggle(
        key: const ValueKey('player-lyrics-toggle'),
        value: p.showPlayerLyrics,
        label: '显示所有歌曲的歌词',
        onChanged: (v) => report(context, () => p.setPlayerLyrics(v)),
      ),
    ],
  );
}

class PlaybackTool extends StatelessWidget {
  const PlaybackTool(this.p, {super.key, required this.timer});
  final LibraryController p;
  final bool timer;
  @override
  Widget build(BuildContext context) => Pressable(
    key: ValueKey(timer ? 'player-sleep-timer' : 'player-speed'),
    label: timer ? '定时关闭 ${timerLabel(p)}' : '播放倍速 ${rateLabel(p.speed)}',
    selectionFill: false,
    onPressed: () => showPlaybackSettings(context, p, timer: timer),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TingyuIcon(
          timer ? Icons.schedule : Icons.speed,
          size: 20,
          color: context.tokens.muted,
        ),
        if (!timer || timerLabel(p).isNotEmpty) ...[
          const SizedBox(width: TingyuTokens.space / 2),
          Text(
            timer ? timerLabel(p) : rateLabel(p.speed),
            style: TextStyle(color: context.tokens.muted, fontSize: 12),
          ),
        ],
      ],
    ),
  );
}
