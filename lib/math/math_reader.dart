import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/model.dart' show StrokeItem;
import 'decoder.dart';
import 'ink_image.dart';
import 'latex.dart';
import 'onnx_math.dart';

// Reads handwritten math on the device, offline, on every platform the app
// runs on (the model ships with the app: assets/math). One reading at a
// time; the last few are remembered, so the preview and "Convert to math"
// don't read the same ink twice.

/// What some handwriting says, as math.
@immutable
class MathReading {
  const MathReading(this.latex, {this.others = const []});

  /// The best reading.
  final String latex;

  /// Other readings, best first (for "Not sure? Try…").
  final List<String> others;
}

class MathReader {
  MathReader(this._load);

  final Future<MathModel> Function() _load;
  Future<MathModel?>? _model;
  Future<void> _tail = Future.value();
  final _recent = <String, MathReading?>{};
  bool _disposed = false;

  /// False once the model turned out not to load here.
  bool available = true;

  /// What [strokes] say, or null when they don't read as math (or there's
  /// no model on this device).
  Future<MathReading?> read(List<StrokeItem> strokes) {
    final key = [for (final s in strokes) '${s.id}@${s.x},${s.y},${s.points.length}'].join('|');
    if (_recent.containsKey(key)) return Future.value(_recent[key]);
    final done = Completer<MathReading?>();
    _tail = _tail.then((_) async {
      if (_recent.containsKey(key)) return done.complete(_recent[key]);
      try {
        final reading = await _read(strokes);
        _remember(key, reading);
        done.complete(reading);
      } on Object catch (e, st) {
        debugPrint('Math reading failed: $e\n$st');
        done.complete(null);
      }
    });
    return done.future;
  }

  void _remember(String key, MathReading? reading) {
    _recent[key] = reading;
    if (_recent.length > 24) _recent.remove(_recent.keys.first);
  }

  Future<MathReading?> _read(List<StrokeItem> strokes) async {
    final image = renderInk([
      for (final s in strokes) [for (final p in s.pageInk) Offset(p.x, p.y)],
    ]);
    if (image == null || _disposed) return null;
    final model = await (_model ??= _loadModel());
    if (model == null || _disposed) return null;
    final readings = [
      for (final h in await readMath(model, image))
        if (latexFromSymbols(h.symbols) case final latex when h.tokens.isNotEmpty && isDrawable(latex)) latex,
    ];
    if (readings.isEmpty) return null;
    return MathReading(readings.first, others: readings.skip(1).take(4).toList());
  }

  Future<MathModel?> _loadModel() async {
    try {
      return await _load();
    } on Object catch (e) {
      debugPrint('No math model here: $e');
      available = false;
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    _model?.then((m) {
      if (m is OnnxMathModel) m.close();
    });
  }
}

final mathReaderProvider = Provider<MathReader>((ref) {
  final reader = MathReader(OnnxMathModel.load);
  ref.onDispose(reader.dispose);
  return reader;
});
