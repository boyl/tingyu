part of 'app.dart';

String rateLabel(double speed) =>
    '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}×';
String timerLabel(LibraryController p) {
  if (p.waitingForTrack) return '本首结束后暂停';
  if (!p.sleepTimer.active) return '';
  final seconds = p.sleepTimer.remaining.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

Future<void> showPlaybackSettings(
  BuildContext context,
  LibraryController p, {
  required bool timer,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: context.tokens.surface,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(TingyuTokens.detailRadius),
    ),
  ),
  builder: (ctx) => PlaybackSettingsPanel(p, timer: timer),
);

class PlaybackSettingsPanel extends StatefulWidget {
  const PlaybackSettingsPanel(this.p, {super.key, required this.timer});
  final LibraryController p;
  final bool timer;
  @override
  State<PlaybackSettingsPanel> createState() => _PlaybackSettingsPanelState();
}

class _PlaybackSettingsPanelState extends State<PlaybackSettingsPanel> {
  late int minutes = widget.p.sleepTimer.active
      ? (widget.p.sleepTimer.remaining.inSeconds / 60).ceil().clamp(1, 180)
      : 30;
  late bool finish = widget.p.sleepTimer.finishTrack;
  late final FixedExtentScrollController hoursWheel =
      FixedExtentScrollController(initialItem: minutes ~/ 60);
  late final FixedExtentScrollController minutesWheel =
      FixedExtentScrollController(initialItem: minutes % 60);
  bool movingWheels = false;
  @override
  void dispose() {
    hoursWheel.dispose();
    minutesWheel.dispose();
    super.dispose();
  }

  void start(int value) {
    minutes = value;
    widget.p.setSleepTimer(Duration(minutes: value), finishTrack: finish);
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
              Row(
                children: [
                  TingyuIcon(
                    widget.timer ? Icons.schedule : Icons.speed,
                    color: t.muted,
                  ),
                  const SizedBox(width: TingyuTokens.space),
                  Expanded(
                    child: Text(
                      widget.timer ? '定时关闭' : '播放倍速',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
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
                Row(
                  children: [
                    Expanded(
                      child: Pressable(
                        key: const ValueKey('timer-off'),
                        label: '关闭定时',
                        selected: !p.sleepTimer.active && !p.waitingForTrack,
                        selectionFill: false,
                        padding: EdgeInsets.zero,
                        onPressed: () => p.setSleepTimer(null),
                        child: const Center(
                          child: Text('关闭', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                    for (final value in [15, 30, 45, 60])
                      Expanded(
                        child: Pressable(
                          key: ValueKey('timer-$value'),
                          label: '$value分钟',
                          selected: p.sleepTimer.active && minutes == value,
                          selectionFill: false,
                          padding: EdgeInsets.zero,
                          onPressed: () => start(value),
                          child: Center(
                            child: Text(
                              '$value 分钟',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: TingyuTokens.space * 2),
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
                            start(total.clamp(1, 180));
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
                            start(total.clamp(1, 180));
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
                Row(
                  children: [
                    for (final value in [false, true])
                      Expanded(
                        child: Pressable(
                          key: ValueKey('timer-finish-$value'),
                          selected: finish == value,
                          label: value ? '播完本首' : '到时暂停',
                          onPressed: () {
                            setState(() => finish = value);
                            p.sleepTimer.finishTrack = value;
                            if (p.sleepTimer.active) start(minutes);
                          },
                          child: Text(value ? '播完本首' : '到时暂停'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: TingyuTokens.space * 2),
                Text(
                  p.waitingForTrack
                      ? '本首结束后暂停'
                      : p.sleepTimer.active
                      ? '${timerLabel(p)} 后暂停'
                      : '未开启',
                  style: TextStyle(color: t.muted, fontSize: 12),
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
