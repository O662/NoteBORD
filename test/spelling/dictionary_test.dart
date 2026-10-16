import 'package:endless/spelling/dictionary.dart';
import 'package:flutter_test/flutter_test.dart';

import 'spelling_fixtures.dart';

void main() {
  setUpAll(loadSpelling);

  test('conserve: mostly a verb, with its pronunciation, examples, similar words and opposites', () {
    final e = testDictionary.lookup('conserve')!;
    expect(e.word, 'conserve');
    expect(e.say, 'kən-SURV');
    expect(e.groups.map((g) => g.$1), [WordClass.verb, WordClass.noun]);
    final verbs = e.groups.first.$2;
    expect(verbs, hasLength(4));
    expect(verbs.first.definition, 'keep constant through physical or chemical reactions or evolutionary change');
    expect(verbs.first.example, 'Energy is conserved in this process');
    // The example that uses the word is picked over the first one.
    expect(verbs[1].example, 'children must be taught to conserve our national heritage');
    expect(e.similar, containsAll(['preserve', 'maintain', 'economize']));
    expect(e.similar, isNot(contains('conserve')));
    expect(e.similar, isNot(contains('conserves')));
    expect(e.similar, isNot(contains('preserves')));
    expect(e.opposites, ['waste']);
  });

  test('forms of a word find it', () {
    expect(testDictionary.lookup('conserving')!.word, 'conserve');
    expect(testDictionary.lookup('Collisions')!.word, 'collision');
    expect(testDictionary.lookup('geese')!.word, 'goose');
    expect(testDictionary.lookup('ran')!.word, 'run');
    expect(testDictionary.lookup('hugged')!.word, 'hug');
    expect(testDictionary.lookup('  “Momentum,” ')!.word, 'momentum');
    expect(testDictionary.lookup('kinetic energy')!.word, 'kinetic energy');
  });

  test('pronunciations are respelled', () {
    expect(testDictionary.lookup('momentum')!.say, 'moh-MEN-təm');
    expect(testDictionary.lookup('collision')!.say, 'kə-LIZH-ən');
    expect(testDictionary.lookup('bite')!.say, 'byte');
  });

  test('not found', () {
    expect(testDictionary.lookup('momentem'), isNull);
    expect(testDictionary.lookup(''), isNull);
    expect(testDictionary.lookup('!!'), isNull);
  });

  test('normalizeLookup', () {
    expect(normalizeLookup('  Don’t  '), "don't");
    expect(normalizeLookup('kinetic   energy'), 'kinetic energy');
    expect(normalizeLookup('(word),'), 'word');
  });
}
