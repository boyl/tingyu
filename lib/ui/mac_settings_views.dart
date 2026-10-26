part of 'app.dart';

/// Desktop preferences stay inside one window; edits use shared controllers.
class MacSettingsPanel extends StatefulWidget {
  const MacSettingsPanel(this.p, {super.key});
  final LibraryController p;

  @override
  State<MacSettingsPanel> createState() => _MacSettingsPanelState();
}

class _MacSettingsPanelState extends State<MacSettingsPanel> {
  String section = 'appearance';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      key: const ValueKey('mac-settings'),
      width: TingyuTokens.macSettingsWidth,
      height: TingyuTokens.macSettingsHeight,
      child: Padding(
        padding: const EdgeInsets.all(TingyuTokens.space * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '设置',
                    style: TextStyle(
                      fontSize: TingyuTokens.macDetailTitle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                action(Icons.clear, '关闭设置', () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: TingyuTokens.space),
            Row(
              children: [
                for (final item in [
                  ('appearance', '外观'),
                  ('playback', '播放'),
                  ('storage', '存储'),
                ])
                  Expanded(
                    child: Pressable(
                      key: ValueKey('mac-settings-${item.$1}'),
                      label: item.$2,
                      selected: section == item.$1,
                      color: section == item.$1 ? t.tint : null,
                      radius: TingyuTokens.radius,
                      onPressed: () => setState(() => section = item.$1),
                      child: Center(
                        child: Text(
                          item.$2,
                          style: TextStyle(
                            color: section == item.$1 ? t.accentInk : t.muted,
                            fontWeight: section == item.$1
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: TingyuTokens.space),
            Expanded(
              child: SingleChildScrollView(
                key: PageStorageKey('mac-preferences-$section'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    switch (section) {
                      'appearance' => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [heading('主题'), themes(context)],
                      ),
                      'playback' => playback(context),
                      _ => StoragePanel(widget.p, desktop: true),
                    },
                  ],
                ),
              ),
            ),

            const SizedBox(height: TingyuTokens.space),
            Divider(height: 1, color: t.line),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'tingyu $tingyuVersion',
                    style: TextStyle(
                      color: t.muted,
                      fontSize: TingyuTokens.macCaption,
                    ),
                  ),
                ),
                labelButton('关于 tingyu', () => showAboutTingyu(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget themes(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: TingyuTokens.space * 2,
      runSpacing: TingyuTokens.space * 2,
      children: [
        for (final item in TingyuTokens.themes)
          SizedBox(
            width: (constraints.maxWidth - TingyuTokens.space * 6) / 4,
            child: ThemePreview(
              name: item.$2,
              tokens: item.$3,
              selected: widget.p.theme == item.$1,
              themeId: item.$1,
              onPressed: () =>
                  report(context, () => widget.p.setTheme(item.$1)),
            ),
          ),
      ],
    ),
  );

  Widget heading(String title) => Padding(
    padding: const EdgeInsets.only(bottom: TingyuTokens.space),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: TingyuTokens.macMenuTitle,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget playback(BuildContext context) {
    final p = widget.p, t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('音质偏好'),
        Row(
          children: [
            for (final item in [
              (false, '高音质', 'high'),
              (true, '标准', 'standard'),
            ])
              Expanded(
                child: Pressable(
                  key: ValueKey('mac-quality-${item.$3}'),
                  label: item.$2,
                  selected: p.standard == item.$1,
                  color: p.standard == item.$1 ? t.tint : null,
                  radius: TingyuTokens.radius,
                  onPressed: () =>
                      report(context, () => p.setStandard(item.$1)),
                  child: Center(
                    child: Text(
                      item.$2,
                      style: TextStyle(
                        color: p.standard == item.$1 ? t.accentInk : t.muted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: TingyuTokens.space),
        Divider(height: 1, color: t.line),
        const SizedBox(height: TingyuTokens.space),
        Row(
          children: [
            Expanded(child: heading('播放倍速')),
            Text(rateLabel(p.speed), style: TextStyle(color: t.accentInk)),
            action(
              Icons.refresh,
              '恢复正常倍速',
              p.speed == 1 ? null : () => report(context, () => p.setSpeed(1)),
            ),
          ],
        ),
        Wrap(
          spacing: TingyuTokens.space,
          runSpacing: TingyuTokens.space,
          children: [
            for (final speed in [.5, .75, 1.0, 1.25, 1.5, 2.0])
              Pressable(
                key: ValueKey('mac-speed-$speed'),
                label: rateLabel(speed),
                selected: p.speed == speed,
                color: p.speed == speed ? t.tint : null,
                radius: TingyuTokens.radius,
                onPressed: () => report(context, () => p.setSpeed(speed)),
                child: Text(
                  rateLabel(speed),
                  style: TextStyle(
                    color: p.speed == speed ? t.accentInk : t.muted,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: TingyuTokens.space),
        Slider(
          key: const ValueKey('mac-settings-speed-slider'),
          label: rateLabel(p.speed),
          value: p.speed.clamp(.5, 2),
          min: .5,
          max: 2,
          onChanged: (value) => report(context, () => p.setSpeed(value)),
        ),
      ],
    );
  }
}
