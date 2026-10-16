import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'board/store.dart';
import 'library/index_db.dart';
import 'spelling/spelling_state.dart';
import 'state/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerLicenses();

  // The design is for tablets in landscape. Phones get their own layout later.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);

  final docs = await getApplicationDocumentsDirectory();
  final root = Directory(p.join(docs.path, 'Endless'));
  await root.create(recursive: true);
  final store = FileBoardStore(root);
  final overrides = await bootstrap(store, index: IndexDb.file(File(p.join(root.path, 'index.sqlite'))));
  // The dictionary is app data, not the user's: it's unpacked outside Endless/.
  final support = await getApplicationSupportDirectory();

  runApp(ProviderScope(
    overrides: [
      ...overrides,
      dictionaryDirProvider.overrideWithValue(Directory(p.join(support.path, 'dictionary'))),
    ],
    child: const EndlessApp(),
  ));
}

void _registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in [('Figtree', 'figtree'), ('Newsreader', 'newsreader'), ('Caveat', 'caveat')]) {
      yield LicenseEntryWithLineBreaks([family], await rootBundle.loadString('assets/fonts/OFL-$file.txt'));
    }
    yield LicenseEntryWithLineBreaks(
      ['Open English WordNet', 'CMU Pronouncing Dictionary', 'SCOWL'],
      await rootBundle.loadString('assets/dictionary/NOTICE.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      ['CoMER handwritten math model'],
      await rootBundle.loadString('assets/math/NOTICE.txt'),
    );
  });
}
