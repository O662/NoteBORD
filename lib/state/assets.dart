import 'dart:ui' as ui;

import 'package:cryptography/dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Image files in a notebook's `assets/` folder, and their decoded pictures.

typedef ImageDecoder = Future<ui.Image> Function(Uint8List bytes);

/// Decodes an image file. Throws if the bytes aren't an image.
Future<ui.Image> decodeImageBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// How image files become pictures. Tests supply their own.
final imageDecoderProvider = Provider<ImageDecoder>((ref) => decodeImageBytes);

/// `png`, `jpg`, `gif`, `webp` or `bmp`, told from the file's first bytes
/// (`img` for anything else).
String imageExtension(Uint8List b) {
  bool starts(List<int> magic, [int at = 0]) {
    if (b.length < at + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (b[at + i] != magic[i]) return false;
    }
    return true;
  }

  if (starts(const [0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (starts(const [0xFF, 0xD8])) return 'jpg';
  if (starts(const [0x47, 0x49, 0x46])) return 'gif';
  if (starts(const [0x52, 0x49, 0x46, 0x46]) && starts(const [0x57, 0x45, 0x42, 0x50], 8)) return 'webp';
  if (starts(const [0x42, 0x4D])) return 'bmp';
  return 'img';
}

/// The content-addressed file name for an image: `<sha256>.<ext>`.
String assetNameFor(Uint8List bytes) {
  final hash = const DartSha256().hashSync(bytes).bytes;
  final hex = [for (final v in hash) v.toRadixString(16).padLeft(2, '0')].join();
  return '$hex.${imageExtension(bytes)}';
}

/// Every `asset` named anywhere in an item's JSON (nested items and item
/// types this version doesn't know included).
Iterable<String> assetRefs(Object? json) sync* {
  if (json is Map) {
    for (final e in json.entries) {
      if ((e.key == 'asset') && e.value is String) {
        yield e.value as String;
      } else {
        yield* assetRefs(e.value);
      }
    }
  } else if (json is List) {
    for (final v in json) {
      yield* assetRefs(v);
    }
  }
}

/// The decoded images of one open notebook, by asset name. A picture that
/// isn't loaded yet is read and decoded in the background; [onLoaded] says
/// when it can be drawn.
class NotebookImages {
  NotebookImages({required this.read, required this.decode, required this.onLoaded});

  /// The file's bytes, or null if it's missing or still locked.
  final Future<Uint8List?> Function(String asset) read;
  final ImageDecoder decode;
  final void Function(String asset) onLoaded;

  final _images = <String, ui.Image>{};
  final _loading = <String>{};
  final _missing = <String>{};
  bool _disposed = false;

  ui.Image? lookup(String asset) {
    final image = _images[asset];
    if (image != null || _disposed) return image;
    if (!_missing.contains(asset) && _loading.add(asset)) _load(asset);
    return null;
  }

  Future<void> _load(String asset) async {
    ui.Image? image;
    try {
      final bytes = await read(asset);
      if (bytes != null) image = await decode(bytes);
    } on Object catch (e) {
      debugPrint('Could not load image $asset: $e');
    }
    _loading.remove(asset);
    if (_disposed) {
      image?.dispose();
    } else if (image == null) {
      _missing.add(asset);
    } else {
      put(asset, image);
      onLoaded(asset);
    }
  }

  /// Keeps an image that was just decoded (a new picture on the page).
  void put(String asset, ui.Image image) {
    if (_disposed || identical(_images[asset], image)) return;
    _images[asset]?.dispose();
    _images[asset] = image;
    _missing.remove(asset);
  }

  /// After an unlock: files that couldn't be read may open now.
  void retryMissing() => _missing.clear();

  /// Forgets pictures that belong to pages that were just locked.
  void evict(Iterable<String> assets) {
    for (final a in assets) {
      _images.remove(a)?.dispose();
    }
  }

  void dispose() {
    _disposed = true;
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
  }
}
