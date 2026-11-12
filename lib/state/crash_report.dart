import 'dart:io';

import '../board/store.dart';

// The anonymous crash report (Update 04, Recovery.png): off by default,
// and when it's ticked it goes through the share sheet (Endless has no
// server to send it to). It never has notes, handwriting, titles or file
// names in it: the last error's type and stack trace (the app's own code),
// the platform, and how many strokes were brought back.

const _file = 'last_error';

/// Notes the error that may stop the app: its type and stack only (an
/// error's message can quote what's in a note).
Future<void> recordError(BoardStore store, Object error, StackTrace? stack, {DateTime? at}) async {
  try {
    await store.saveSyncFile(_file, {
      'at': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'type': error.runtimeType.toString(),
      'stack': _frames(stack),
    });
  } on Object {
    // Nothing more to do while the app is falling over.
  }
}

/// The stack's frames, at most 30, without anything but code locations.
List<String> _frames(StackTrace? stack) => [
      for (final l in (stack?.toString() ?? '').split('\n'))
        if (l.trim().startsWith('#')) l.trim(),
    ].take(30).toList();

/// The report's text.
Future<String> crashReport(BoardStore store, {required DateTime closedAt, required int strokes}) async {
  final last = await store.loadSyncFile(_file);
  final b = StringBuffer()
    ..writeln('Endless crash report (anonymous)')
    ..writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
    ..writeln('Closed unexpectedly: ${closedAt.toUtc().toIso8601String()}')
    ..writeln('Strokes brought back: $strokes');
  if (last != null) {
    b
      ..writeln('Last error: ${last['type']} at ${last['at']}')
      ..writeln('Stack:');
    for (final f in (last['stack'] as List? ?? const [])) {
      b.writeln('  $f');
    }
  } else {
    b.writeln('Last error: none was caught (the system may have closed Endless).');
  }
  b.writeln('No notes, handwriting, titles or file names are in this report.');
  return b.toString();
}
