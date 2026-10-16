import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/page_runtime.dart' show paintStroke;
import '../../recognition/handwriting_index.dart';
import '../../recognition/models.dart';
import '../../recognition/recognizer.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../dialogs.dart';

/// "Write your search with the S Pen": a small pad that reads what's
/// written on it. Returns the text, or null if cancelled.
Future<String?> showWriteQuery(BuildContext context) =>
    showEndlessDialog<String>(context, builder: (context) => const _WriteQuery());

class _WriteQuery extends ConsumerStatefulWidget {
  const _WriteQuery();

  @override
  ConsumerState<_WriteQuery> createState() => _WriteQueryState();
}

class _WriteQueryState extends ConsumerState<_WriteQuery> {
  final _strokes = <StrokeItem>[];
  List<InkPoint>? _current;
  DateTime? _startedAt;
  int? _pointer;
  Timer? _idle;
  String _text = '';
  bool _reading = false;
  String? _problem;
  int _run = 0;

  late final HandwritingIndex _index = ref.read(handwritingIndexProvider);

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null || !_index.canRecognize) return;
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
        id: 'q${_strokes.length}',
        z: _strokes.length,
        createdAt: _startedAt!,
        tool: InkTool.pen,
        penType: PenType.ballpoint,
        color: const Color(0xFF000000),
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
    setState(() {
      _reading = true;
      _problem = null;
    });
    try {
      final read = await _index.read(_strokes, language: _index.language);
      if (!mounted || mine != _run) return;
      setState(() {
        _text = read.text.replaceAll('\n\n', ' ');
        _reading = false;
      });
    } on Object catch (e) {
      if (!mounted || mine != _run) return;
      setState(() {
        _reading = false;
        _problem = e is RecognitionFailed ? e.message : 'Couldn’t read that. Try writing it again.';
      });
    }
  }

  void _clear() {
    _idle?.cancel();
    _run++;
    setState(() {
      _strokes.clear();
      _text = '';
      _problem = null;
      _reading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = ref.watch(inkModelsProvider);
    final can = _index.canRecognize;
    final status = !can
        ? 'Handwriting recognition runs on the tablet. Type your search instead.'
        : _problem ??
            (_reading && note?.phase == ModelPhase.downloading
                ? note!.text
                : _reading
                    ? 'Reading…'
                    : _text.isEmpty
                        ? 'Write a word or two with the S Pen'
                        : null);
    return DialogFrame(
      title: 'Write your search',
      width: 600,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        Semantics(
          label: 'Writing pad',
          child: Container(
            height: 200,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: c.surfaceSunk,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: CustomPaint(
                painter: _PadPainter(_strokes, _current, c.text),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        Row(spacing: 12, children: [
          Expanded(
            child: status == null
                ? Text(_text, style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 24, color: c.text))
                : Text(status, style: TextStyle(fontSize: 14, color: c.textMuted)),
          ),
          SecondaryButton(label: 'Clear', onPressed: _strokes.isEmpty ? null : _clear, height: 46),
          PrimaryButton(
            label: 'Search',
            height: 46,
            onPressed: _text.trim().isEmpty || _reading ? null : () => Navigator.of(context).pop(_text.trim()),
          ),
        ]),
      ]),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes, this.current, this.live);

  final List<StrokeItem> strokes;
  final List<InkPoint>? current;
  final Color live;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      paintStroke(canvas, s, live);
    }
    final pts = current;
    if (pts == null || pts.isEmpty) return;
    final path = Path()..moveTo(pts.first.x, pts.first.y);
    for (final p in pts.skip(1)) {
      path.lineTo(p.x, p.y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = live
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}
