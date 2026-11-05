import 'package:flutter/foundation.dart';

import '../audio/recording.dart';

/// Recordings in one view (Audio.png): a finished recording waiting to be
/// put on the page, and which recording's transcript panel is open.
class AudioMode extends ChangeNotifier {
  final _toPlace = <FinishedRecording>[];
  String? _transcript;

  /// Puts [r] on the page shown (the canvas does it, at a free spot).
  void place(FinishedRecording r) {
    _toPlace.add(r);
    notifyListeners();
  }

  /// The recordings waiting to be put on the page (taken by the canvas).
  List<FinishedRecording> takeToPlace() {
    final out = [..._toPlace];
    _toPlace.clear();
    return out;
  }

  /// The recording (item id) whose transcript panel is open.
  String? get transcriptOf => _transcript;

  void showTranscript(String? itemId) {
    if (_transcript == itemId) return;
    _transcript = itemId;
    notifyListeners();
  }

  void toggleTranscript(String itemId) => showTranscript(_transcript == itemId ? null : itemId);
}
