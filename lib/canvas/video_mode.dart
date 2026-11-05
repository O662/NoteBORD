import 'package:flutter/foundation.dart';

import '../board/model.dart';

/// Videos in one view (Video.png): the one selected (the Video selected
/// bar shows), and a new one waiting to be put on the page.
class VideoMode extends ChangeNotifier {
  String? _selected;
  final _toPlace = <VideoItem>[];

  /// The video (item id) whose bar is showing.
  String? get selected => _selected;

  void select(String? itemId) {
    if (_selected == itemId) return;
    _selected = itemId;
    notifyListeners();
  }

  /// Puts [v] on the page shown (the canvas does it, at a free spot).
  void place(VideoItem v) {
    _toPlace.add(v);
    notifyListeners();
  }

  List<VideoItem> takeToPlace() {
    final out = [..._toPlace];
    _toPlace.clear();
    return out;
  }
}
