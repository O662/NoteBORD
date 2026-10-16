import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'decoder.dart';
import 'ink_image.dart';

// The math model on ONNX Runtime (flutter_onnxruntime), on the device and
// offline. Two networks from tool/math_model/export.py: the encoder
// reads the picture once; the decoder takes one step for every hypothesis
// at a time, keeping its caches as native tensors that never come to Dart
// (it reorders them itself). Each step sends one small tensor, `ctl`: the
// tokens, the cache rows they continue, and the position.

/// Bump when the model files change, so the copies on the device are
/// replaced.
const mathModelVersion = 'comer-2';

const _heads = 8, _headDim = 32;

class OnnxMathModel implements MathModel {
  OnnxMathModel._(this._encoder, this._decoder);

  final OrtSession _encoder;
  final OrtSession _decoder;

  /// Loads the model bundled with the app.
  static Future<OnnxMathModel> load() async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'math', mathModelVersion));
    final runtime = OnnxRuntime();
    final encoder = await runtime.createSession(await _extract('encoder.onnx', dir));
    final decoder = await runtime.createSession(await _extract('decoder.onnx', dir));
    return OnnxMathModel._(encoder, decoder);
  }

  /// Copies a bundled model file to [dir] once (whole, or not at all).
  static Future<String> _extract(String name, Directory dir) async {
    final file = File(p.join(dir.path, name));
    if (await file.exists()) return file.path;
    await dir.create(recursive: true);
    final data = await rootBundle.load('assets/math/$name');
    final part = File('${file.path}.part');
    await part.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    await part.rename(file.path);
    return file.path;
  }

  Future<void> close() async {
    await _encoder.close();
    await _decoder.close();
  }

  @override
  Future<MathMemory> encode(InkImage image) async {
    final img = await OrtValue.fromList(image.pixels, [1, 1, image.height, image.width]);
    final Map<String, OrtValue> out;
    try {
      out = await _encoder.run({'img': img});
    } finally {
      unawaited(img.dispose());
    }
    // The feature map is the picture shrunk 16 times (rounding up); only
    // its shape matters to the decoder.
    final h = (image.height + 15) ~/ 16, w = (image.width + 15) ~/ 16;
    final grid = await OrtValue.fromList(Float32List(h * w), [h, w]);
    return _Memory(_decoder, out['memK']!, out['memV']!, grid, h * w);
  }
}

class _Memory implements MathMemory {
  _Memory(this._decoder, this._k, this._v, this._grid, this._length);

  final OrtSession _decoder;
  final OrtValue _k, _v, _grid;
  final int _length;

  @override
  Future<MathCache> start() async => _Cache(
        await OrtValue.fromList(Float32List(3 * _heads * _headDim), [3, 1, _heads, 1, _headDim]),
        await OrtValue.fromList(Float32List(3 * _heads * _headDim), [3, 1, _heads, 1, _headDim]),
        await OrtValue.fromList(Float32List(2 * 2 * _heads * _length), [2, 1, 2 * _heads, _length]),
      );

  @override
  Future<(Float32List, MathCache)> step(MathCache cache, List<int> from, List<int> tokens, int position) async {
    final c = cache as _Cache;
    final ctl = await OrtValue.fromList(Int64List.fromList([...tokens, ...from, position]), [2 * tokens.length + 1]);
    final Map<String, OrtValue> out;
    try {
      out = await _decoder.run({
        'ctl': ctl,
        'memK': _k,
        'memV': _v,
        'grid': _grid,
        'sk': c.sk,
        'sv': c.sv,
        'cov': c.cov,
      });
    } finally {
      unawaited(ctl.dispose());
    }
    final logp = out['logp']!;
    final scores = Float32List.fromList([for (final x in await logp.asFlattenedList()) (x as num).toDouble()]);
    unawaited(logp.dispose());
    return (scores, _Cache(out['sk_out']!, out['sv_out']!, out['cov_out']!));
  }

  @override
  Future<void> dispose() async {
    for (final v in [_k, _v, _grid]) {
      await v.dispose();
    }
  }
}

class _Cache implements MathCache {
  _Cache(this.sk, this.sv, this.cov);

  final OrtValue sk, sv, cov;

  @override
  Future<void> dispose() async {
    for (final v in [sk, sv, cov]) {
      unawaited(v.dispose());
    }
  }
}
