/// Window lifecycle shared by macOS and Windows. Native effects are injected so
/// hide/restore/exit ordering can be verified without a desktop plugin runtime.
enum DesktopPhase { visible, hidden, quitting, closed }

class DesktopSession {
  DesktopSession({
    required this.hideWindow,
    required this.showWindow,
    required this.persist,
    required this.stopPlayback,
    required this.destroyWindow,
  });
  final Future<void> Function() hideWindow,
      showWindow,
      persist,
      stopPlayback,
      destroyWindow;
  bool trayAvailable = false;
  DesktopPhase phase = DesktopPhase.visible;
  Future<void>? _quitFuture;
  Future<void> requestClose() async {
    if (phase == DesktopPhase.quitting || phase == DesktopPhase.closed) return;
    if (!trayAvailable) {
      await quit();
      return;
    }
    await hideWindow();
    phase = DesktopPhase.hidden;
  }

  Future<void> restore() async {
    if (phase == DesktopPhase.quitting || phase == DesktopPhase.closed) return;
    await showWindow();
    phase = DesktopPhase.visible;
  }

  Future<void> quit() => _quitFuture ??= _quit();
  Future<void> _quit() async {
    phase = DesktopPhase.quitting;
    try {
      // Do not stop or destroy the app if state cannot be saved.
      await persist();
      await stopPlayback();
      await destroyWindow();
      phase = DesktopPhase.closed;
    } catch (_) {
      phase = DesktopPhase.visible;
      _quitFuture = null;
      rethrow;
    }
  }
}
