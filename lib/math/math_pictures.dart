import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.g.dart' show FontFamilies;

// Math on the page is drawn like everything else on it: by the canvas's
// painter, in z-order with the ink, in thumbnails, the map and exported
// PDFs. flutter_math_fork typesets with widgets, so each formula is laid out
// once off screen, at [mathReferenceSize] in black, and kept as a vector
// picture (crisp at any zoom) that the painter scales and colors.

/// Fonts for math symbols in ordinary text (keys, the keyboard's line, the
/// formula library): Newsreader and Figtree have no Greek, ∑ or ∫, and the
/// typesetter's own KaTeX fonts, bundled with the app, have them all.
const mathFontFallback = <String>[
  'packages/flutter_math_fork/KaTeX_Main',
  'packages/flutter_math_fork/KaTeX_Math',
  'packages/flutter_math_fork/KaTeX_AMS',
  'packages/flutter_math_fork/KaTeX_Size1',
];

/// The size math is typeset at; items scale it to their own size.
const mathReferenceSize = 40.0;

/// A formula, typeset.
class MathPicture {
  MathPicture(this.picture, this.size);

  /// Black on transparent, [size] at [mathReferenceSize].
  final ui.Picture picture;
  final Size size;
}

/// Typeset math for the painter.
abstract interface class MathSource {
  /// The formula typeset, or null while it's being typeset (or when it
  /// can't be).
  MathPicture? picture(String latex);
}

/// Typesets one formula. Swapped out in widget tests, where the
/// typesetter's asynchronous pieces never settle.
typedef Typesetter = Future<MathPicture?> Function(String latex);

/// Every formula typeset so far, app-wide. Listeners hear when one is
/// ready to draw.
class MathPictures extends ChangeNotifier implements MathSource {
  MathPictures({Typesetter? typeset}) : _typeset = typeset ?? typesetOffscreen;

  final Typesetter _typeset;
  final _done = <String, MathPicture?>{};
  final _loading = <String, Future<MathPicture?>>{};
  bool _disposed = false;

  @override
  MathPicture? picture(String latex) {
    if (_done.containsKey(latex)) return _done[latex];
    load(latex);
    return null;
  }

  /// The formula typeset (now if it isn't yet), or null if it can't be.
  Future<MathPicture?> load(String latex) {
    if (_done.containsKey(latex)) return Future.value(_done[latex]);
    return _loading[latex] ??= () async {
      MathPicture? done;
      try {
        done = await _typeset(latex);
      } on Object catch (e) {
        debugPrint('Could not typeset $latex: $e');
      }
      _loading.remove(latex);
      if (_disposed) return null;
      _done[latex] = done;
      notifyListeners();
      return done;
    }();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final p in _done.values) {
      p?.picture.dispose();
    }
    super.dispose();
  }
}

final mathPicturesProvider = Provider<MathPictures>((ref) {
  final pictures = MathPictures();
  ref.onDispose(pictures.dispose);
  return pictures;
});

/// The widget math is typeset with, here and in the preview.
Widget mathWidget(String latex, {double size = mathReferenceSize, Color color = const Color(0xFF000000)}) => Math.tex(
      latex,
      mathStyle: MathStyle.display,
      textStyle: TextStyle(fontSize: size, color: color, fontFamily: FontFamilies.serif),
      onErrorFallback: (e) => Text(latex, style: TextStyle(fontSize: size * 0.6, color: color)),
    );

/// Typesets [latex] in a private widget tree, waits for its drawn pieces
/// (√ signs and stretchy brackets are SVG, read asynchronously), and
/// records what it paints.
Future<MathPicture?> typesetOffscreen(String latex) async {
  final root = _Root();
  final pipeline = PipelineOwner()..rootNode = root;
  final build = BuildOwner(focusManager: FocusManager());
  root.scheduleInitialLayout();
  final element = RenderObjectToWidgetAdapter<RenderBox>(
    container: root,
    child: MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(textDirection: TextDirection.ltr, child: mathWidget(latex)),
    ),
  ).attachToRenderTree(build);
  try {
    // Up to 3 s for the pieces to arrive.
    for (var round = 0; round < 150; round++) {
      build
        ..buildScope(element)
        ..finalizeTree();
      pipeline.flushLayout();
      if (!_waiting(element)) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (_waiting(element)) return null;
    final size = root.size;
    if (size.isEmpty) return null;
    pipeline.flushCompositingBits();
    final layer = OffsetLayer();
    final context = _Recorder(layer, Offset.zero & size);
    root.paint(context, Offset.zero);
    context.finish();
    final recorder = ui.PictureRecorder();
    _draw(ui.Canvas(recorder), layer);
    final picture = recorder.endRecording();
    layer.dispose();
    return MathPicture(picture, size);
  } finally {
    element.update(RenderObjectToWidgetAdapter<RenderBox>(container: root));
    build.finalizeTree();
    root.dispose();
  }
}

/// Whether an SVG piece hasn't been read yet: flutter_svg shows a
/// placeholder until its picture arrives.
bool _waiting(Element root) {
  var graphics = 0, ready = 0;
  void visit(Element e) {
    final name = e.widget.runtimeType.toString();
    if (name == 'VectorGraphic') graphics++;
    if (name.startsWith('_Raw') && name.endsWith('VectorGraphicWidget')) ready++;
    e.visitChildren(visit);
  }

  visit(root);
  return ready < graphics;
}

/// Replays a painted layer tree onto [canvas].
void _draw(ui.Canvas canvas, Layer layer) {
  void children(ContainerLayer c) {
    for (var child = c.firstChild; child != null; child = child.nextSibling) {
      _draw(canvas, child);
    }
  }

  switch (layer) {
    case PictureLayer l:
      if (l.picture case final picture?) canvas.drawPicture(picture);
    case ClipRectLayer l:
      canvas.save();
      if (l.clipRect case final clip?) canvas.clipRect(clip);
      children(l);
      canvas.restore();
    case OpacityLayer l:
      canvas.saveLayer(null, Paint()..color = Color.fromARGB(l.alpha ?? 255, 0, 0, 0));
      canvas.translate(l.offset.dx, l.offset.dy);
      children(l);
      canvas.restore();
    case TransformLayer l:
      canvas.save();
      canvas.translate(l.offset.dx, l.offset.dy);
      if (l.transform case final m?) canvas.transform(m.storage);
      children(l);
      canvas.restore();
    case OffsetLayer l:
      canvas.save();
      canvas.translate(l.offset.dx, l.offset.dy);
      children(l);
      canvas.restore();
    case ContainerLayer l:
      children(l);
    default:
      break;
  }
}

/// The root of the private tree (as a RenderView is of the app's): lays
/// its child out at its own size, however big.
class _Root extends RenderObject with RenderObjectWithChildMixin<RenderBox> {
  Size size = Size.zero;

  @override
  void performLayout() {
    child?.layout(const BoxConstraints(), parentUsesSize: true);
    size = child?.size ?? Size.zero;
  }

  @override
  void performResize() {}

  @override
  void debugAssertDoesMeetConstraints() {}

  @override
  Rect get paintBounds => Offset.zero & size;

  @override
  Rect get semanticBounds => paintBounds;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child case final child?) context.paintChild(child, offset);
  }
}

class _Recorder extends PaintingContext {
  _Recorder(super.containerLayer, super.estimatedBounds);

  void finish() => stopRecordingIfNeeded();
}
