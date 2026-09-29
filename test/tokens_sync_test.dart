import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// tool/ and design/tokens.json are kept out of git, so this check runs the
// generator as a separate process (rather than importing it) and skips on
// clones that don't have them.
final _hasGenerator = File('tool/gen_tokens.dart').existsSync() && File('design/tokens.json').existsSync();

void main() {
  test(
    'lib/theme/tokens.g.dart is generated from design/tokens.json',
    () async {
      final result = await Process.run('dart', ['run', 'tool/gen_tokens.dart', '--check'], runInShell: true);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    },
    skip: _hasGenerator ? false : 'tool/gen_tokens.dart or design/tokens.json is not in this checkout',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
