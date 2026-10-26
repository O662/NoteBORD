import 'package:flutter/widgets.dart';

import '../board/model.dart' show StrokeItem;

// Math mode (Math.png): what the screen's chrome and the canvas share. The
// pen writes math, and what was just written is picked up for "Convert to
// math" once the pen rests; the keyboard types math, with the symbols and
// formulas (MathKit.png's panel) as tabs of its own.

/// What Insert does with what the keyboard typed.
enum DraftFor {
  /// Math on the page: new, or [MathDraft.itemId] changed.
  math,

  /// "Add a graph": a new graph of the function.
  newGraph,

  /// A function (or, in 3D, a surface or point) on graph [MathDraft.itemId]:
  /// added, or the [MathDraft.index]th changed.
  graphLine,

  /// A point or interval on number line [MathDraft.itemId].
  numberLine,

  /// A curve on polar grid [MathDraft.itemId].
  polarCurve,
}

/// What the math keyboard is typing.
class MathDraft {
  MathDraft({
    this.itemId,
    required this.at,
    String text = '',
    this.purpose = DraftFor.math,
    this.index,
    this.span = false,
    this.hint = '',
    this.write = false,
  }) : text = TextEditingController(text: text);

  /// The math item being edited (or the graph or tool being added to), or
  /// null for new math.
  final String? itemId;

  /// Where new math goes (page space, its left middle).
  final Offset at;

  final DraftFor purpose;

  /// Which function, point, interval ([span]) or curve is being changed;
  /// null to add one.
  final int? index;
  final bool span;

  /// Shown in the empty line: what to type.
  final String hint;

  /// Opens on the writing pad ("write or type an equation…" with the pen).
  final bool write;

  /// What was last written on the writing pad, and the line it was read as:
  /// while the line still says that, a graph keeps the writing ("from your
  /// handwriting").
  List<StrokeItem> written = const [];
  String? writtenAs;

  /// "Add a graph": Insert puts a graph of the function on the page.
  bool get graph => purpose == DraftFor.newGraph;

  /// The keyboard's text (linear.dart).
  final TextEditingController text;

  void dispose() => text.dispose();
}

/// A math tool the Math tools bar asks the canvas to add (MathKit.png).
enum MathToolKind {
  numberLine('numberline'),
  unitCircle('unitcircle'),
  polarGrid('polar');

  const MathToolKind(this.widget);

  /// The `widget` field in the file.
  final String widget;
}

class MathMode extends ChangeNotifier {
  bool _on = false;
  bool _lasso = false;
  bool _select = false;
  bool _tools = false;
  MathDraft? _draft;
  int _tab = 0;
  MathToolKind? _wanted;

  /// Math mode is on.
  bool get on => _on;

  /// The pen draws a lasso instead of writing.
  bool get lasso => _lasso;

  /// Math tools' Select: the pen (and a finger) select what's on the page,
  /// to move it, resize it or delete it, as the Select tool does.
  bool get select => _select;

  set select(bool value) {
    if (value == _select) return;
    _select = value;
    if (value) _lasso = false;
    notifyListeners();
  }

  /// The bar is Math tools (MathKit.png): the number line, unit circle,
  /// polar grid and graph, with the keyboard's symbols and formulas. Its
  /// bar has Select, not Lasso: Lasso goes off on the way in, and Select on
  /// the way out.
  bool get tools => _tools;

  set tools(bool value) {
    if (value == _tools) return;
    _tools = value;
    if (value) {
      _lasso = false;
    } else {
      _select = false;
    }
    notifyListeners();
  }

  /// Asks the canvas to add a [kind] of tool to the page.
  void addTool(MathToolKind kind) {
    _wanted = kind;
    notifyListeners();
  }

  /// The tool asked for, once (the canvas takes it).
  MathToolKind? takeWantedTool() {
    final t = _wanted;
    _wanted = null;
    return t;
  }

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
    _select = false;
    _tools = false;
    _closeDraft();
    notifyListeners();
  }

  set lasso(bool value) {
    if (value == _lasso) return;
    _lasso = value;
    if (value) _select = false;
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
