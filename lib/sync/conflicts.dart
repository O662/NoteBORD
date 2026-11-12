import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/model.dart' show Json;
import '../board/store.dart';
import '../state/settings.dart' show boardStoreProvider;

// Pages to check (Update 04, Conflict.png). Sync merges a page changed on
// two devices at once, item by item, and never stops for it. When the
// other device's changes to it are older than [ConflictRule.heldBack] by
// the time they arrive (it was offline while this tablet was written on),
// both sides are kept in version history and the page is put on this list,
// so the student can check it: keep the merge, one side, or both as pages.
// The list is this tablet's (`sync/conflicts` beside the sync state).

/// A page changed on this tablet and on another device while one was
/// offline.
@immutable
class PageConflict {
  const PageConflict({
    required this.notebookId,
    required this.pageId,
    required this.device,
    required this.theirsAt,
    required this.oursAt,
    required this.ours,
    required this.theirs,
  });

  final String notebookId;
  final String pageId;

  /// The other device's name ("Kim’s phone").
  final String device;

  /// When the other device last changed the page, and when this one did.
  final DateTime theirsAt;
  final DateTime oursAt;

  /// The two versions kept in version history (their file names).
  final String ours;
  final String theirs;

  Json toJson() => {
        'notebook': notebookId,
        'page': pageId,
        'device': device,
        'theirsAt': theirsAt.toUtc().toIso8601String(),
        'oursAt': oursAt.toUtc().toIso8601String(),
        'ours': ours,
        'theirs': theirs,
      };

  static PageConflict? fromJson(Object? j) {
    if (j is! Map) return null;
    final theirsAt = DateTime.tryParse('${j['theirsAt']}'), oursAt = DateTime.tryParse('${j['oursAt']}');
    if (j['notebook'] is! String || j['page'] is! String || theirsAt == null || oursAt == null) return null;
    if (j['ours'] is! String || j['theirs'] is! String) return null;
    return PageConflict(
      notebookId: j['notebook'] as String,
      pageId: j['page'] as String,
      device: j['device'] as String? ?? 'another device',
      theirsAt: theirsAt,
      oursAt: oursAt,
      ours: j['ours'] as String,
      theirs: j['theirs'] as String,
    );
  }
}

abstract final class ConflictRule {
  /// Changes from another device this much older than when they arrive
  /// were held back (it was offline). Two devices both online get each
  /// other's changes within seconds and just merge, quietly.
  static const heldBack = Duration(minutes: 1);
}

final conflictsProvider = NotifierProvider<ConflictsNotifier, List<PageConflict>>(ConflictsNotifier.new);

class ConflictsNotifier extends Notifier<List<PageConflict>> {
  static const file = 'conflicts';

  late BoardStore _store;
  Future<void>? _loading;

  @override
  List<PageConflict> build() {
    _store = ref.read(boardStoreProvider);
    _loading = _load();
    return const [];
  }

  Future<void> _load() async {
    final j = await _store.loadSyncFile(file);
    final list = [
      for (final e in (j?['pages'] as List?) ?? const []) ?PageConflict.fromJson(e),
    ];
    if (ref.mounted && list.isNotEmpty) state = [...list, ...state];
  }

  Future<void> _save() => _store.saveSyncFile(file, {
        'version': 1,
        'pages': [for (final c in state) c.toJson()],
      });

  /// Waits for the list saved before to be read.
  Future<void> get ready => _loading ?? Future.value();

  /// [notebookId]'s pages to check, in page order of [pageIds] if given.
  List<PageConflict> of(String notebookId, [List<String>? pageIds]) {
    final out = [for (final c in state) if (c.notebookId == notebookId) c];
    if (pageIds != null) out.sort((a, b) => pageIds.indexOf(a.pageId).compareTo(pageIds.indexOf(b.pageId)));
    return out;
  }

  /// A page to check (a newer one for the same page replaces it).
  Future<void> add(PageConflict c) async {
    await ready;
    state = [
      for (final x in state)
        if (x.notebookId != c.notebookId || x.pageId != c.pageId) x,
      c,
    ];
    await _save();
  }

  /// Checked: off the list.
  Future<void> resolve(String notebookId, String pageId) async {
    await ready;
    state = [
      for (final x in state)
        if (x.notebookId != notebookId || x.pageId != pageId) x,
    ];
    await _save();
  }

  /// Notebook [id] is gone (or one of its pages): its entries go too.
  Future<void> forget(String notebookId, {Set<String>? keepPages}) async {
    await ready;
    final before = state.length;
    state = [
      for (final x in state)
        if (x.notebookId != notebookId || (keepPages != null && keepPages.contains(x.pageId))) x,
    ];
    if (state.length != before) await _save();
  }
}
