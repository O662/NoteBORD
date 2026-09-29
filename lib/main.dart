import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'board/store.dart';
import 'state/notebook.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();

  // The design is for tablets in landscape. Phones get their own layout later.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);

  final docs = await getApplicationDocumentsDirectory();
  final store = FileBoardStore(Directory(p.join(docs.path, 'Endless')));
  final overrides = await bootstrap(store);

  runApp(ProviderScope(overrides: overrides, child: const EndlessApp()));
}

void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in [('Figtree', 'figtree'), ('Newsreader', 'newsreader'), ('Caveat', 'caveat')]) {
      yield LicenseEntryWithLineBreaks([family], await rootBundle.loadString('assets/fonts/OFL-$file.txt'));
    }
  });
}
