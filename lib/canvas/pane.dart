import 'dart:async';

import 'package:flutter/widgets.dart';

import 'canvas_status.dart';
import 'canvas_view.dart';
import 'ruler.dart';
import 'selection.dart';

/// One view onto a notebook: which notebook, which page, and its pan/zoom.
/// The Canvas screen has one; Split view has two, which may show two pages
/// of the same notebook.
class Pane extends ChangeNotifier {
  Pane(this._notebookId, {int page = 0, Offset home = Offset.zero})
      : _page = page,
        view = CanvasView(home: home);

  String _notebookId;
  int _page;
  final CanvasView view;

  /// What's selected on the page shown (cleared when the page changes).
  final selection = Selection();

  /// The ruler over this view.
  final ruler = Ruler();

  /// A status or "… · Undo" message from a pen gesture, shown at the bottom.
  final status = ValueNotifier<CanvasStatus?>(null);
  Timer? _statusTimer;

  /// How long "Line straightened · Undo" and friends stay up.
  static const toastDuration = Duration(seconds: 4);

  /// Shows a status while something is going on ([text] null clears it).
  void showStatus(String? text) {
    _statusTimer?.cancel();
    status.value = text == null ? null : CanvasStatus(text);
  }

  /// Shows what just happened for a few seconds, with an Undo button for
  /// the last step on [undoPageId].
  void toast(String text, {String? undoPageId}) {
    _statusTimer?.cancel();
    final s = CanvasStatus(text, undoPageId: undoPageId);
    status.value = s;
    _statusTimer = Timer(toastDuration, () {
      if (status.value == s) status.value = null;
    });
  }

  /// Esc, or a tap on the chrome: the canvas finishes what it was in the
  /// middle of (typing in a text box, a drag).
  void dismiss() => notifyListeners();

  String get notebookId => _notebookId;

  /// Index of the page shown.
  int get page => _page;

  void goTo(int page) {
    if (page == _page) return;
    _page = page;
    selection.clear();
    view.reset();
    notifyListeners();
  }

  /// Keeps the page inside a notebook of [count] pages (no notification).
  void clampTo(int count) => _page = _page.clamp(0, count < 1 ? 0 : count - 1);

  void show(String notebookId, int page) {
    if (notebookId == _notebookId && page == _page) return;
    _notebookId = notebookId;
    _page = page;
    selection.clear();
    view.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    view.dispose();
    selection.dispose();
    ruler.dispose();
    status.dispose();
    super.dispose();
  }
}
