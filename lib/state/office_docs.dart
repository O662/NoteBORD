import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../canvas/office_cards.dart' show OfficeSource;
import '../office/office_model.dart';
import '../office/office_reader.dart';
import '../office/office_render.dart';
import 'assets.dart';

// The Word, PowerPoint and Excel files of an open notebook, read for their
// cards on the board, and opening a file in its own app.

/// Reads an Office file. Tests read on the test's own isolate.
typedef OfficeParser = Future<OfficeDoc> Function(Uint8List bytes, OfficeKind kind);

final officeParserProvider = Provider<OfficeParser>((ref) => readOfficeInBackground);

/// The Office files of one open notebook, by asset name. A file that isn't
/// read yet is read in the background; [onLoaded] says when its card can
/// be drawn (again: pictures inside a file arrive after its text).
class NotebookDocs implements OfficeSource {
  NotebookDocs({required this.read, required this.parse, required this.decode, required this.onLoaded});

  final Future<Uint8List?> Function(String asset) read;
  final OfficeParser parse;
  final ImageDecoder decode;
  final void Function(String asset) onLoaded;

  final _docs = <String, OfficePreview>{};
  final _loading = <String, Future<OfficePreview?>>{};
  final _missing = <String>{};
  bool _disposed = false;

  @override
  OfficePreview? preview(String asset, OfficeKind kind) {
    final doc = _docs[asset];
    if (doc != null || _disposed) return doc;
    if (!_missing.contains(asset)) load(asset, kind);
    return null;
  }

  @override
  bool unreadable(String asset) => _missing.contains(asset);

  /// The file ready to show, read if it isn't yet; null if it can't be.
  Future<OfficePreview?> load(String asset, OfficeKind kind) {
    if (_docs[asset] case final doc?) return Future.value(doc);
    return _loading[asset] ??= _load(asset, kind);
  }

  Future<OfficePreview?> _load(String asset, OfficeKind kind) async {
    OfficePreview? preview;
    try {
      final bytes = await read(asset);
      if (bytes != null) {
        final doc = await parse(bytes, kind);
        if (!_disposed) preview = OfficePreview(doc, bytes, decode: decode);
      }
    } on Object catch (e) {
      debugPrint('Could not read $asset: $e');
    }
    _loading.remove(asset);
    if (_disposed) {
      preview?.dispose();
      return null;
    }
    if (preview == null) {
      _missing.add(asset);
    } else {
      put(asset, preview);
    }
    onLoaded(asset);
    return preview;
  }

  /// Keeps a file that was just read (one just added to the page).
  void put(String asset, OfficePreview preview) {
    if (_disposed) {
      preview.dispose();
      return;
    }
    if (!identical(_docs[asset], preview)) _docs[asset]?.dispose();
    _docs[asset] = preview..onChanged = () => onLoaded(asset);
    _missing.remove(asset);
  }

  /// After an unlock: files that couldn't be read may open now.
  void retryMissing() => _missing.clear();

  /// Forgets files that belong to pages that were just locked.
  void evict(Iterable<String> assets) {
    for (final a in assets) {
      _docs.remove(a)?.dispose();
    }
  }

  void dispose() {
    _disposed = true;
    for (final d in _docs.values) {
      d.dispose();
    }
    _docs.clear();
  }
}

/// Opens a file in the app the tablet uses for it. Tests supply their own.
abstract class FileOpener {
  /// False when no app could open it.
  Future<bool> open(String name, Uint8List bytes, String mime);
}

class DeviceFileOpener implements FileOpener {
  const DeviceFileOpener();

  static const _channel = MethodChannel('endless/files');

  @override
  Future<bool> open(String name, Uint8List bytes, String mime) async {
    // A fresh folder each time, so copies of earlier files don't pile up.
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'open'));
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, _safeName(name)));
    await file.writeAsBytes(bytes, flush: true);
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<bool>('open', {'path': file.path, 'mime': mime}) ?? false;
    }
    return launchUrl(Uri.file(file.path));
  }

  static String _safeName(String name) {
    final clean = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '-').trim();
    return clean.isEmpty || clean.startsWith('.') ? 'file$clean' : clean;
  }
}

final fileOpenerProvider = Provider<FileOpener>((ref) => const DeviceFileOpener());
