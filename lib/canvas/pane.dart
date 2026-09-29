import 'package:flutter/widgets.dart';

import 'canvas_view.dart';

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

  String get notebookId => _notebookId;

  /// Index of the page shown.
  int get page => _page;

  void goTo(int page) {
    if (page == _page) return;
    _page = page;
    view.reset();
    notifyListeners();
  }

  /// Keeps the page inside a notebook of [count] pages (no notification).
  void clampTo(int count) => _page = _page.clamp(0, count < 1 ? 0 : count - 1);

  void show(String notebookId, int page) {
    if (notebookId == _notebookId && page == _page) return;
    _notebookId = notebookId;
    _page = page;
    view.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    view.dispose();
    super.dispose();
  }
}
