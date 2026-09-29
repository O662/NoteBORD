import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/gen_tokens.dart';

void main() {
  test('lib/theme/tokens.g.dart is generated from design/tokens.json', () {
    final json = jsonDecode(File(tokensPath).readAsStringSync()) as Map<String, dynamic>;
    expect(
      File(outputPath).readAsStringSync().replaceAll('\r\n', '\n'),
      renderTokens(json),
      reason: 'Run `dart run tool/gen_tokens.dart`',
    );
  });
}
