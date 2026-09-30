import 'dart:convert';

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/canvas/cards.dart';
import 'package:endless/canvas/items.dart';
import 'package:endless/canvas/selection.dart';
import 'package:endless/state/links.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_board.dart';

Json _json(Item item) => jsonDecode(jsonEncode(item.toJson())) as Json;

CardItem _back(CardItem card) => decodePage(encodePage(BoardPage(id: 'pg', items: [card]))).items.single as CardItem;

final _at = DateTime.utc(2026, 9, 29, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  group('.board cards', () {
    test('a Kanban board keeps its columns and cards', () {
      final json = _json(sampleKanban);
      expect(json['type'], 'kanban');
      expect(json['title'], 'Study tasks');
      expect(json['unit'], 1.375);
      expect(json['w'], 577.5);
      expect(json['h'], 374.0);
      expect(json['columns'], [
        {
          'title': 'To do',
          'cards': [
            {'text': 'Read chapter 9'},
            {'text': 'Problem set 4'},
          ],
        },
        {
          'title': 'Doing',
          'cards': [
            {'text': 'Lab 4 report'},
          ],
        },
        {
          'title': 'Done',
          'cards': [
            {'text': 'Chapter 8 quiz'},
          ],
        },
      ]);
      final back = _back(sampleKanban);
      final data = back.data as KanbanData;
      expect(data.columns.map((c) => c.title), ['To do', 'Doing', 'Done']);
      expect(data.columns[0].cards.map((c) => c.text), ['Read chapter 9', 'Problem set 4']);
      expect(back.title, 'Study tasks');
      expect(back.unit, 1.375);
      expect(_json(back), json);
    });

    test('timeline, diagram, table and website round trip', () {
      expect(_json(sampleTimeline)['events'], [
        {'date': 'Sep 30', 'label': 'Lab report', 'state': 'done'},
        {'date': 'Oct 14', 'label': 'Midterm', 'state': 'now'},
        {'date': 'Nov 4', 'label': 'Project draft', 'state': 'later'},
        {'date': 'Dec 9', 'label': 'Final exam', 'state': 'later'},
      ]);
      final timeline = _back(sampleTimeline).data as TimelineData;
      expect(timeline.events.map((e) => e.state), [EventState.done, EventState.now, EventState.later, EventState.later]);

      final dj = _json(sampleDiagram);
      expect(dj['type'], 'diagram');
      expect((dj['nodes'] as List)[1], {'id': 'n2', 'text': 'Collide', 'shape': 'pill', 'color': 'clay'});
      expect(dj['edges'], [
        {'from': 'n1', 'to': 'n2'},
        {'from': 'n2', 'to': 'n3'},
        {'from': 'n3', 'to': 'n4'},
      ]);
      final diagram = _back(sampleDiagram).data as DiagramData;
      expect(diagram.nodes.map((n) => n.shape), [NodeShape.box, NodeShape.pill, NodeShape.box, NodeShape.diamond]);
      expect(diagram.edges, [('n1', 'n2'), ('n2', 'n3'), ('n3', 'n4')]);

      final tj = _json(sampleTable);
      expect(tj['type'], 'table');
      expect(tj['header'], isTrue);
      expect((tj['cells'] as List)[1], ['1', '0.50', '2.0', '1.00']);
      final table = _back(sampleTable).data as TableData;
      expect((table.rows, table.columns, table.header), (4, 4, true));

      final wj = _json(sampleWebsite);
      expect(wj['type'], 'embed');
      expect(wj['url'], 'https://website-address.com/collision-lab');
      expect((_back(sampleWebsite).data as EmbedData).host, 'website-address.com');
    });

    test('fields this version doesn’t know are kept, inside cards too', () {
      final source = <String, dynamic>{
        'id': 'it_k', 'type': 'kanban', 'x': 1, 'y': 2, 'z': 3, 'createdAt': '2026-09-01T00:00:00.000Z', //
        'w': 420, 'h': 272, 'title': 'Tasks', 'wipLimit': 3,
        'columns': [
          {
            'title': 'To do',
            'color': '#2B5A8C',
            'cards': [
              {'text': 'Read', 'assignee': 'maya', 'due': '2026-10-01'},
            ],
          },
        ],
      };
      final card = decodeItem(source) as CardItem;
      expect(card.unit, 1); // a file without a scale is at the design's size
      final json = _json(card);
      expect(json['wipLimit'], 3);
      final column = (json['columns'] as List).single as Map;
      expect(column['color'], '#2B5A8C');
      expect((column['cards'] as List).single, {'text': 'Read', 'assignee': 'maya', 'due': '2026-10-01'});

      final event = decodeItem({
        ...source,
        'type': 'timeline',
        'events': [
          {'date': 'Oct 1', 'label': 'Quiz', 'state': 'soon', 'link': 'nb_1'},
        ],
      }) as CardItem;
      final e = (event.data as TimelineData).events.single;
      expect(e.state, EventState.later); // a state from a newer app reads as "to come"
      expect(e.toJson()['link'], 'nb_1');
    });

    test('a card this version can’t read is kept exactly as it was', () {
      final odd = <String, dynamic>{
        'id': 'it_t', 'type': 'table', 'x': 1, 'y': 2, 'z': 3, 'createdAt': '2026-09-01T00:00:00.000Z', //
        'w': 220, 'h': 200, 'cells': [['a']], 'header': ['Name'],
      };
      final item = decodeItem(odd);
      expect(item, isA<UnknownItem>());
      expect(item.toJson(), odd);
      expect(decodeItem({...odd, 'type': 'kanban'}), isA<UnknownItem>()); // no columns
      expect(decodeItem({...odd, 'type': 'embed'}), isA<UnknownItem>()); // no url
    });

    test('a website only opens http and https addresses', () {
      expect(const EmbedData('https://example.com/lab').link, Uri.parse('https://example.com/lab'));
      expect(const EmbedData('http://example.com').link, isNotNull);
      for (final bad in ['javascript:alert(1)', 'file:///etc/passwd', 'tel:+123', 'intent://x#Intent;end', 'not a url', '']) {
        expect(EmbedData(bad).link, isNull, reason: bad);
      }
      expect(const EmbedData('https://www.example.com/a').host, 'example.com');

      expect(EmbedData.normalize('example.com/lab'), 'https://example.com/lab');
      expect(EmbedData.normalize(' http://example.com '), 'http://example.com');
      expect(EmbedData.normalize('localhost'), isNull);
      expect(EmbedData.normalize('two words.com'), isNull);
      expect(EmbedData.normalize('ftp://example.com'), isNull);
      expect(EmbedData.normalize(''), isNull);
    });

    test('the browser opener itself refuses anything but a web page', () async {
      // Refused before the platform is asked (which would fail in a test).
      expect(await const BrowserLinkOpener().open(Uri.parse('tel:+123')), isFalse);
      expect(await const BrowserLinkOpener().open(Uri.parse('file:///etc/passwd')), isFalse);
    });
  });

  group('card sizes', () {
    test('new cards are the sizes on Board.png, times the scale they are drawn at', () {
      expect(cardNaturalSize(starterKanban()), const Size(420, 272));
      expect(cardNaturalSize((sampleTimeline.data as TimelineData)), const Size(666, 132));
      expect(cardNaturalSize(starterTable()), const Size(220, 200));
      expect(cardNaturalSize(const EmbedData('https://example.com')), const Size(290, 200));
      final diagram = cardNaturalSize(sampleDiagram.data);
      expect(diagram.width, inInclusiveRange(400, 440)); // 420 on the design
      expect(diagram.height, 198);

      final card = newCard(starterKanban(), const Offset(640, 400), z: 1, now: _at);
      expect(card.unit, CardItem.defaultUnit);
      expect(Size(card.w, card.h), const Size(578, 374));
      expect((card.center - const Offset(640, 400)).distance, lessThan(0.01));

      final timeline = starterTimeline(DateTime(2026, 9, 30));
      expect(timeline.events.map((e) => e.date), ['Sep 30', 'Oct 7', 'Oct 14']);
      expect(timeline.events.first.state, EventState.now);
    });

    test('a card grows for what it holds, and never shrinks', () {
      final many = KanbanData([
        KanbanColumn('To do', [for (var i = 0; i < 12; i++) KanbanCard('Task $i')]),
        const KanbanColumn('Doing'),
        const KanbanColumn('Done'),
      ]);
      final grown = fitCard(sampleKanban.copyWith(data: many));
      expect(grown.h, greaterThan(sampleKanban.h + 100));
      expect(grown.w, sampleKanban.w);
      expect((grown.x, grown.y), (sampleKanban.x, sampleKanban.y));
      // Long text wraps inside its card, so it needs more height too.
      final long = fitCard(sampleKanban.copyWith(
        data: KanbanData([KanbanColumn('To do', [for (var i = 0; i < 4; i++) const KanbanCard('Write up the method, the results and the conclusion')])]),
      ));
      expect(fitCard(sampleKanban), same(sampleKanban));
      expect(long.h, greaterThanOrEqualTo(sampleKanban.h));

      final rows = TableData([for (var r = 0; r < 12; r++) ['a', 'b']]);
      expect(fitCard(sampleTable.copyWith(data: rows)).h, closeTo((38 + 1 + 12 * 29 + 10) * 1.375, 0.01));
      final wide = TableData([List.filled(8, 'x')]);
      expect(fitCard(sampleTable.copyWith(data: wide)).w, greaterThan(sampleTable.w));
    });

    test('corner handles scale a card; edge handles change its width, down to a minimum', () {
      final bigger = const Similarity(scale: 2).applyToItem(sampleKanban) as CardItem;
      expect(bigger.unit, 2.75);
      expect(Size(bigger.w, bigger.h), Size(sampleKanban.w * 2, sampleKanban.h * 2));
      expect(bigger.data, same(sampleKanban.data));

      final wider = stretchBox(sampleKanban, 1, sampleKanban.toPage(Offset(sampleKanban.w + 100, 50))) as CardItem;
      expect(wider.w, sampleKanban.w + 100);
      expect(wider.unit, sampleKanban.unit); // the text stays the size it was
      expect(wider.x, sampleKanban.x);

      final narrow = stretchBox(sampleKanban, 1, sampleKanban.toPage(const Offset(10, 50))) as CardItem;
      expect(narrow.w, 3 * 84 * 1.375); // room for three columns
      final short = stretchBox(sampleKanban, 2, sampleKanban.toPage(const Offset(50, 5))) as CardItem;
      expect(short.h, 80 * 1.375);
      expect(stretchSides(sampleKanban), [0, 1, 2, 3]);
    });

    test('a website card’s Open button is at its bottom right', () {
      final open = embedOpenRect(sampleWebsite);
      expect(open.right, closeTo(sampleWebsite.w - 10 * 1.375, 0.01));
      expect(open.bottom, closeTo(sampleWebsite.h - 5 * 1.375, 0.01));
      expect(open.height, closeTo(30 * 1.375, 0.01));
      expect(open.width, greaterThan(44));
    });
  });
}
