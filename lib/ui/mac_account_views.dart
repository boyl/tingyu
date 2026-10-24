part of 'app.dart';

/// Mac view of the shared account session: one modal, one primary action.
class _MacAccountPanelView extends StatelessWidget {
  const _MacAccountPanelView(this.state);
  final _AccountPanelState state;

  Widget primary(
    BuildContext context,
    String label,
    FutureOr<void> Function()? onPressed, {
    Key? key,
  }) {
    final t = context.tokens;
    return Pressable(
      key: key,
      label: label,
      onPressed: onPressed,
      radius: TingyuTokens.radius,
      color: onPressed == null ? t.tint : t.accent,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: onPressed == null ? t.muted : t.onAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens, p = state.widget.p;
    final connected = p.profile != null;
    final height = state.imported != null
        ? TingyuTokens.macResultHeight
        : connected
        ? TingyuTokens.macAccountHeight
        : TingyuTokens.macLoginHeight;
    return LayoutBuilder(
      builder: (context, box) => AnimatedContainer(
        key: const ValueKey('mac-account-task'),
        width: connected
            ? TingyuTokens.macAccountWidth
            : TingyuTokens.macLoginWidth,
        height: math.min(box.maxHeight, height),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : TingyuTokens.transition,
        curve: Curves.easeOutCubic,
        child: Padding(
          padding: const EdgeInsets.all(TingyuTokens.space * 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connected ? '收藏夹' : '登录哔哩哔哩',
                          style: const TextStyle(
                            fontSize: TingyuTokens.macMenuTitle,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (connected)
                          Text(
                            '${p.profile!['uname']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.muted),
                          ),
                      ],
                    ),
                  ),
                  action(Icons.clear, '关闭账号窗口', () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: TingyuTokens.space * 2),
              Expanded(child: connected ? folders(context) : login(context)),
              if (connected &&
                  state.message.isNotEmpty &&
                  state.imported == null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: TingyuTokens.space,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      state.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.muted,
                        fontSize: TingyuTokens.macCaption,
                      ),
                    ),
                  ),
                ),
              if (connected) footer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget login(BuildContext context) {
    final t = context.tokens;
    final retry =
        !state.busy && (state.qrExpired || state.qrFailed || state.qr == null);
    final message = state.busy
        ? '正在连接…'
        : state.message == '等待 B 站确认登录' || state.message.isEmpty
        ? '使用哔哩哔哩 App 扫码登录'
        : state.message;
    return SingleChildScrollView(
      key: const ValueKey('account-content'),
      child: Column(
        children: [
          const SizedBox(height: TingyuTokens.space * 2),
          Center(
            child: Container(
              key: const ValueKey('mac-login-qr'),
              width: TingyuTokens.macAccountQr,
              height: TingyuTokens.macAccountQr,
              padding: const EdgeInsets.all(TingyuTokens.space),
              decoration: BoxDecoration(
                color: TingyuTokens.onArtwork,
                borderRadius: BorderRadius.circular(TingyuTokens.radius),
                border: Border.all(color: t.line),
              ),
              child: state.busy
                  ? const Center(child: CircularProgressIndicator())
                  : retry
                  ? Center(
                      child: TingyuIcon(
                        Icons.qr_code_2,
                        size: TingyuTokens.controlSize,
                        color: t.muted,
                      ),
                    )
                  : QrImageView(data: state.qr!, padding: EdgeInsets.zero),
            ),
          ),
          const SizedBox(height: TingyuTokens.space * 2),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: state.qrFailed ? t.danger : t.muted,
                fontSize: TingyuTokens.macTrackTitle,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: TingyuTokens.space),
          if (retry)
            labelButton(
              '刷新二维码',
              () => state.generate(openApp: false),
              icon: Icons.refresh,
            ),
        ],
      ),
    );
  }

