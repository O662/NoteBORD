import 'dart:convert';

import 'model.dart';

// JSON encoding for notebook.json and pages/<pageId>.json.

const _notebookKeys = {
  'format', 'version', 'id', 'title', 'folderPath', 'cover', 'createdAt', 'updatedAt', //
  'pages', 'defaults', 'locked', 'pinned', 'trashedAt',
};
const _pageKeys = {'id', 'title', 'paper', 'template', 'locked', 'items'};
const _itemKeys = {'id', 'type', 'x', 'y', 'rotation', 'z', 'createdAt', 'author', 'remember'};
const _strokeKeys = {
  ..._itemKeys, 'tool', 'penType', 'color', 'width', 'points', 'usePressure', 'arrow', 'straightened', //
};

Json _unknown(Json json, Set<String> known) => {
      for (final e in json.entries)
        if (!known.contains(e.key)) e.key: e.value,
    };

String encodeNotebook(Notebook nb) {
  final json = {
    ...nb.extra,
    'format': boardFormat,
    'version': boardVersion,
    'id': nb.id,
    'title': nb.title,
    'folderPath': nb.folderPath,
    'cover': nb.coverColor == null ? null : {'color': nb.coverColor},
    'createdAt': nb.createdAt.toUtc().toIso8601String(),
    'updatedAt': nb.updatedAt.toUtc().toIso8601String(),
    'pages': nb.pageIds,
    'defaults': {...nb.extraDefaults, 'paper': nb.defaultPaper.name, 'theme': nb.theme},
    'locked': nb.locked,
    'pinned': nb.pinned,
    'trashedAt': nb.trashedAt?.toUtc().toIso8601String(),
  };
  return const JsonEncoder.withIndent('  ').convert(json);
}

