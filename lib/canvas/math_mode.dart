import 'package:flutter/widgets.dart';

// Math mode (Math.png): what the screen's chrome and the canvas share. The
// pen writes math, and what was just written is picked up for "Convert to
// math" once the pen rests; the keyboard types math, with the symbols and
// formulas (MathKit.png's panel) as tabs of its own.

/// What the math keyboard is typing.
class MathDraft {
  MathDraft({this.itemId, required this.at, String text = '', this.graph = false})
      : text = TextEditingController(text: text);

  /// The math item being edited, or null for new math.
  final String? itemId;

  /// Where new math goes (page space, its left middle).
  final Offset at;

  /// "Add a graph": Insert puts a graph of the function on the page.
  final bool graph;

  /// The keyboard's text (linear.dart).
  final TextEditingController text;

  void dispose() => text.dispose();
}

class MathMode extends ChangeNotifier {
  bool _on = false;
  bool _lasso = false;
  MathDraft? _draft;
  int _tab = 0;

  /// Math mode is on.
  bool get on => _on;

  /// The pen draws a lasso instead of writing.
  bool get lasso => _lasso;

  /// What the keyboard is typing, while it's open.
  MathDraft? get draft => _draft;

  /// The keyboard's tab (math_keys.dart's `mathKeyTabs`).
  int get tab => _tab;

  void start() {
    if (_on) return;
    _on = true;
    notifyListeners();
  }

  void end() {
    if (!_on) return;
    _on = false;
    _lasso = false;
    _closeDraft();
    notifyListeners();
  }

  set lasso(bool value) {
    if (value == _lasso) return;
    _lasso = value;
    notifyListeners();
  }

  /// Opens the keyboard on [draft] (closing any other).
  void type(MathDraft draft) {
    _closeDraft();
    _draft = draft;
    notifyListeners();
  }

  void closeKeyboard() {
    if (_draft == null) return;
    _closeDraft();
    notifyListeners();
  }

  void _closeDraft() {
    final d = _draft;
    _draft = null;
    // Its field may still be on screen this frame.
    if (d != null) WidgetsBinding.instance.addPostFrameCallback((_) => d.dispose());
  }

  set tab(int value) {
    if (value == _tab) return;
    _tab = value;
    notifyListeners();
  }

  /// Puts [text] (the keyboard's text) in the field at the cursor, the
  /// cursor ending [cursor] characters into it; false when the keyboard
  /// isn't open.
  bool insert(String text, {int? cursor}) {
    final field = _draft?.text;
    if (field == null) return false;
    insertAtCursor(field, text, cursor: cursor);
    return true;
  }

  @override
  void dispose() {
    _draft?.dispose();
    super.dispose();
  }
}

/// Types [text] into [field] at its cursor (replacing what's selected),
/// leaving the cursor [cursor] characters into it (at its end by default).
void insertAtCursor(TextEditingController field, String text, {int? cursor}) {
  final value = field.value;
  final sel = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
  final out = value.text.replaceRange(sel.start, sel.end, text);
  final at = sel.start + (cursor ?? text.length).clamp(0, text.length);
  field.value = TextEditingValue(text: out, selection: TextSelection.collapsed(offset: at));
}

/// Takes away the character before the cursor (or what's selected).
void backspaceAt(TextEditingController field) {
  final value = field.value;
  final sel = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
  if (!sel.isCollapsed) {
    field.value = TextEditingValue(
      text: value.text.replaceRange(sel.start, sel.end, ''),
      selection: TextSelection.collapsed(offset: sel.start),
    );
    return;
  }
  if (sel.start == 0) return;
  // One character, however many UTF-16 units it takes.
  final before = value.text.substring(0, sel.start).characters;
  final kept = before.skipLast(1).toString();
  field.value = TextEditingValue(
    text: kept + value.text.substring(sel.start),
    selection: TextSelection.collapsed(offset: kept.length),
  );
}
