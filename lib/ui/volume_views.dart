part of 'app.dart';

Future<void> showPlayerVolume(BuildContext context, LibraryController p) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TingyuTokens.detailRadius),
        ),
      ),
      builder: (_) => PlayerVolumePanel(p),
    );

class PlayerVolumePanel extends StatelessWidget {
  const PlayerVolumePanel(this.p, {super.key});
  final LibraryController p;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: p,
    builder: (context, _) {
      final volume = p.playback.player.volume.clamp(0.0, 1.0);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TingyuTokens.space * 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '播放音量',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${(volume * 100).round()}%',
                    key: const ValueKey('player-volume-percent'),
                    style: TextStyle(color: context.tokens.accentInk),
                  ),
                  action(
                    Icons.refresh,
                    '恢复正常音量',
                    () => p.playback.player.setVolume(1),
                  ),
                ],
              ),
              Row(
                children: [
                  const TingyuIcon(Icons.volume_off),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('player-volume-slider'),
                      value: volume,
                      semanticFormatterCallback: (value) =>
                          '${(value * 100).round()}%',
                      onChanged: (value) => report(
                        context,
                        () => p.playback.player.setVolume(value),
                      ),
                    ),
                  ),
                  const TingyuIcon(Icons.volume_up),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
