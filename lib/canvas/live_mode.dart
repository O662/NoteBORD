import 'package:flutter/foundation.dart';

/// What the Live items bar adds to the page.
enum LiveKind {
  clock('a clock'),
  date('today’s date'),
  stamp('a time stamp'),
  checklist('a checklist');

  const LiveKind(this.noun);

  /// For "Added … to the page".
  final String noun;
}

/// Live items (LiveItems.png): the bar in place of the tool pill while it's
/// on, and what's been asked for, which the canvas adds where there's room.
class LiveMode extends ChangeNotifier {
  bool _on = false;
  final _wanted = <LiveKind>[];

  bool get on => _on;

  void start() {
    if (_on) return;
    _on = true;
    notifyListeners();
  }

  void end() {
    if (!_on) return;
    _on = false;
    notifyListeners();
  }

  /// Asks the canvas to add [kind] (with the bar on or not).
  void add(LiveKind kind) {
    _wanted.add(kind);
    notifyListeners();
  }

  /// What's been asked for since last time.
  List<LiveKind> takeWanted() {
    final out = [..._wanted];
    _wanted.clear();
    return out;
  }
}
