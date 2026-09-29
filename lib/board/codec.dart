import 'dart:convert';

import 'model.dart';

// JSON encoding for notebook.json and pages/<pageId>.json.

const _notebookKeys = {
  'format', 'version', 'id', 'title', 'folderPath', 'cover', 'createdAt', 'updatedAt', //
  'pages', 'defaults', 'locked', 'pinned', 'trashedAt',
};
const _pageKeys = {'id', 'title', 'paper', 'template', 'locked', 'items'};
const _itemKeys = {'id', 'type', 'x', 'y', 'rotation', 'z', 'createdAt', 'author', 'remember'};
const _strokeKeys = {..._itemKeys, 'tool', 'penType', 'color', 'width', 'points', 'usePressure'};

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
  switch (json['type']) {
    case 'stroke':
      return StrokeItem(
        id: json['id'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        z: (json['z'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        author: json['author'] as String? ?? localAuthor,
        remember: (json['remember'] as Map?)?.cast<String, dynamic>(),
        extra: _unknown(json, _strokeKeys),
        tool: InkTool.values.firstWhere((t) => t.name == json['tool'], orElse: () => InkTool.pen),
        penType: PenType.values.firstWhere((t) => t.name == json['penType'], orElse: () => PenType.ballpoint),
        color: colorFromHex(json['color'] as String),
        width: (json['width'] as num).toDouble(),
        usePressure: json['usePressure'] as bool? ?? true,
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
    default:
      return UnknownItem(json);
  }
}
