import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/math_mode.dart';
import '../../canvas/page_runtime.dart' show paintStroke;
import '../../math/linear.dart';
import '../../math/math_pictures.dart' show mathFontFallback;
import '../../math/math_reader.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../icons.dart';
import 'math_keys.dart';

/// The math keyboard (Math.dc.html's "Math keyboard"): the math being typed
/// as a line, Delete, Write it instead, Insert; tabs of Greek letters,
/// operators, structures and units, then MathKit.png's symbols and formulas
/// (one popup for both, so the page stays free). Letters and digits come
/// from the tablet's keyboard (tap the line) or from writing.
class MathKeyboard extends ConsumerStatefulWidget {
  const MathKeyboard({super.key, required this.math, required this.draft, required this.onInsert, this.width = 1060});

  /// Holds the tab, which Formulas & tools picks too.
  final MathMode math;
  final MathDraft draft;
  final VoidCallback onInsert;
  final double width;

  @override
  ConsumerState<MathKeyboard> createState() => _MathKeyboardState();
}

class _MathKeyboardState extends ConsumerState<MathKeyboard> {
  final _focus = FocusNode();
  var _writing = false;

  /// The tablet's own keyboard is wanted (after a tap on the line).
  var _system = false;

  TextEditingController get _field => widget.draft.text;

  @override
  void initState() {
    super.initState();
    if (_field.selection.baseOffset < 0) _field.selection = TextSelection.collapsed(offset: _field.text.length);
    // The line has the cursor from the start, for the keys; the tablet's
    // keyboard waits for a tap on it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _press(String text, {int? cursor}) {
    insertAtCursor(_field, text, cursor: cursor);
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  void _showSystemKeyboard() {
    if (_system) return;
    setState(() => _system = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = widget.math.tab.clamp(0, mathKeyTabs.length - 1);
    final tab = mathKeyTabs[selected];
    return Semantics(
      container: true,
      label: 'Math keyboard',
      explicitChildNodes: true,
      child: TextFieldTapRegion(
        child: Container(
          width: widget.width,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(0, 24), blurRadius: 48, spreadRadius: -24)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            Row(spacing: 10, children: [
              Expanded(
                child: Semantics(
                  label: 'Equation being edited',
                  textField: true,
                  child: Container(
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      border: Border.all(color: c.accent, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _field,
                      focusNode: _focus,
                      keyboardType: _system ? TextInputType.text : TextInputType.none,
                      autocorrect: false,
                      enableSuggestions: false,
                      onTap: _showSystemKeyboard,
                      onSubmitted: (_) => widget.onInsert(),
                      cursorColor: c.accent,
                      style: TextStyle(
                        fontFamily: FontFamilies.serif,
                        fontFamilyFallback: mathFontFallback,
                        fontStyle: FontStyle.italic,
                        fontSize: 28,
                        color: c.text,
                      ),
                      decoration: const InputDecoration.collapsed(hintText: ''),
                    ),
                  ),
                ),
              ),
              _Backspace(onPress: () => backspaceAt(_field)),
              _Button(
                label: _writing ? 'Type it instead' : 'Write it instead',
                onTap: () => setState(() => _writing = !_writing),
              ),
              _Button(label: 'Insert', dark: true, onTap: widget.onInsert),
            ]),
            if (_writing)
              _WritingPad(onRead: (text) => _field.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)))
            else ...[
              Semantics(
                container: true,
                label: 'Symbol sets',
                explicitChildNodes: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(spacing: 6, children: [
                    for (final (i, t) in mathKeyTabs.indexed)
                      _Tab(label: t.label, selected: i == selected, onTap: () => widget.math.tab = i),
                  ]),
                ),
              ),
              // Three rows of keys, whatever the tab (Symbols scrolls), so
              // the keyboard keeps its height.
              SizedBox(
                height: _keysHeight,
                child: LayoutBuilder(builder: (context, box) {
                  const gap = 6.0;
                  if (tab.formulas.isNotEmpty) {
                    const columns = 4;
                    final w = (box.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(spacing: gap, runSpacing: gap, children: [
                      for (final f in tab.formulas)
                        SizedBox(
                          width: w,
                          height: (_keysHeight - gap) / 2,
                          child: _FormulaKey(f, onTap: () => _press(f.text)),
                        ),
                    ]);
                  }
                  const columns = 12;
                  final w = (box.maxWidth - gap * (columns - 1)) / columns;
                  return SingleChildScrollView(
                    child: Wrap(spacing: gap, runSpacing: gap, children: [
                      for (final k in tab.keys)
                        SizedBox(
                          width: w,
                          child: _Key(k, onTap: () => _press(k.types, cursor: k.cursor)),
                        ),
                    ]),
                  );
                }),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Three rows of 48 px keys and their gaps.
const _keysHeight = 48 * 3 + 6 * 2.0;

/// A formula from MathKit.png's library: its name over it.
class _FormulaKey extends StatelessWidget {
  const _FormulaKey(this.f, {required this.onTap});

  final Formula f;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Insert ${f.name}',
      excludeSemantics: true,
      child: Material(
        color: c.surfaceSunk,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.lineSoft)),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, spacing: 2, children: [
              Text(f.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.textMuted)),
              Text(
                formulaLabel(f.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FontFamilies.serif,
                  fontFamilyFallback: mathFontFallback,
                  fontStyle: FontStyle.italic,
                  fontSize: 18,
                  color: c.text,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.k, {required this.onTap});

  final MathKey k;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Insert ${k.name}',
      excludeSemantics: true,
      child: Material(
        color: c.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.cardLine)),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                k.label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: FontFamilies.serif,
                  fontFamilyFallback: mathFontFallback,
                  fontSize: k.label.length > 3 ? 16 : 22,
                  color: c.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label.split('  ').first,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.inverse : c.side,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamilyFallback: mathFontFallback,
                color: selected ? c.onInverse : c.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap, this.dark = false});

  final String label;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: dark ? c.inverse : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: dark ? BorderSide.none : BorderSide(color: c.lineStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 54,
            padding: EdgeInsets.symmetric(horizontal: dark ? 22 : 16),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: dark ? 15 : 14,
                fontWeight: dark ? FontWeight.w700 : FontWeight.w600,
                color: dark ? c.onInverse : c.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Delete: one symbol, then on and on while it's held.
class _Backspace extends StatefulWidget {
  const _Backspace({required this.onPress});

  final VoidCallback onPress;

  @override
  State<_Backspace> createState() => _BackspaceState();
}

class _BackspaceState extends State<_Backspace> {
  Timer? _hold;

  void _stop() {
    _hold?.cancel();
    _hold = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Delete last symbol',
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) {
          widget.onPress();
          _hold = Timer(const Duration(milliseconds: 450), () {
            _hold = Timer.periodic(const Duration(milliseconds: 70), (_) => widget.onPress());
          });
        },
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            border: Border.all(color: c.lineStrong),
            borderRadius: BorderRadius.circular(12),
          ),
          child: EIcon(EIcons.backspace, size: 22, color: c.text),
        ),
      ),
    );
  }
}

