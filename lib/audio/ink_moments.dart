import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/model.dart';

/// Hears of strokes as they're written, so a recording can note when each
/// was written (Audio.png: ink lights up as the recording reaches it).
class InkMoments {
  void Function(String notebookId, Iterable<StrokeItem> strokes)? _listener;

  /// Only one recording listens at a time.
  set listener(void Function(String notebookId, Iterable<StrokeItem> strokes)? l) => _listener = l;

  void wrote(String notebookId, Iterable<StrokeItem> strokes) {
    if (_listener == null || strokes.isEmpty) return;
    _listener!(notebookId, strokes);
  }
}

final inkMomentsProvider = Provider<InkMoments>((ref) => InkMoments());
