part of 'app.dart';

class LyricsPreferencesPage extends StatefulWidget {
  const LyricsPreferencesPage(
    this.p,
    this.track, {
    super.key,
    required this.section,
  });
  final LibraryController p;
  final Track track;
  final String section;
  @override
  State<LyricsPreferencesPage> createState() => _LyricsPreferencesState();
}

class _LyricsPreferencesState extends State<LyricsPreferencesPage> {
  late final query = TextEditingController(
    text: '${widget.track.title} ${widget.track.artist}',
  );
  late final original = TextEditingController(text: widget.p.lyricText);
  late final translation = TextEditingController(
    text: widget.p.lyricTranslation,
  );
  late final romaji = TextEditingController(text: widget.p.lyricRomaji);
  late int offset = widget.p.lyricOffset;
  String source = 'auto';
  int tab = 0, revision = 0;
  bool busy = false, allowExit = false;
  String? error;
  List<Map<String, dynamic>> candidates = [];
  CancelToken? token;
  bool get editable => widget.section == 'edit' || widget.section == 'offset';
  bool get dirty =>
      original.text != widget.p.lyricText ||
      translation.text != widget.p.lyricTranslation ||
      romaji.text != widget.p.lyricRomaji ||
      offset != widget.p.lyricOffset;
  @override
  void dispose() {
    token?.cancel();
    query.dispose();
    original.dispose();
    translation.dispose();
    romaji.dispose();
    super.dispose();
  }

