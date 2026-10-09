import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../board/model.dart' show OfficeItem;
import '../canvas/office_cards.dart' show OfficeSource;
import '../office/office_model.dart';
import '../office/office_reader.dart';
import '../office/office_render.dart';
import 'assets.dart';
import 'notebook.dart';

// The Word, PowerPoint and Excel files of an open notebook, read for their
// cards on the board; opening a file in its own app, and bringing back what
// is saved there.

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

/// A file handed to another app, watched for the saves that app makes.
abstract class OpenedFile {
  /// The file as saved since the last time this was asked (and not being
  /// written right now), or null if it hasn't changed.
  Future<Uint8List?> changes();

  /// Stops watching and deletes the copy.
  void close();
}

/// Opens a file in the app the tablet uses for it. Tests supply their own.
abstract class FileOpener {
  /// Opens a copy of [bytes] that the app may save changes to. Null when no
  /// app could open it.
  Future<OpenedFile?> open(String name, Uint8List bytes, String mime);
}

class DeviceFileOpener implements FileOpener {
  const DeviceFileOpener();

  static const _channel = MethodChannel('endless/files');

  /// The folders of files still being watched.
  static final _watched = <String>{};

  @override
  Future<OpenedFile?> open(String name, Uint8List bytes, String mime) async {
    // A folder of its own for each file opened; folders of files nothing
    // watches any more go, so copies don't pile up.
    final base = Directory(p.join((await getTemporaryDirectory()).path, 'open'));
    if (base.existsSync()) {
      for (final d in base.listSync()) {
        if (!_watched.contains(d.path)) await d.delete(recursive: true);
      }
    }
    final dir = Directory(p.join(base.path, '${DateTime.now().microsecondsSinceEpoch}'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, _safeName(name)));
    await file.writeAsBytes(bytes, flush: true);
    final seen = await file.stat();
    final bool opened;
    if (Platform.isAndroid) {
      // With permission to write, so the app can save back to it.
      opened = await _channel.invokeMethod<bool>('open', {'path': file.path, 'mime': mime}) ?? false;
    } else {
      opened = await launchUrl(Uri.file(file.path));
    }
    if (!opened) {
      await dir.delete(recursive: true);
      return null;
    }
    _watched.add(dir.path);
    return _DeviceOpenedFile(dir, file, seen, assetNameFor(bytes));
  }

  static String _safeName(String name) {
    final clean = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '-').trim();
    return clean.isEmpty || clean.startsWith('.') ? 'file$clean' : clean;
  }
}

class _DeviceOpenedFile implements OpenedFile {
  _DeviceOpenedFile(this.dir, this.file, this._seen, this._hash);

  final Directory dir;
  final File file;
  FileStat _seen;
  String _hash;

  @override
  Future<Uint8List?> changes() async {
    try {
      if (!file.existsSync()) return null;
      final stat = await file.stat();
      if (stat.modified == _seen.modified && stat.size == _seen.size) return null;
      // Written in the last second: the app may still be saving.
      if (DateTime.now().difference(stat.modified) < const Duration(seconds: 1)) return null;
      _seen = stat;
      final bytes = await file.readAsBytes();
      final hash = assetNameFor(bytes);
      if (hash == _hash) return null;
      _hash = hash;
      return bytes;
    } on Object catch (e) {
      // Locked by the app that has it open, for now.
      debugPrint('Could not read ${file.path}: $e');
      return null;
    }
  }

  @override
  void close() {
    DeviceFileOpener._watched.remove(dir.path);
    try {
      dir.deleteSync(recursive: true);
    } on Object {
      // Still open in the other app; it goes with the next file opened.
    }
  }
}

final fileOpenerProvider = Provider<FileOpener>((ref) => const DeviceFileOpener());

/// A file opened from a card, whose saves update that card.
class OfficeEdit {
  OfficeEdit({required this.notebookId, required this.pageId, required this.itemId, required this.file, this.onUpdated});

  final String notebookId;
  final String pageId;
  final String itemId;
  final OpenedFile file;

  /// Hears about each update (to say so on the screen that opened it).
  final void Function(OfficeUpdate update)? onUpdated;
}

/// How often files opened from cards are checked for saves while Endless is
/// in front (null: only when Endless comes back to the front). Tests check
/// by hand.
final officeEditPollProvider = Provider<Duration?>((ref) => const Duration(seconds: 2));

final officeEditsProvider = Provider<OfficeEdits>((ref) {
  final edits = OfficeEdits(ref, poll: ref.read(officeEditPollProvider));
  ref.onDispose(edits.dispose);
  return edits;
});

/// Watches the files opened from cards in their own apps: when one is
/// saved there, its card shows the new version (one undo step). A notebook
/// that isn't open gets its update when it's opened again and checked.
class OfficeEdits with WidgetsBindingObserver {
  OfficeEdits(this.ref, {this.poll}) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Ref ref;
  final Duration? poll;
  final _edits = <OfficeEdit>[];
  Timer? _timer;
  bool _checking = false;
  bool _inFront = true;

  /// What's being watched, for tests.
  List<OfficeEdit> get watching => List.unmodifiable(_edits);

  /// Watches [edit] (instead of an earlier open of the same card).
  void watch(OfficeEdit edit) {
    for (final e in _edits.where((e) => e.itemId == edit.itemId).toList()) {
      _drop(e);
    }
    _edits.add(edit);
    _schedule();
  }

  void _drop(OfficeEdit e) {
    _edits.remove(e);
    e.file.close();
    _schedule();
  }

  void _schedule() {
    final every = poll;
    if (every == null || _edits.isEmpty || !_inFront) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(every, (_) => check());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inFront = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    _schedule();
    if (state == AppLifecycleState.resumed) check();
  }

  /// Looks for saves now and updates their cards.
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      for (final e in _edits.toList()) {
        if (!ref.exists(notebookProvider(e.notebookId))) continue;
        final nb = ref.read(notebookProvider(e.notebookId));
        final i = nb.indexOf(e.pageId);
        if (i < 0 || nb.pages[i][e.itemId] is! OfficeItem) {
          // The card (or its page) is gone.
          _drop(e);
          continue;
        }
        final bytes = await e.file.changes();
        if (bytes == null || !ref.exists(notebookProvider(e.notebookId))) continue;
        try {
          final update = await ref.read(notebookProvider(e.notebookId).notifier).updateOffice(e.pageId, e.itemId, bytes);
          if (update != null) e.onUpdated?.call(update);
        } on Object catch (err) {
          // Not a file the board can show (yet): the next save is tried.
          debugPrint('Could not update from ${e.itemId}: $err');
        }
      }
    } finally {
      _checking = false;
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    for (final e in _edits) {
      e.file.close();
    }
    _edits.clear();
  }
}
