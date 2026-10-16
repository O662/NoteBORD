import 'dart:async';
import 'dart:ui';

import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/recognition/recognizer.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;

/// A recognizer for tests: each stroke is a word, known by where it starts
/// ([label]). A line reads as its words in pen order, and words with
/// [alts] add runner-up readings with that word swapped.
class FakeRecognizer extends InkRecognizer {
  FakeRecognizer({Set<String>? models, this.downloads = true}) : models = models ?? {'en-US'};

  /// Languages whose model is on the "device".
  final Set<String> models;

  /// Whether a download works (false: offline).
  bool downloads;

  /// Holds downloads until completed, to see the note while it runs.
  Completer<void>? gate;

  /// Holds recognition until completed (something happening meanwhile).
  Completer<void>? reading;

  final _words = <String, String>{};
  final alts = <String, List<String>>{};

  /// What a language reads words as, if not the same everywhere.
  String Function(String word, String language)? translate;

  int recognized = 0;
  int downloaded = 0;
  final contexts = <String>[];
  final languages = <String>[];

  void label(StrokeItem s, String word) => _words[_key(s.pageInk.first.x, s.pageInk.first.y)] = word;

  /// A stroke that starts at [at] reads as [word].
  void labelAt(Offset at, String word) => _words[_key(at.dx, at.dy)] = word;

  static String _key(double x, double y) => '${x.round()},${y.round()}';

  @override
  bool get available => true;

  @override
  Future<bool> hasModel(String language) async => models.contains(language);

  @override
  Future<bool> downloadModel(String language) async {
    downloaded++;
    await gate?.future;
    if (!downloads) return false;
    models.add(language);
    return true;
  }

  @override
  Future<List<String>> recognize(
    List<List<InkSamplePoint>> strokes, {
    required String language,
    String preContext = '',
    Size? area,
  }) async {
    if (!models.contains(language)) throw const RecognitionFailed('no model');
    await reading?.future;
    recognized++;
    contexts.add(preContext);
    languages.add(language);
    final words = [
      for (final s in strokes)
        if (_words[_key(s.first.x, s.first.y)] case final w?) translate?.call(w, language) ?? w,
    ];
    final out = [words.join(' ')];
    for (final (i, w) in words.indexed) {
      for (final a in alts[w] ?? const <String>[]) {
        out.add([...words.take(i), a, ...words.skip(i + 1)].join(' '));
      }
    }
    return out;
  }
}

/// Writes [line] as ink: one zig-zag stroke per word, [height] tall, 14 px
/// wide per letter, 20 px between words, starting at [at]. Each stroke is
/// labelled with its word in [r].
List<StrokeItem> writeLine(
  FakeRecognizer r,
  String line, {
  required Offset at,
  double height = 30,
  Color? color,
  DateTime? time,
  int z = 1,
}) {
  final out = <StrokeItem>[];
  var x = at.dx;
  final t0 = time ?? DateTime.utc(2026, 9, 25, 10);
  for (final (i, word) in line.split(' ').indexed) {
    final w = 14.0 * word.length;
    final n = word.length * 2 + 2;
    final pts = [
      for (var k = 0; k <= n; k++) InkPoint(x + w * k / n, at.dy + (k.isEven ? height : 0), 0.5, k * 10),
    ];
    final s = StrokeItem.fromPagePoints(
      id: newId('it'),
      z: z + i,
      createdAt: t0.add(Duration(seconds: i)),
      tool: InkTool.pen,
      penType: PenType.ballpoint,
      color: color ?? tokens.inkDefaults[0],
      width: 2.5,
      usePressure: true,
      pagePoints: pts,
    );
    r.label(s, word);
    out.add(s);
    x += w + 20;
  }
  return out;
}
