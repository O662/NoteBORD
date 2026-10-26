import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/items.dart' show ImageLookup;
import '../../canvas/page_runtime.dart' show paintItem;
import '../../math/math_pictures.dart';
import '../../state/assets.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';

/// Pictures in a notebook's package, for previews drawn outside the
/// notebook (the Remember and Flashcards screens). Repaints listeners as
/// they load.
class PreviewImages extends ChangeNotifier {
  PreviewImages(Future<Uint8List?> Function(String asset) read, ImageDecoder decode) {
    images = NotebookImages(read: read, decode: decode, onLoaded: (_) => notifyListeners());
  }

  late final NotebookImages images;

  ui.Image? lookup(String asset) => images.lookup(asset);

  @override
  void dispose() {
    images.dispose();
    super.dispose();
  }
}

final previewImagesProvider = Provider.autoDispose.family<PreviewImages, String>((ref, notebookId) {
  final store = ref.read(boardStoreProvider);
  final images = PreviewImages((asset) => store.loadAsset(notebookId, asset), ref.read(imageDecoderProvider));
  ref.onDispose(images.dispose);
  return images;
});

/// [items] drawn as on the page, scaled to fit (never more than [maxScale])
/// and placed by [alignment]. Ink is brightened in dark mode, as on the page.
class ItemsPreview extends ConsumerWidget {
  const ItemsPreview({
    super.key,
    required this.items,
    this.images,
    this.notebookId,
    this.maxScale = 2.5,
    this.alignment = Alignment.center,
    this.label,
  });

  final List<Item> items;

  /// The open notebook's pictures; else they're read from [notebookId]'s
  /// package.
  final ImageLookup? images;
  final String? notebookId;
  final double maxScale;
  final Alignment alignment;

  /// What it shows, for screen readers.
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pictures = ref.watch(mathPicturesProvider);
    final nb = notebookId;
    final loader = images == null && nb != null && items.any((i) => i is ImageItem) ? ref.watch(previewImagesProvider(nb)) : null;
    final lookup = images ?? loader?.lookup;
    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ItemsPainter(
            items,
            Theme.of(context).brightness,
            context.colors,
            images: lookup,
            typeset: pictures,
            maxScale: maxScale,
            alignment: alignment,
            repaint: Listenable.merge([pictures, ?loader]),
          ),
        ),
      ),
    );
  }
}

/// Where [items] are on their page, or null if there's nothing to draw.
Rect? itemsBounds(Iterable<Item> items) {
  Rect? r;
  for (final i in items) {
    if (i is FlashcardItem) continue;
    r = r == null ? i.extent : r.expandToInclude(i.extent);
  }
  return r;
}

class _ItemsPainter extends CustomPainter {
  _ItemsPainter(
    this.items,
    this.brightness,
    this.colors, {
    this.images,
    required this.typeset,
    required this.maxScale,
    required this.alignment,
    super.repaint,
  });

  final List<Item> items;
  final Brightness brightness;
  final EndlessColors colors;
  final ImageLookup? images;
  final MathSource typeset;
  final double maxScale;
  final Alignment alignment;

  @override
  void paint(Canvas canvas, Size size) {
    final b = itemsBounds(items);
    if (b == null || size.isEmpty) return;
    final w = math.max(b.width, 1.0), h = math.max(b.height, 1.0);
    final scale = math.min(maxScale, math.min(size.width / w, size.height / h));
    final drawn = Size(w * scale, h * scale);
    final at = alignment.inscribe(drawn, Offset.zero & size).topLeft;
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..scale(scale)
      ..translate(-b.left, -b.top);
    for (final item in items) {
      paintItem(canvas, item, brightness, colors, images: images, math: typeset);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ItemsPainter old) =>
      !identical(old.items, items) || old.brightness != brightness || old.colors != colors || old.images != images;
}
