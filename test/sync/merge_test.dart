import 'dart:convert';
import 'dart:typed_data';

import 'package:endless/board/model.dart';
import 'package:endless/sync/doc.dart';
import 'package:endless/sync/root.dart';
import 'package:endless/sync/stamps.dart';
import 'package:flutter_test/flutter_test.dart';

Json item(String id, {int x = 0, String type = 'shape'}) => {
      'id': id,
      'type': type,
      'x': x,
      'y': 0,
      'rotation': 0,
      'z': 1,
      'createdAt': '2026-11-05T12:00:00.000Z',
      'kind': 'rect',
      'w': 10,
      'h': 10,
    };

Json page(String id, List<Json> items, {String title = ''}) => {
      'id': id,
      'title': title,
      'paper': 'dots',
      'template': null,
      'locked': false,
      'items': items,
    };

Json notebook(List<String> pages, {String title = 'Physics', String updated = '2026-11-05T12:00:00.000Z'}) => {
      'format': 'endless.board',
      'version': 1,
      'id': 'nb_1',
      'title': title,
      'folderPath': <String>[],
      'cover': null,
      'createdAt': '2026-11-01T12:00:00.000Z',
      'updatedAt': updated,
      'pages': pages,
      'defaults': {'paper': 'dots', 'theme': 'paper'},
      'locked': false,
      'pinned': false,
      'trashedAt': null,
    };

/// A device: what it has, and what it knew at its last sync.
class Device {
  Device(String name, this.doc, {int clockMs = 1000}) : stamper = Stamper(name, clock: () => DateTime.utc(2030));

  BoardDoc doc;
  final Stamper stamper;
  final known = Known();

  void stamp({DateTime? at}) => stampChanges(doc, known, stamper, editedAt: at ?? DateTime.utc(2026, 11, 5, 12));

  /// Takes [merged] as its own (as after a sync).
  void take(BoardDoc merged) {
    doc = BoardDoc(
      notebook: jsonDecode(jsonEncode(merged.notebook)) as Json,
      pages: {for (final e in merged.pages.entries) e.key: jsonDecode(jsonEncode(e.value)) as Json},
      sealed: {...merged.sealed},
      lock: merged.lock,
      study: merged.study,
      assets: {...merged.assets},
      stamps: merged.stamps.copy(),
    );
    known.record(doc);
  }

  List<Json> items(String pid) => [...(doc.pages[pid]!['items'] as List).cast<Json>()];
}

List<String> ids(BoardDoc d, String pid) => [for (final i in d.pages[pid]!['items'] as List) (i as Map)['id'] as String];