  Future<void> back() async {
    if (editable && dirty && !await confirm(context, '放弃尚未保存的歌词修改？')) return;
    if (mounted) {
      setState(() => allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> search() async {
    final version = ++revision;
    final searchedQuery = query.text.trim();
    token?.cancel();
    final cancel = token = CancelToken();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final found = source == 'auto'
          ? await widget.p.lyricsClient.search(
              query.text.trim(),
              cancelToken: cancel,
            )
          : await widget.p.lyricsClient.searchSources(
              query.text.trim(),
              source: source,
              cancelToken: cancel,
            );
      if (mounted &&
          version == revision &&
          query.text.trim() == searchedQuery) {
        setState(() {
          candidates = found;
          error = found.isEmpty ? '未找到歌词，请调整歌名或歌手' : null;
        });
      }
    } on AppFailure catch (e) {
      if (mounted && version == revision) setState(() => error = e.message);
    } on DioException catch (e) {
      if (mounted && version == revision && !CancelToken.isCancel(e)) {
        setState(() => error = '搜索失败，请重试');
      }
    } finally {
      if (mounted && version == revision) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p, t = context.tokens;
    final title = switch (widget.section) {
      'display' => '显示与排版',
      'match' => '匹配歌词',
      'edit' => '编辑歌词',
      _ => '时间偏移',
    };
    return PopScope(
      canPop: allowExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(back());
      },
      child: AnimatedBuilder(
        animation: p,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            centerTitle: true,
            backgroundColor: t.background,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleTextStyle: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
            leading: action(Icons.arrow_back, '返回', back),
            title: Text(title),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.section == 'display') ...[
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: t.tint,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        p.lines
                                .where((l) => l.text.trim().isNotEmpty)
                                .firstOrNull
                                ?.text ??
                            '歌词显示预览',
                        textAlign: p.lyricCentered
                            ? TextAlign.center
                            : TextAlign.start,
                        style: TextStyle(
                          fontSize: p.lyricFontSize,
                          height: 1.8,
                          color: t.accentInk,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('歌词内容', style: TextStyle(fontSize: 12)),
                    for (final item in [
                      ('逐字高亮', p.showLyricWords),
                      ('翻译', p.showLyricTranslation),
                      ('罗马音', p.showLyricRomaji),
                    ])
                      Row(
                        children: [
                          Expanded(child: Text(item.$1)),
                          TingyuToggle(
                            label: item.$1,
                            value: item.$2,
                            onChanged: (value) => p.setLyricDisplay(
                              words: item.$1 == '逐字高亮' ? value : null,
                              translation: item.$1 == '翻译' ? value : null,
                              romaji: item.$1 == '罗马音' ? value : null,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: Text('文字大小')),
                        labelButton(
                          '恢复默认',
                          () => p.setLyricDisplay(
                            fontSize: TingyuTokens.lyricDefault,
                          ),
                          icon: Icons.refresh,
                        ),
                      ],
                    ),
                    Text(
                      '${p.lyricFontSize.round()} px',
                      style: const TextStyle(fontSize: 24),
                    ),
                    Slider(
                      key: const ValueKey('lyric-font-size'),
                      min: TingyuTokens.lyricMin,
                      max: TingyuTokens.lyricMax,
                      value: p.lyricFontSize,
                      onChanged: (v) => p.setLyricDisplay(fontSize: v),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${TingyuTokens.lyricMin.round()}'),
                        Text('${TingyuTokens.lyricMax.round()}'),
                      ],
                    ),
                    const Text('排版'),
                    Row(
                      children: [
                        for (final centered in [false, true])
                          Expanded(
                            child: labelButton(
                              centered ? '居中' : '左对齐',
                              () => p.setLyricCentered(centered),
                              selected: p.lyricCentered == centered,
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (widget.section == 'match') ...[
                    TextField(
                      controller: query,
                      decoration: InputDecoration(
                        labelText: '歌曲 / 歌手',
                        suffixIcon: action(
                          Icons.search,
                          '搜索歌词',
                          busy ? null : search,
                        ),
                      ),
                      onChanged: (_) {
                        token?.cancel();
                        revision++;
                        setState(() {
                          busy = false;
                          candidates = [];
                          error = null;
                        });
                      },
                      onSubmitted: (_) => search(),
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final e in LyricsClient.sources.entries)
                            labelButton(
                              e.value,
                              busy
                                  ? null
                                  : () => setState(() => source = e.key),
                              selected: source == e.key,
                            ),
                        ],
                      ),
                    ),
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      Text(error!, style: TextStyle(color: t.danger)),
                    for (final c in candidates.take(20))
                      labelButton(
                        '${c['trackName']} · ${c['artistName']}\n${lyricSourceLabel(c['source'] as String? ?? 'lrclib')}',
                        () => report(context, () async {
                          if (p.current?.id != widget.track.id) {
                            throw const AppFailure('歌曲已切换，请重新打开歌词窗口');
                          }
                          final resolved = await p.lyricsClient
                              .resolveCandidate(c);
                          if (!context.mounted) return;
                          final use = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('${c['trackName']}'),
                              content: SingleChildScrollView(
                                child: Text(
                                  (resolved['syncedLyrics'] ??
                                          resolved['plainLyrics'] ??
                                          '暂无文本')
                                      .toString(),
                                ),
                              ),
                              actions: [
                                labelButton(
                                  '返回',
                                  () => Navigator.pop(ctx, false),
                                ),
                                labelButton(
                                  '使用这份歌词',
                                  () => Navigator.pop(ctx, true),
                                ),
                              ],
                            ),
                          );
                          if (use != true) return;
                          if (!context.mounted) return;
                          await report(context, () async {
                            await p.chooseLyrics(resolved, widget.track);
                            if (mounted) {
                              setState(() => allowExit = true);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) Navigator.pop(context);
                              });
                            }
                          });
                        }),
                      ),
                  ],
                  if (widget.section == 'edit') ...[
                    Row(
                      children: [
                        for (final item in ['原文', '翻译', '罗马音'].indexed)
                          Expanded(
                            child: labelButton(
                              item.$2,
                              () => setState(() => tab = item.$1),
                              selected: tab == item.$1,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: ValueKey('lyric-editor-$tab'),
                      controller: [original, translation, romaji][tab],
                      minLines: 12,
                      maxLines: 20,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: [
                          '歌词内容 · LRC / SPL / YRC',
                          '翻译歌词（可选）',
                          '罗马音（可选）',
                        ][tab],
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (editable) ...[
                    Row(
                      children: [
                        const Expanded(child: Text('时间偏移')),
                        action(
                          Icons.remove,
                          '歌词延后 0.1 秒',
                          offset > -60000
                              ? () => setState(() => offset -= 100)
                              : null,
                        ),
                        Text('${(offset / 1000).toStringAsFixed(1)} 秒'),
                        action(
                          Icons.add,
                          '歌词提前 0.1 秒',
                          offset < 60000
                              ? () => setState(() => offset += 100)
                              : null,
                        ),
                      ],
                    ),
                    Text(
                      '正值提前，负值延后',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
          bottomNavigationBar: !editable
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Pressable(
                      key: const ValueKey('保存歌词'),
                      label: '保存歌词',
                      color: t.accent,
                      onPressed: () => report(context, () async {
                        await p.setLyrics(
                          original.text,
                          track: widget.track,
                          offset: offset,
                          translation: translation.text,
                          romaji: romaji.text,
                        );
                        await p.save();
                        if (mounted) {
                          setState(() => allowExit = true);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) Navigator.pop(context);
                          });
                        }
                      }),
                      child: Center(
                        heightFactor: 1,
                        child: Text('保存', style: TextStyle(color: t.onAccent)),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