  Widget folders(BuildContext context) {
    final t = context.tokens;
    if (state.imported case final Playlist list) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TingyuIcon(
                Icons.check_circle_outline,
                size: TingyuTokens.controlSize,
                color: t.accent,
              ),
              const SizedBox(height: TingyuTokens.space * 2),
              Text(
                '已导入 ${state.importedCount} 个收藏夹',
                style: const TextStyle(
                  fontSize: TingyuTokens.macDetailTitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: TingyuTokens.space),
              Text(
                list.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.muted),
              ),
              const SizedBox(height: TingyuTokens.space),
              Text(
                '${list.trackIds.length} 首歌曲',
                style: TextStyle(color: t.muted),
              ),
            ],
          ),
        ),
      );
    }
    final visible = state.folders
        .where(
          (f) => matchesFolderName('${f['title']}', state.folderSearch.text),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '收藏夹 · ${state.folders.length}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            labelButton(
              '全选',
              state.busy || visible.isEmpty ? null : state._macSelectVisible,
            ),
            action(
              Icons.refresh,
              '刷新收藏夹',
              state.busy ? null : state.loadProfile,
            ),
          ],
        ),
        TextField(
          key: const ValueKey('mac-folder-search'),
          controller: state.folderSearch,
          enabled: !state.busy,
          decoration: const InputDecoration(
            prefixIcon: Padding(
              padding: EdgeInsets.all(TingyuTokens.space * 1.5),
              child: TingyuIcon(Icons.search, size: TingyuTokens.iconSize),
            ),
            hintText: '查找收藏夹',
          ),
          onChanged: state._macFolderQuery,
        ),
        const SizedBox(height: TingyuTokens.space),
        if (state.busy) const LinearProgressIndicator(),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    state.busy
                        ? '正在加载收藏夹…'
                        : state.folders.isEmpty
                        ? '暂无可导入的收藏夹'
                        : '没有匹配的收藏夹',
                    style: TextStyle(color: t.muted),
                  ),
                )
              : ListView.separated(
                  key: const ValueKey('account-content'),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: t.line),
                  itemBuilder: (context, i) {
                    final folder = visible[i],
                        selected = state.selectedFolders.contains(
                          visible[i]['id'],
                        );
                    return Pressable(
                      key: ValueKey('folder-${folder['id']}'),
                      label:
                          '${selected ? '取消选择' : '选择'}收藏夹 ${folder['title']}',
                      selected: selected,
                      onPressed: state.busy
                          ? null
                          : () => state._macToggleFolder(folder),
                      child: Row(
                        children: [
                          TingyuIcon(Icons.folder_outlined, color: t.muted),
                          const SizedBox(width: TingyuTokens.space * 2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${folder['title']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${folder['media_count'] ?? 0} 首',
                                  style: TextStyle(
                                    color: t.muted,
                                    fontSize: TingyuTokens.macCaption,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TingyuIcon(
                            selected
                                ? Icons.check_circle_outline
                                : Icons.radio_button_unchecked,
                            color: selected ? t.accent : t.muted,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget footer(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: TingyuTokens.space * 2),
    child: Row(
      children: [
        labelButton('退出账号', state.busy ? null : state._macLogout),
        const Spacer(),
        if (state.imported != null) ...[
          labelButton('继续导入', state._macContinueImport),
          const SizedBox(width: TingyuTokens.space),
        ],
        SizedBox(
          width: TingyuTokens.macAccountAction,
          child: primary(
            context,
            state.imported != null
                ? '打开歌单'
                : state.busy
                ? '正在导入或加载…'
                : state.selectedFolders.isEmpty
                ? '选择收藏夹'
                : '导入 ${state.selectedFolders.length} 个收藏夹',
            state.busy
                ? null
                : state.imported != null
                ? state._macOpenImported
                : state.selectedFolders.isEmpty
                ? null
                : state.importSelected,
            key: ValueKey(
              state.imported != null ? 'mac-open-imported' : 'import-folders',
            ),
          ),
        ),
      ],
    ),
  );
}
