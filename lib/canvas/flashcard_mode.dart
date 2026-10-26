import 'package:flutter/widgets.dart';

// Making flashcards (FlashMake.png): circle the front, then the back, then
// Add card. What the screen's chrome and the canvas share.

/// One side being circled: the items and the loop drawn round them (page
/// space; null when it was picked another way).
@immutable
class CircledSide {
  const CircledSide(this.ids, [this.loop]);

  final List<String> ids;
  final Path? loop;
}

class FlashcardMode extends ChangeNotifier {
  bool _on = false;
  CircledSide? _front;
  CircledSide? _back;
  bool _reverse = false;
  String _deckId = '';
  String _deckName = '';
  String? _added;
  int _serial = 0;

  /// Making flashcards is on.
  bool get on => _on;

  CircledSide? get front => _front;
  CircledSide? get back => _back;

  /// "Also quiz me back to front".
  bool get reverse => _reverse;
  set reverse(bool v) {
    if (v == _reverse) return;
    _reverse = v;
    notifyListeners();
  }

  /// The deck new cards go into.
  String get deckId => _deckId;
  String get deckName => _deckName;

  /// The deck a card was just added to ("Card added to … · Study now"),
  /// until the next one is circled.
  String? get addedTo => _added;

  /// Changes each time a card is added (the screen's message keys on it).
  int get serial => _serial;

  bool get ready => _front != null && _back != null;

  /// Starts, into deck [deckId]; [front] is what's already selected.
  void start({required String deckId, required String deckName, CircledSide? front}) {
    _on = true;
    _deckId = deckId;
    _deckName = deckName;
    _front = front != null && front.ids.isNotEmpty ? front : null;
    _back = null;
    _added = null;
    notifyListeners();
  }

  void end() {
    if (!_on) return;
    _on = false;
    _front = null;
    _back = null;
    _added = null;
    notifyListeners();
  }

  void pickDeck(String id, String name) {
    _deckId = id;
    _deckName = name;
    notifyListeners();
  }

  /// Something was circled: it's the front, then the back. Circling again
  /// with both done changes the back.
  void circled(CircledSide side) {
    if (side.ids.isEmpty) return;
    _added = null;
    if (_front == null) {
      _front = side;
    } else {
      _back = side;
    }
    notifyListeners();
  }

  /// Clear: start the card again.
  void clear() {
    _front = null;
    _back = null;
    notifyListeners();
  }

  /// The card was added: on to the next one.
  void added() {
    _added = _deckName;
    _serial++;
    _front = null;
    _back = null;
    notifyListeners();
  }
}
