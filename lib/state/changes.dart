import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/store.dart';
import '../sync/versions.dart';
import 'settings.dart';

/// Tells cloud sync that something here changed and should go to the
/// cloud: a notebook ([last] its id) or the library (folders, decks: null).
class LocalChanges extends ChangeNotifier {
  String? last;

  void changed([String? notebookId]) {
    last = notebookId;
    notifyListeners();
  }
}

final localChangesProvider = Provider<LocalChanges>((ref) {
  final c = LocalChanges();
  ref.onDispose(c.dispose);
  return c;
});

/// Earlier versions of pages (version history).
final versionStoreProvider = Provider<VersionStore>((ref) {
  final BoardStore store = ref.read(boardStoreProvider);
  return VersionStore(store);
});
