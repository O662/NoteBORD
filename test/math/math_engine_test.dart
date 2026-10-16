import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:endless/math/decoder.dart';
import 'package:endless/math/ink_image.dart';
import 'package:endless/math/latex.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pen strokes from MathWriting (test/fixtures/math), with the picture
/// tool/math_model/render.py draws for them and what the model reads.
List<Map<String, dynamic>> samples() =>
    (jsonDecode(File('test/fixtures/math/ink_samples.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

List<List<Offset>> strokesOf(Map<String, dynamic> s) => [
      for (final stroke in s['strokes'] as List)
        [for (final p in stroke as List) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())],
    ];

/// A model that knows one answer: the next symbol of [target] is very
/// likely, anything else isn't. Read right to left it knows it backwards.
class ScriptedModel implements MathModel {
  ScriptedModel(this.target, {this.sure = 0.9});

  final List<int> target;
  final double sure;
  int steps = 0;

  @override
  Future<MathMemory> encode(InkImage image) async => _Memory(this);
}

class _Cache implements MathCache {
  _Cache(this.rows);

  final List<List<int>> rows;
  bool disposed = false;

  @override
  Future<void> dispose() async => disposed = true;
}

class _Memory implements MathMemory {
  _Memory(this.model);

  final ScriptedModel model;

  @override
  Future<MathCache> start() async => _Cache([[]]);

  @override
  Future<(Float32List, MathCache)> step(MathCache cache, List<int> from, List<int> tokens, int position) async {
    model.steps++;
    final c = cache as _Cache;
    expect(c.disposed, isFalse, reason: 'a step used a cache already let go');
    final rows = [for (final (i, b) in from.indexed) [...c.rows[b], tokens[i]]];
    final v = mathVocab.length;
    final out = Float32List(rows.length * v);
    for (final (r, row) in rows.indexed) {
      // row[0] is the start token: 1 reads left to right, 2 right to left.
      final want = row.first == 1 ? [...model.target, 2] : [...model.target.reversed, 1];
      final at = row.length - 1;
      final onTrack = at < want.length && List.generate(at, (k) => row[k + 1] == want[k]).every((x) => x);
      for (var t = 0; t < v; t++) {
        final p = onTrack && t == want[at] ? model.sure : (1 - model.sure) / (v - 1);
        out[r * v + t] = math.log(p);
      }
    }
    return (out, _Cache(rows));
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('drawing handwriting for the model', () {
    for (final s in samples()) {
      test(s['label'] as String, () {
        final img = renderInk(strokesOf(s))!;
        expect((img.width, img.height), (s['width'], s['height']));
        final bits = base64Decode(s['bits'] as String);
        var differ = 0;
        for (var k = 0; k < img.width * img.height; k++) {
          final want = (bits[k >> 3] >> (7 - (k & 7))) & 1 == 1;
          if (want != img.pixels[k] > 0) differ++;
        }
        // Rounding at a stroke's edge may differ by a pixel here and there.
        expect(differ, lessThan(img.width * img.height * 0.002), reason: '$differ pixels differ');
      });
    }

    test('writing size ignores flat strokes', () {
      final tall = [const Offset(0, 0), const Offset(2, 30)];
      final minus = [const Offset(0, 50), const Offset(40, 50)];
      expect(writingSize([tall, minus, tall]), 30);
    });

    test('a big expression is shrunk to the model\'s limits', () {
      final img = renderInk([
        [const Offset(0, 0), const Offset(5000, 0)],
        [const Offset(0, 0), const Offset(0, 40)],
      ])!;
      expect(img.width, lessThanOrEqualTo(1024));
      expect(img.height, lessThanOrEqualTo(256));
    });

    test('no ink, no picture', () => expect(renderInk([]), isNull));
  });

  group('reading', () {
    final image = InkImage(16, 16, Float32List(256));
    int id(String s) => mathVocab.indexOf(s);

    test('finds the answer the model is sure of, from both directions', () async {
      final target = [id('x'), id('^'), id('{'), id('2'), id('}')];
      final model = ScriptedModel(target);
      final best = (await readMath(model, image)).first;
      expect(best.symbols, ['x', '^', '{', '2', '}']);
      expect(latexFromSymbols(best.symbols), 'x^{2}');
    });

    test('a beam\'s score is what rating the same reading gives', () async {
      final target = [id(r'\frac'), id('{'), id('1'), id('}'), id('{'), id('2'), id('}')];
      final memory = await ScriptedModel(target, sure: 0.6).encode(image);
      final [found] = await beamSearch(memory, const [(1, 2)], beamSize: 4);
      final rated = await rate(memory, [(found.first.tokens, 1, 2)]);
      expect(found.first.tokens, target);
      expect(rated.single, closeTo(found.first.score, 1e-5));
    });

    test('both directions run in the same steps', () async {
      final target = [id('a'), id('+'), id('b')];
      final together = ScriptedModel(target);
      await readMath(together, image, beamSize: 3);
      // The same searches and ratings one at a time.
      final apart = ScriptedModel(target);
      final memory = await apart.encode(image);
      final [l2r] = await beamSearch(memory, const [(1, 2)], beamSize: 3);
      final [r2l] = await beamSearch(memory, const [(2, 1)], beamSize: 3);
      await rate(memory, [for (final h in l2r) (h.tokens.reversed.toList(), 2, 1)]);
      await rate(memory, [for (final h in r2l) (h.tokens, 1, 2)]);
      expect(together.steps, lessThan(apart.steps * 0.6));
    });

    test('readings are each listed once', () async {
      final all = await readMath(ScriptedModel([id('a')]), image, beamSize: 3);
      final keys = all.map((h) => h.tokens.join(',')).toList();
      expect(keys.toSet().length, keys.length);
    });
  });

  group('LaTeX from the recognizer', () {
    test('compact, spaced only where a command needs it', () {
      expect(latexFromSymbols([r'\sin', 'x', '+', r'\frac', '{', '1', '}', '{', '2', '}']), r'\sin x+\frac{1}{2}');
      expect(latexFromSymbols([r'\alpha', r'\beta']), r'\alpha\beta');
    });

    test('unbalanced braces are mended', () {
      expect(balanceBraces(['x', '^', '{', '2']), ['x', '^', '{', '2', '}']);
      expect(balanceBraces(['x', '}', '2']), ['x', '2']);
    });

    test('every symbol the model knows can be drawn', () {
      for (final s in mathVocab.skip(3)) {
        final latex = switch (s) {
          r'\frac' => r'\frac{a}{b}',
          r'\sqrt' => r'\sqrt{a}',
          r'\limits' => r'\lim\limits_{x}',
          '^' || '_' => 'x${s}2',
          '{' || '}' => '{x}',
          r'\prime' => r"x^{\prime}",
          _ => 'a$s b',
        };
        expect(isDrawable(latex), isTrue, reason: latex);
      }
    });
  });
}
