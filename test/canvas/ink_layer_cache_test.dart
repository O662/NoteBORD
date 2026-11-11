import 'dart:ui' as ui;

import 'package:endless/canvas/canvas_view.dart';
import 'package:endless/canvas/ink_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ui.Picture _ink() {
  final r = ui.PictureRecorder();
  Canvas(r).drawCircle(const Offset(100, 100), 20, Paint()..color = const Color(0xFF000000));
  return r.endRecording();
}

/// Paints [cache] once onto a throwaway canvas.
void _paint(InkLayerCache cache, CanvasView vp, ui.Picture picture) {
  final r = ui.PictureRecorder();
  cache.paint(Canvas(r), const Size(400, 300), vp, picture, 2);
  r.endRecording().dispose();
}

void main() {
  test('the ink is drawn as an image once the view holds still', () {
    final cache = InkLayerCache();
    final vp = CanvasView();
    final picture = _ink();

    _paint(cache, vp, picture);
    expect(cache.usedImage, isFalse, reason: 'first paint: the view may still be moving');
    _paint(cache, vp, picture);
    expect(cache.usedImage, isTrue, reason: 'same view: drawn from the image');
    _paint(cache, vp, picture);
    expect(cache.usedImage, isTrue);

    // Panning: drawn directly while the view moves…
    vp.panBy(const Offset(10, 0));
    _paint(cache, vp, picture);
    expect(cache.usedImage, isFalse);
    vp.panBy(const Offset(10, 0));
    _paint(cache, vp, picture);
    expect(cache.usedImage, isFalse);
    // …and from a new image once it stops.
    _paint(cache, vp, picture);
    expect(cache.usedImage, isTrue);

    // New ink under a still view (a stroke went down): a new image at once.
    final more = _ink();
    _paint(cache, vp, more);
    expect(cache.usedImage, isTrue);

    cache.dispose();
    picture.dispose();
    more.dispose();
  });

  test('asks to paint again once the view has settled', () async {
    final cache = InkLayerCache();
    final vp = CanvasView();
    final picture = _ink();
    var asked = 0;
    cache.addListener(() => asked++);

    _paint(cache, vp, picture);
    expect(asked, 0);
    await Future<void>.delayed(InkLayerCache.settle + const Duration(milliseconds: 50));
    expect(asked, 1);

    cache.dispose();
    picture.dispose();
  });
}
