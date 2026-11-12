import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/codec.dart' show decodeItem;
import '../board/model.dart';
import '../board/store.dart';
import '../library/library.dart' show clockProvider;
import 'settings.dart' show boardStoreProvider;

// Crash recovery (Update 04, Recovery.png). Every stroke is also written to
// an append-only journal as it's finished (`journal/<notebook>.jsonl`, one
// JSON line each), flushed about every 2 s and when the app is paused, and
// cleared once its pages are saved. Pages are saved within half a second of
// the pen lifting anyway; the journal covers a crash in between, or one in
// the middle of a save. When a notebook opens and its journal has strokes
// its pages don't, they're put back ("We brought back your last strokes").
//
// Strokes on a page with a password are never journaled (they'd be in the
// clear on the disk).

/// A stroke from the journal.
@immutable
class JournalEntry {
  const JournalEntry(this.pageId, this.item, this.at);

  final String pageId;
  final Item item;
  final DateTime at;
}

class StrokeJournal {
  StrokeJournal(this._store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const flushEvery = Duration(seconds: 2);

  final BoardStore _store;
  final DateTime Function() _clock;
  final _pending = <String, StringBuffer>{};
  DateTime? _flushedAt;
  Future<void> _writing = Future.value();

  /// Notes [item] (just finished on page [pageId] of notebook [notebookId]).
  /// What's waiting is written when [flushEvery] has passed since the last
  /// write, when a save starts, and when the app is paused (no timer: the
  /// save comes within half a second of the pen lifting anyway).
  void add(String notebookId, String pageId, Item item) {
    final now = _clock();
    final line = jsonEncode({'t': now.toUtc().millisecondsSinceEpoch, 'page': pageId, 'item': jsonDecode(item.encoded)});
    (_pending[notebookId] ??= StringBuffer()).writeln(line);
    final last = _flushedAt;
    if (last == null || now.difference(last) >= flushEvery) unawaited(flush());
  }

  /// Writes what's waiting.
  Future<void> flush() {
    _flushedAt = _clock();
    final out = {for (final e in _pending.entries) e.key: e.value.toString()};
    _pending.clear();
    for (final e in out.entries) {
      if (e.value.isEmpty) continue;
      _writing = _writing.then((_) => _store.appendJournal(e.key, e.value)).catchError((Object e) {
        debugPrint('Journal write failed: $e');
      });
    }
    return _writing;
  }

  /// Notebook [notebookId]'s pages are saved: its journal isn't needed.
  Future<void> clear(String notebookId) {
    _pending.remove(notebookId);
    return _writing = _writing.then((_) => _store.clearJournal(notebookId)).catchError((Object _) {});
  }

  /// The strokes in [text]; a line cut off by a crash is skipped.
  static List<JournalEntry> parse(String text) {
    final out = <JournalEntry>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      try {
        final j = jsonDecode(line) as Map<String, dynamic>;
        final item = decodeItem((j['item'] as Map).cast<String, dynamic>());
        out.add(JournalEntry(j['page'] as String, item, DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt(), isUtc: true)));
      } on Object {
        continue;
      }
    }
    return out;
  }

  Future<List<JournalEntry>> read(String notebookId) async {
    await _writing;
    final text = await _store.loadJournal(notebookId);
    return text == null ? const [] : parse(text);
  }

  final _stashed = <String, List<JournalEntry>>{};

  /// Read as notebook [notebookId] loads, taken when it opens.
  void stash(String notebookId, List<JournalEntry> entries) => _stashed[notebookId] = entries;
  List<JournalEntry> take(String notebookId) => _stashed.remove(notebookId) ?? const [];
}

/// The notebook whose last strokes may not have been saved (its journal
/// isn't empty: Endless closed unexpectedly), found as the app starts; it
/// opens first so they come back.
final initialRecoveryProvider = Provider<String?>((ref) => null);

final strokeJournalProvider = Provider<StrokeJournal>((ref) {
  final journal = StrokeJournal(ref.read(boardStoreProvider), clock: ref.read(clockProvider));
  // Flushed when the app is paused (or anything short of in front). Not
  // without a Flutter binding (plain tests).
  AppLifecycleListener? life;
  try {
    WidgetsBinding.instance;
    life = AppLifecycleListener(onInactive: journal.flush, onHide: journal.flush, onPause: journal.flush);
  } on Object {
    life = null;
  }
  ref.onDispose(() {
    life?.dispose();
    journal.flush();
  });
  return journal;
});

/// What was brought back when a notebook opened (Recovery.png): the
/// strokes by page, when the app closed, and whether it's been undone.
@immutable
class Recovery {
  const Recovery({required this.notebookId, required this.items, required this.closedAt, this.undone = false});

  final String notebookId;
  final Map<String, List<Item>> items;
  final DateTime closedAt;
  final bool undone;

  int get strokes => items.values.fold(0, (n, l) => n + l.length);

  /// Lines of writing: the strokes grouped by the height they're at.
  int get lines {
    var n = 0;
    for (final list in items.values) {
      final spans = [for (final i in list) (i.bounds.top, i.bounds.bottom)]..sort((a, b) => a.$1.compareTo(b.$1));
      double? end;
      for (final (top, bottom) in spans) {
        if (end == null || top > end + 8) {
          n++;
          end = bottom;
        } else if (bottom > end) {
          end = bottom;
        }
      }
    }
    return n;
  }

  Recovery copyWith({bool? undone}) => Recovery(notebookId: notebookId, items: items, closedAt: closedAt, undone: undone ?? this.undone);
}

/// The open notebooks' recoveries, until the card is dismissed.
final recoveryProvider = NotifierProvider<RecoveryNotifier, Map<String, Recovery>>(RecoveryNotifier.new);

class RecoveryNotifier extends Notifier<Map<String, Recovery>> {
  @override
  Map<String, Recovery> build() => const {};

  void set(Recovery r) => state = {...state, r.notebookId: r};

  void dismiss(String notebookId) => state = {
        for (final e in state.entries)
          if (e.key != notebookId) e.key: e.value,
      };
}