/// "Write it instead": a pad the math is written on, read when the pen
/// rests; what it says replaces the line.
class _WritingPad extends ConsumerStatefulWidget {
  const _WritingPad({required this.onRead});

  final ValueChanged<String> onRead;

  @override
  ConsumerState<_WritingPad> createState() => _WritingPadState();
}

class _WritingPadState extends ConsumerState<_WritingPad> {
  final _strokes = <StrokeItem>[];
  List<InkPoint>? _current;
  DateTime? _startedAt;
  int? _pointer;
  Timer? _idle;
  String? _status;
  var _run = 0;

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _idle?.cancel();
    _startedAt = DateTime.now().toUtc();
    setState(() => _current = [InkPoint(e.localPosition.dx, e.localPosition.dy, 0.5, 0)]);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _current == null) return;
    final t = DateTime.now().toUtc().difference(_startedAt!).inMilliseconds;
    setState(() => _current!.add(InkPoint(e.localPosition.dx, e.localPosition.dy, 0.5, t)));
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final pts = _current;
    _current = null;
    if (pts != null && pts.isNotEmpty) {
      _strokes.add(StrokeItem.fromPagePoints(
        id: 'pad${_strokes.length}',
        z: _strokes.length,
        createdAt: _startedAt!,
        tool: InkTool.pen,
        penType: PenType.ballpoint,
        color: inkDefaults.first,
        width: 3,
        usePressure: false,
        pagePoints: pts,
      ));
    }
    setState(() {});
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 800), _read);
  }

  Future<void> _read() async {
    if (_strokes.isEmpty) return;
    final mine = ++_run;
    setState(() => _status = 'Reading…');
    final reader = ref.read(mathReaderProvider);
    final reading = await reader.read([..._strokes]);
    if (!mounted || mine != _run) return;
    if (reading == null) {
      setState(() => _status = reader.available ? 'Couldn’t read that as math' : 'Math can’t be read on this device');
      return;
    }
    setState(() => _status = null);
    widget.onRead(latexToLinear(reading.latex));
  }

  void _clear() {
    _idle?.cancel();
    _run++;
    setState(() {
      _strokes.clear();
      _status = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Writing pad',
      child: Container(
        height: 208,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surfaceSunk,
          border: Border.all(color: c.cardLine),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: CustomPaint(painter: _PadPainter(_strokes, _current, c.text)),
            ),
          ),
          if (_strokes.isEmpty && _current == null)
            IgnorePointer(
              child: Center(
                child: Text('Write the math here', style: TextStyle(fontSize: 15, color: c.textFaint)),
              ),
            ),
          Positioned(
            right: 6,
            bottom: 6,
            child: Row(spacing: 8, children: [
              if (_status != null) Text(_status!, style: TextStyle(fontSize: 13, color: c.textMuted)),
              if (_strokes.isNotEmpty)
                TextButton(onPressed: _clear, child: Text('Clear', style: TextStyle(color: c.accentDeep))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes, this.current, this.color);

  final List<StrokeItem> strokes;
  final List<InkPoint>? current;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      paintStroke(canvas, s, color);
    }
    final pts = current;
    if (pts != null && pts.isNotEmpty) {
      final path = Path()..moveTo(pts.first.x, pts.first.y);
      for (final p in pts.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}
