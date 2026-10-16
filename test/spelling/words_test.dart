import 'package:endless/spelling/words.dart';
import 'package:flutter_test/flutter_test.dart';

import 'spelling_fixtures.dart';

void main() {
  setUpAll(loadSpelling);

  group('the bundled word list', () {
    test('has common words, inflections, names and contractions, case-insensitively', () {
      expect(testWords.length, greaterThan(150000));
      for (final w in ['the', 'momentum', 'momenta', 'conserved', 'collision', 'Sunday', 'sunday', 'Maya', "don't", 'photosynthesis']) {
        expect(testWords.contains(w), isTrue, reason: w);
      }
      for (final w in ['momentem', 'sistem', 'colision', 'recieve', 'teh']) {
        expect(testWords.contains(w), isFalse, reason: w);
      }
      expect(testWords.levelOf('the'), 10);
      expect(testWords.levelOf('momenta')!, greaterThan(testWords.levelOf('momentum')!));
    });

    test('suggests corrections like Spell.png’s, keeping capitals', () {
      expect(testWords.suggest('Momentem').take(2), ['Momentum', 'Moment']);
      expect(testWords.suggest('sistem').take(2), ['system', 'sister']);
      expect(testWords.suggest('colision').take(2), ['collision', 'collusion']);
      expect(testWords.suggest('Recieve').take(2), ['Receive', 'Relieve']);
      expect(testWords.suggest('RECIEVE').first, 'RECEIVE');
      expect(testWords.suggest('definately').first, 'definitely');
      expect(testWords.suggest('accomodate').first, 'accommodate');
      expect(testWords.suggest('photosynthisis'), ['photosynthesis']);
      // Names keep their capital.
      expect(testWords.suggest('sundday').first, 'Sunday');
      expect(testWords.suggest('xqzvbw'), isEmpty);
    });

    test('other readings of handwriting come first when they are words', () {
      expect(testWords.suggest('sistem', hints: ['sisten', 'sister']).first, 'sister');
    });
  });

  test('a small list reads levels and capitals', () {
    final words = WordList.parse('#10\nthe\nMarch\n#35\nmarch\nNASA\n');
    expect(words.levelOf('THE'), 10);
    // A lower-case spelling wins over a capitalized one.
    expect(words.writtenAs('march'), 'march');
    expect(words.levelOf('march'), 10);
    expect(words.writtenAs('nasa'), 'NASA');
  });

  test('spelling distance: vowels, doubled letters and swaps cost less', () {
    expect(spellingDistance('sistem', 'system'), closeTo(0.7, 1e-9));
    expect(spellingDistance('colision', 'collision'), closeTo(0.6, 1e-9));
    expect(spellingDistance('recieve', 'receive'), closeTo(0.8, 1e-9));
    expect(spellingDistance('cat', 'cut'), closeTo(0.7, 1e-9));
    expect(spellingDistance('cat', 'bat'), 1);
    expect(spellingDistance('kitten', 'sitting'), greaterThan(maxSuggestDistance));
  });

  test('matchCase', () {
    expect(matchCase('momentum', 'Momentem'), 'Momentum');
    expect(matchCase('receive', 'RECIEVE'), 'RECEIVE');
    expect(matchCase('Sunday', 'sundy'), 'Sunday');
    expect(matchCase('system', 'sistem'), 'system');
  });
}