void main() {
  final t1 = DateTime.utc(2026, 11, 5, 12);
  final t2 = DateTime.utc(2026, 11, 5, 13);

  BoardDoc start() => BoardDoc(notebook: notebook(['p1']), pages: {
        'p1': page('p1', [item('a'), item('b')]),
      });

  (Device, Device) twoDevices() {
    final a = Device('dv_a', start())..stamp(at: t1);
    final b = Device('dv_b', start());
    b.take(a.doc);
    return (a, b);
  }

  test('strokes added on both devices are all kept, in the same order either way', () {
    final (a, b) = twoDevices();
    a.doc.pages['p1']!['items'] = [...a.items('p1'), item('fromA')];
    b.doc.pages['p1']!['items'] = [...b.items('p1'), item('fromB1'), item('fromB2')];
    a.stamp(at: t2);
    b.stamp(at: t2);
    final ab = mergeDocs(a.doc, b.doc);
    final ba = mergeDocs(b.doc, a.doc);
    expect(ids(ab, 'p1').toSet(), {'a', 'b', 'fromA', 'fromB1', 'fromB2'});
    expect(ids(ab, 'p1'), ids(ba, 'p1'));
    expect(hashJson(ab.pages), hashJson(ba.pages));
    // Merging again changes nothing.
    expect(hashJson(mergeDocs(ab, a.doc).pages), hashJson(ab.pages));
  });

  test('a deletion wins over an older copy, and isn\'t undone by a device that still has it', () {
    final (a, b) = twoDevices();
    a.doc.pages['p1']!['items'] = [item('b')];
    a.stamp(at: t2);
    // b didn't change anything.
    b.stamp(at: t2);
    final m = mergeDocs(a.doc, b.doc);
    expect(ids(m, 'p1'), ['b']);
    expect(m.stamps.pages['p1']!.gone.keys, contains('a'));
    // b takes it; merging b's old copy again doesn't bring 'a' back.
    expect(ids(mergeDocs(m, start()..stamps.pages['p1'] = PageStamps()), 'p1'), ['b']);
  });

  test('the same item changed on both: the later change wins', () {
    final (a, b) = twoDevices();
    a.doc.pages['p1']!['items'] = [item('a', x: 5), item('b')];
    b.doc.pages['p1']!['items'] = [item('a', x: 9), item('b')];
    a.stamp(at: t1.add(const Duration(minutes: 5)));
    b.stamp(at: t1.add(const Duration(minutes: 7)));
    for (final m in [mergeDocs(a.doc, b.doc), mergeDocs(b.doc, a.doc)]) {
      expect((m.pages['p1']!['items'] as List).first['x'], 9);
    }
  });

  test('an edit made after seeing another device\'s change wins, even with a clock behind', () {
    final (a, b) = twoDevices();
    a.doc.pages['p1']!['items'] = [item('a', x: 5), item('b')];
    a.stamp(at: t2); // a's clock is an hour ahead
    b.take(mergeDocs(b.doc, a.doc));
    b.doc.pages['p1']!['items'] = [item('a', x: 7), item('b')];
    b.stamp(at: t1); // b edits it later, by a slow clock
    final m = mergeDocs(a.doc, b.doc);
    expect((m.pages['p1']!['items'] as List).first['x'], 7);
  });

  test('a deleted item edited later on another device comes back', () {
    final (a, b) = twoDevices();
    a.doc.pages['p1']!['items'] = [item('b')];
    a.stamp(at: t1.add(const Duration(minutes: 1)));
    b.doc.pages['p1']!['items'] = [item('a', x: 3), item('b')];
    b.stamp(at: t1.add(const Duration(minutes: 2)));
    expect(ids(mergeDocs(a.doc, b.doc), 'p1'), containsAll(['a', 'b']));
  });

  test('notebook fields merge one by one; pages added on both are kept', () {
    final (a, b) = twoDevices();
    a.doc.notebook['title'] = 'Physics 2';
    a.doc.notebook['pages'] = ['p1', 'pa'];
    a.doc.pages['pa'] = page('pa', [item('x')]);
    b.doc.notebook['pinned'] = true;
    b.doc.notebook['pages'] = ['p1', 'pb'];
    b.doc.pages['pb'] = page('pb', []);
    a.stamp(at: t2);
    b.stamp(at: t2);
    final m = mergeDocs(a.doc, b.doc);
    expect(m.notebook['title'], 'Physics 2');
    expect(m.notebook['pinned'], true);
    expect((m.notebook['pages'] as List).toSet(), {'p1', 'pa', 'pb'});
    expect(m.notebook['pages'], mergeDocs(b.doc, a.doc).notebook['pages']);
  });

  test('a page deleted on one device stays deleted unless written on later', () {
    final (a, b) = twoDevices();
    a.doc.notebook['pages'] = <String>[];
    a.doc.pages.remove('p1');
    a.stamp(at: t2);
    b.stamp(at: t2);
    final m = mergeDocs(a.doc, b.doc);
    expect(m.pageIds, isEmpty);
    expect(m.notebook['pages'], isEmpty);

    // Written on after the delete: the page comes back.
    final (c, d) = twoDevices();
    c.doc.notebook['pages'] = <String>[];
    c.doc.pages.remove('p1');
    c.stamp(at: t1.add(const Duration(minutes: 1)));
    d.doc.pages['p1']!['items'] = [...d.items('p1'), item('late')];
    d.stamp(at: t1.add(const Duration(minutes: 2)));
    final m2 = mergeDocs(c.doc, d.doc);
    expect(m2.pageIds, {'p1'});
    expect(ids(m2, 'p1'), contains('late'));
  });

  test('unknown item types and fields travel untouched', () {
    final (a, b) = twoDevices();
    final odd = {...item('odd', type: 'hologram'), 'beam': {'color': 'teal', 'mode': 3}};
    a.doc.pages['p1']!['items'] = [...a.items('p1'), odd];
    a.doc.pages['p1']!['futureField'] = [1, 2];
    a.stamp(at: t2);
    b.stamp(at: t2);
    final m = mergeDocs(b.doc, a.doc);
    expect((m.pages['p1']!['items'] as List).last, odd);
    expect(m.pages['p1']!['futureField'], [1, 2]);
  });

  test('a page locked on one device stays locked; its password entry comes with it', () {
    final (a, b) = twoDevices();
    a.doc.pages.remove('p1');
    a.doc.sealed['p1'] = Uint8List.fromList([1, 2, 3]);
    a.doc.lock = {
      'version': 1,
      'notebook': null,
      'pages': {
        'p1': {'salt': 'abc'},
      },
    };
    a.stamp(at: t1.add(const Duration(minutes: 1)));
    // b wrote on it meanwhile, but didn't remove a password.
    b.doc.pages['p1']!['items'] = [...b.items('p1'), item('late')];
    b.stamp(at: t1.add(const Duration(minutes: 2)));
    for (final m in [mergeDocs(a.doc, b.doc), mergeDocs(b.doc, a.doc)]) {
      expect(m.sealed.keys, ['p1']);
      expect(m.pages, isEmpty);
      expect((m.lock!['pages'] as Map).keys, ['p1']);
    }
  });

  test('newest wins: the copy changed last replaces the other as a whole', () {
    final (a, b) = twoDevices();
    a.doc.pages['p1']!['items'] = [...a.items('p1'), item('fromA')];
    b.doc.pages['p1']!['items'] = [...b.items('p1'), item('fromB')];
    a.stamp(at: t1.add(const Duration(minutes: 1)));
    b.stamp(at: t1.add(const Duration(minutes: 2)));
    final m = mergeDocs(a.doc, b.doc, policy: MergePolicy.newestWins);
    expect(ids(m, 'p1'), ['a', 'b', 'fromB']);
  });

  test('mergeOrder puts the other list\'s items after the one before them', () {
    expect(mergeOrder(['a', 'b', 'c'], ['a', 'x', 'b', 'y'], {'a', 'b', 'c', 'x', 'y'}), ['a', 'x', 'b', 'y', 'c']);
    expect(mergeOrder(['b'], ['x', 'b'], {'b', 'x'}), ['x', 'b']);
  });

  test('stamps sort in time order, and a stamp is always after the one it replaces', () {
    final s = Stamper('dv_a', clock: () => DateTime.utc(2026, 11, 5, 12));
    final early = s.after(null, DateTime.utc(2026, 11, 5, 10));
    final late = s.after(null, DateTime.utc(2026, 11, 5, 11));
    expect(newer(late, early), isTrue);
    final ahead = Stamper('dv_b', clock: () => DateTime.utc(2027)).after(null, DateTime.utc(2027));
    expect(newer(s.after(ahead, DateTime.utc(2026, 11, 5, 10)), ahead), isTrue);
    // Never in the future.
    expect(stampMillis(s.after(null, DateTime.utc(2030))), DateTime.utc(2026, 11, 5, 12).millisecondsSinceEpoch);
  });

  test('folders and decks: entries merge by key, deletions stick', () {
    final sa = Stamper('dv_a'), sb = Stamper('dv_b');
    final knownA = <String, String>{}, knownB = <String, String>{};
    var a = stampKeyed({'f1': 1, 'f2': 2}, knownA, Keyed(), sa);
    var b = stampKeyed({'f1': 1, 'f2': 2}, knownB, Keyed(), sb);
    final both = mergeKeyed(a, b);
    a = stampKeyed({'f1': 1, 'f3': 3}, knownA, both, sa); // f2 deleted, f3 added
    b = stampKeyed({'f1': 10, 'f2': 2}, knownB, both, sb); // f1 changed
    final m = mergeKeyed(a, b);
    expect(m.values, {'f1': 10, 'f3': 3});
    expect(mergeKeyed(b, a).values, m.values);
  });
}