Notebook decodeNotebook(String source) {
  final json = jsonDecode(source) as Json;
  if (json['format'] != boardFormat) {
    throw FormatException('Not an Endless notebook (format: ${json['format']})');
  }
  final defaults = (json['defaults'] as Map?)?.cast<String, dynamic>() ?? {};
  return Notebook(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Untitled notebook',
    folderPath: [...?(json['folderPath'] as List?)?.cast<String>()],
    coverColor: (json['cover'] as Map?)?['color'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    pageIds: [...(json['pages'] as List).cast<String>()],
    defaultPaper: paperFromName(defaults['paper'] as String?),
    theme: defaults['theme'] as String? ?? 'paper',
    locked: json['locked'] as bool? ?? false,
    pinned: json['pinned'] as bool? ?? false,
    trashedAt: DateTime.tryParse(json['trashedAt'] as String? ?? ''),
    extra: _unknown(json, _notebookKeys),
    extraDefaults: _unknown(defaults, {'paper', 'theme'}),
  );
}

/// Items reuse their cached encoding, so a save only encodes new items.
String encodePage(BoardPage page) {
  final head = jsonEncode({
    ...page.extra,
    'id': page.id,
    'title': page.title,
    'paper': page.paper.name,
    'template': page.template,
    'locked': page.locked,
  });
  final items = page.items.map((i) => i.encoded).join(',\n');
  return '${head.substring(0, head.length - 1)},"items":[\n$items\n]}\n';
}

BoardPage decodePage(String source) {
  final json = jsonDecode(source) as Json;
  return BoardPage(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    paper: paperFromName(json['paper'] as String?),
    template: json['template'],
    locked: json['locked'] as bool? ?? false,
    items: [for (final i in (json['items'] as List? ?? const [])) decodeItem(i as Json)],
    extra: _unknown(json, _pageKeys),
  );
}

Item decodeItem(Json json) {
  try {
    return _decodeKnown(json) ?? UnknownItem(json);
  } on TypeError {
    // A known type with fields this version can't read: keep it as it is.
    return UnknownItem(json);
  } on FormatException {
    return UnknownItem(json);
  }
}

const _boxKeys = {..._itemKeys, 'w', 'h'};

double _num(Object? v, [double fallback = 0]) => (v as num?)?.toDouble() ?? fallback;

List<Item> _nested(Object? list) => [for (final i in (list as List? ?? const [])) decodeItem((i as Map).cast<String, dynamic>())];

Item? _decodeKnown(Json json) {
  final id = json['id'] as String;
  final x = (json['x'] as num).toDouble();
  final y = (json['y'] as num).toDouble();
  final rotation = _num(json['rotation']);
  final z = (json['z'] as num?)?.toInt() ?? 0;
  final createdAt = DateTime.parse(json['createdAt'] as String);
  final author = json['author'] as String? ?? localAuthor;
  final remember = (json['remember'] as Map?)?.cast<String, dynamic>();
  switch (json['type']) {
    case 'stroke':
      return StrokeItem(
        id: id,
        x: x,
        y: y,
        rotation: rotation,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: _unknown(json, _strokeKeys),
        tool: InkTool.values.firstWhere((t) => t.name == json['tool'], orElse: () => InkTool.pen),
        penType: PenType.values.firstWhere((t) => t.name == json['penType'], orElse: () => PenType.ballpoint),
        color: colorFromHex(json['color'] as String),
        width: (json['width'] as num).toDouble(),
        usePressure: json['usePressure'] as bool? ?? true,
        arrow: ArrowHeads.fromJson(json['arrow']),
        straightened: json['straightened'] as String?,
        points: [
          for (final p in json['points'] as List)
            InkPoint(
              ((p as List)[0] as num).toDouble(),
              (p[1] as num).toDouble(),
              p.length > 2 ? (p[2] as num).toDouble() : 0.5,
              p.length > 3 ? (p[3] as num).toInt() : 0,
            ),
        ],
      );
    case 'text':
      return TextItem(
        id: id,
        x: x,
        y: y,
        rotation: rotation,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: _unknown(json, const {..._itemKeys, 'w', 'text', 'font', 'size', 'color', 'autoWidth'}),
        wrap: (json['w'] as num).toDouble(),
        text: json['text'] as String,
        font: json['font'] as String? ?? 'ui',
        size: _num(json['size'], 22),
        color: colorFromHex(json['color'] as String),
        autoWidth: json['autoWidth'] == true,
      );
    case 'sticky':
      final stack = json['stack'] as Map?;
      return StickyItem(
        id: id,
        x: x,
        y: y,
        rotation: rotation,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: _unknown(json, const {..._boxKeys, 'color', 'items', 'stack'}),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
        color: colorFromHex(json['color'] as String),
        items: _nested(json['items']),
        under: [
          for (final n in (stack?['notes'] as List? ?? const []))
            StickyNote(color: colorFromHex((n as Map)['color'] as String), items: _nested(n['items'])),
        ],
        count: (stack?['count'] as num?)?.toInt(),
      );
    case 'frame':
      return FrameItem(
        id: id,
        x: x,
        y: y,
        rotation: rotation,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: _unknown(json, const {..._boxKeys, 'paper', 'title', 'template', 'unit'}),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
        paper: json['paper'] as String? ?? 'lined-a4',
        title: json['title'] as String? ?? '',
        template: json['template'] as String?,
        unit: _num(json['unit'], 1),
      );
    case 'image':
      return ImageItem(
        id: id,
        x: x,
        y: y,
        rotation: rotation,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: _unknown(json, const {..._boxKeys, 'asset'}),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
        asset: json['asset'] as String,
      );
    case 'shape':
      final kind = ShapeType.values.where((k) => k.name == json['kind']).firstOrNull;
      if (kind == null) return null;
      return ShapeItem(
        id: id,
        x: x,
        y: y,
        rotation: rotation,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: _unknown(json, const {..._boxKeys, 'kind', 'stroke', 'fill', 'strokeWidth'}),
        kind: kind,
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
        stroke: colorFromHex(json['stroke'] as String),
        fill: json['fill'] is String ? colorFromHex(json['fill'] as String) : null,
        strokeWidth: _num(json['strokeWidth'], 2.5),
      );
    case 'kanban' || 'timeline' || 'diagram' || 'table' || 'embed':
      final data = _cardData(json);
      return CardItem(
        id: id,
        x: x,
        y: y,
        rotation: rotation,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: _unknown(json, {..._boxKeys, 'title', 'unit', ...data.keys}),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
        data: data,
        title: json['title'] as String? ?? '',
        unit: _num(json['unit'], 1),
      );
    default:
      return null;
  }
}

Json _map(Object? v) => (v as Map).cast<String, dynamic>();

T _named<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

/// What a card holds, by its item type.
CardData _cardData(Json json) {
  switch (json['type']) {
    case 'kanban':
      return KanbanData([
        for (final c in (json['columns'] as List).map(_map))
          KanbanColumn(
            c['title'] as String? ?? '',
            [
              for (final card in (c['cards'] as List? ?? const []).map(_map))
                KanbanCard(card['text'] as String? ?? '', extra: _unknown(card, const {'text'})),
            ],
            _unknown(c, const {'title', 'cards'}),
          ),
      ]);
    case 'timeline':
      return TimelineData([
        for (final e in (json['events'] as List).map(_map))
          TimelineEvent(
            date: e['date'] as String? ?? '',
            label: e['label'] as String? ?? '',
            state: _named(EventState.values, e['state'], EventState.later),
            extra: _unknown(e, const {'date', 'label', 'state'}),
          ),
      ]);
    case 'diagram':
      return DiagramData(
        [
          for (final n in (json['nodes'] as List).map(_map))
            DiagramNode(
              id: n['id'] as String,
              text: n['text'] as String? ?? '',
              shape: _named(NodeShape.values, n['shape'], NodeShape.box),
              color: _named(NodeColor.values, n['color'], NodeColor.blue),
              extra: _unknown(n, const {'id', 'text', 'shape', 'color'}),
            ),
        ],
        [
          for (final e in (json['edges'] as List? ?? const []).map(_map)) (e['from'] as String, e['to'] as String),
        ],
      );
    case 'table':
      // `header` says whether the first row is the column names.
      if (json['header'] != null && json['header'] is! bool) throw const FormatException('table.header');
      return TableData(
        [
          for (final row in json['cells'] as List) [for (final cell in row as List) '${cell ?? ''}'],
        ],
        header: json['header'] != false,
      );
    default:
      return EmbedData(json['url'] as String);
  }
}
