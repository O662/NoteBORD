import 'dart:convert';

import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;
import 'package:endless/board/codec.dart';
import 'package:endless/board/lock.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/library.dart';
import 'package:endless/state/biometric.dart';
import 'package:endless/state/notebook.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<ProviderContainer> _open(MemoryBoardStore store, String id, {FakeBiometric? biometric}) async {
  final c = ProviderContainer(overrides: await testOverrides(store, biometric: biometric));
  addTearDown(c.dispose);
  c.listen(loadedNotebookProvider(id), (_, _) {});
  await c.read(loadedNotebookProvider(id).future);
  c.listen(notebookProvider(id), (_, _) {});
  c.listen(libraryProvider, (_, _) {});
  return c;
}

void main() {
  group('LockCrypto', () {
    test('Argon2id + AES-GCM round trip; a wrong password or key fails', () async {
      final (entry, key) = await testCrypto.create('momentum42', hint: ' physics ', biometric: true);
      expect(entry.hint, 'physics');
      expect(entry.salt, hasLength(16));
      expect(await testCrypto.open(entry, 'momentum42'), key);
      expect(await testCrypto.open(entry, 'momentum43'), isNull);

      final sealed = await testCrypto.seal(key, '{"id":"pg_1"}');
      expect(ascii.decode(sealed.sublist(0, 4)), 'EBL1');
      expect(utf8.decode(sealed, allowMalformed: true), isNot(contains('pg_1')));
      expect(await testCrypto.unseal(key, sealed), '{"id":"pg_1"}');
      final (_, otherKey) = await testCrypto.create('other');
      expect(() => testCrypto.unseal(otherKey, sealed), throwsA(isA<SecretBoxAuthenticationError>()));
    });

    test('the default Argon2id cost is the OWASP minimum', () {
      const p = KdfParams();
      expect(p.memoryKiB, 19456);
      expect(p.iterations, 2);
    });

    test('lock.json round trip keeps no password', () async {
      final (entry, _) = await testCrypto.create('secret-password', hint: 'the usual');
      final file = LockFile(notebook: entry, pages: {'pg_3': entry});
      final json = jsonEncode(file.toJson());
      expect(json, isNot(contains('secret-password')));
      final back = LockFile.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(back.notebook!.hint, 'the usual');
      expect(back.pages['pg_3']!.kdf.memoryKiB, KdfParams.fast.memoryKiB);
      expect(back.entryFor('pg_3'), isNotNull);
      expect(back.entryFor('pg_9'), same(back.notebook));
    });
  });

  group('locking pages', () {
    testWidgets('a locked page is stored encrypted and opens with its password', (tester) async {
      final store = storeWith(sampleNotebook());
      final bio = FakeBiometric();
      final c = await _open(store, 'nb_sample', biometric: bio);
      final n = c.read(notebookProvider('nb_sample').notifier);

      await n.lockPage('pg_03', 'momentum42', hint: 'units', biometric: true);
      final nb = c.read(notebookProvider('nb_sample'));
      expect(nb.isSealed('pg_03'), isTrue);
      expect(nb.pageAt(2).items, isEmpty);
      expect(store.pages['nb_sample']!.containsKey('pg_03'), isFalse);
      expect(store.sealedPages['nb_sample']!.containsKey('pg_03'), isTrue);
      expect(LockFile.fromJson(store.locks['nb_sample']!).pages['pg_03']!.hint, 'units');
      expect(bio.saved.keys, [biometricSlot('nb_sample', 'pg_03')]);
      // The cover never shows a locked page.
      expect(c.read(libraryProvider).byId('nb_sample')!.thumb, isNull);

      expect(await n.unlock('pg_03', 'wrong'), isFalse);
      expect(c.read(notebookProvider('nb_sample')).isSealed('pg_03'), isTrue);
      expect(await n.unlock('pg_03', 'momentum42'), isTrue);
      expect(c.read(notebookProvider('nb_sample')).pageAt(2).items, hasLength(14));

      // Editing an unlocked page keeps it encrypted on disk.
      n.addStroke('pg_03', strokeFrom(const [Offset(0, 0), Offset(10, 10)]));
      await n.flush();
      expect(store.pages['nb_sample']!.containsKey('pg_03'), isFalse);

      await n.lockNow();
      expect(c.read(notebookProvider('nb_sample')).isSealed('pg_03'), isTrue);
      expect(await n.unlockWithBiometrics('pg_03', reason: 'test'), isTrue);
      expect(c.read(notebookProvider('nb_sample')).pageAt(2).items, hasLength(15));

      await n.removePageLock('pg_03');
      expect(store.pages['nb_sample']!.containsKey('pg_03'), isTrue);
      expect(store.sealedPages['nb_sample']!.containsKey('pg_03'), isFalse);
      expect(store.locks.containsKey('nb_sample'), isFalse);
      expect(bio.saved, isEmpty);
      expect(decodePage(store.pages['nb_sample']!['pg_03']!).locked, isFalse);
    });

    testWidgets('reopening a notebook keeps locked pages sealed', (tester) async {
      final store = storeWith(sampleNotebook());
      final c = await _open(store, 'nb_sample');
      await c.read(notebookProvider('nb_sample').notifier).lockPage('pg_03', 'momentum42');
      c.dispose();

      final loaded = await store.loadNotebook('nb_sample');
      expect(loaded!.sealed.keys, ['pg_03']);
      expect(loaded.pages[2].locked, isTrue);
      expect(loaded.pages[2].items, isEmpty);
      final again = await _open(store, 'nb_sample');
      expect(again.read(notebookProvider('nb_sample')).isSealed('pg_03'), isTrue);
      expect(await again.read(notebookProvider('nb_sample').notifier).unlock('pg_03', 'momentum42'), isTrue);
    });

    testWidgets('a notebook password locks every page and shows on the library cover', (tester) async {
      final store = storeWith(sampleNotebook());
      final c = await _open(store, 'nb_sample');
      final n = c.read(notebookProvider('nb_sample').notifier);
      await n.lockNotebook('whole-book', hint: 'book');
      expect(c.read(notebookProvider('nb_sample')).sealed, hasLength(4));
      expect(store.pages['nb_sample'] ?? {}, isEmpty);
      expect(decodeNotebook(store.notebooks['nb_sample']!).locked, isTrue);
      expect(c.read(libraryProvider).byId('nb_sample')!.locked, isTrue);

      expect(await n.unlock('pg_01', 'whole-book'), isTrue);
      expect(c.read(notebookProvider('nb_sample')).sealed, isEmpty);
      await n.removeNotebookLock();
      expect(store.sealedPages['nb_sample'] ?? {}, isEmpty);
      expect(store.pages['nb_sample']!, hasLength(4));
      expect(c.read(libraryProvider).byId('nb_sample')!.locked, isFalse);
    });
  });
}
