import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/codec.dart';
import '../board/ids.dart';
import '../board/model.dart';
import '../board/store.dart';
import '../state/settings.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';

// Templates (design/source/Templates.dc.html). Paper templates only set the
// page's paper. Layout templates also draw a starting layout under the ink,
// in page space at [layoutOrigin]; the page stays endless around it.

enum TemplateCategory { paper, study, planning, boards }

/// What "Use for" applies the template to.
enum TemplateTarget { newPage, frame, newNotebook }

class TemplateDef {
  const TemplateDef(this.id, this.name, this.categories, {this.paper = Paper.dots, this.layout = true});

  final String id;
  final String name;
  final Set<TemplateCategory> categories;
  final Paper paper;

  /// Draws a layout (false for plain paper).
  final bool layout;
}

const builtInTemplates = [
  TemplateDef('dots', 'Dot grid', {TemplateCategory.paper}, layout: false),
  TemplateDef('lined', 'Lined paper', {TemplateCategory.paper}, paper: Paper.lines, layout: false),
  TemplateDef('graph', 'Graph paper', {TemplateCategory.paper}, paper: Paper.grid, layout: false),
  TemplateDef('cornell', 'Cornell notes', {TemplateCategory.study}, paper: Paper.lines),
  TemplateDef('meeting', 'Meeting notes', {TemplateCategory.planning}, paper: Paper.lines),
  TemplateDef('weekly', 'Weekly planner', {TemplateCategory.planning}, paper: Paper.blank),
  TemplateDef('todo', 'To-do list', {TemplateCategory.planning}, paper: Paper.lines),
  TemplateDef('kanban', 'Kanban board', {TemplateCategory.boards}, paper: Paper.blank),
  TemplateDef('mind', 'Mind map', {TemplateCategory.study, TemplateCategory.boards}),
  TemplateDef('story', 'Storyboard', {TemplateCategory.boards}, paper: Paper.blank),
  TemplateDef('lab', 'Lab report', {TemplateCategory.study}, paper: Paper.lines),
];

TemplateDef? templateById(Object? id) => builtInTemplates.where((t) => t.id == id).firstOrNull;

/// Where layouts start on the page: just inside the chrome at 100% zoom.
const layoutOrigin = Offset(120, 110);

/// Page-space bounds of a layout, for "whole board" and thumbnails.
Rect? layoutBounds(Object? id) {
  final size = switch (id) {
    'cornell' => const Size(1000, 1300),
    'meeting' => const Size(1000, 1000),
    'weekly' || 'kanban' || 'story' => const Size(1040, 620),
    'todo' => const Size(900, 900),
    'mind' => const Size(1040, 560),
    'lab' => const Size(1000, 1180),
    _ => null,
  };
  return size == null ? null : layoutOrigin & size;
}

final _pictures = <(String, EndlessColors), ui.Picture>{};

/// The layout for [id] as a cached picture in page coordinates, or null.
ui.Picture? layoutPicture(Object? id, EndlessColors colors) {
  if (id is! String || layoutBounds(id) == null) return null;
  return _pictures[(id, colors)] ??= () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(layoutOrigin.dx, layoutOrigin.dy);
    _LayoutPainter(canvas, colors).paint(id);
    return recorder.endRecording();
  }();
}

class _LayoutPainter {
  _LayoutPainter(this.canvas, this.c);

  final Canvas canvas;
  final EndlessColors c;

  Paint get _rule => Paint()
    ..color = c.lineStrong
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  void _label(String text, Offset at, {Color? color, double size = 15, FontWeight weight = FontWeight.w600}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text.toUpperCase(),
        style: TextStyle(
          fontFamily: FontFamilies.ui,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: size * 0.08,
          color: color ?? c.textFaint,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  void _box(Rect r, {Color? fill, Color? stroke, double radius = 12}) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    if (fill != null) canvas.drawRRect(rr, Paint()..color = fill);
    if (stroke != null) {
      canvas.drawRRect(
        rr,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _checkbox(Offset at) => _box(at & const Size(24, 24), stroke: c.accent, radius: 5);

  void paint(String id) {
    switch (id) {
      case 'cornell':
        final accent = Paint()
          ..color = c.accent
          ..strokeWidth = 2;
        canvas
          ..drawLine(const Offset(0, 96), const Offset(1000, 96), accent)
          ..drawLine(const Offset(280, 96), const Offset(280, 1040), accent)
          ..drawLine(const Offset(0, 1040), const Offset(1000, 1040), accent);
        _label('Topic · date', const Offset(4, 56));
        _label('Cues', const Offset(4, 112));
        _label('Notes', const Offset(300, 112));
        _label('Summary', const Offset(4, 1056));
      case 'meeting':
        _label('Meeting', const Offset(0, 0), color: c.text, size: 20, weight: FontWeight.w700);
        canvas.drawLine(const Offset(0, 64), const Offset(1000, 64), _rule);
        _label('Date', const Offset(0, 84));
        _label('Attendees', const Offset(420, 84));
        _label('Notes', const Offset(0, 180));
        _label('Action items', const Offset(0, 700));
        for (var i = 0; i < 5; i++) {
          final y = 750.0 + i * 48;
          _checkbox(Offset(0, y));
        }
      case 'weekly':
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Notes'];
        const w = (1040 - 3 * 16) / 4, h = (620 - 16) / 2;
        for (var i = 0; i < 8; i++) {
          final r = Rect.fromLTWH((i % 4) * (w + 16), (i ~/ 4) * (h + 16), w, h);
          _box(r, fill: i == 7 ? c.stickyYellow : null, stroke: i == 7 ? null : c.lineStrong);
          _label(days[i], r.topLeft + const Offset(16, 14));
        }
      case 'todo':
        _label('To do', const Offset(0, 0), color: c.text, size: 20, weight: FontWeight.w700);
        for (var i = 0; i < 12; i++) {
          final y = 72.0 + i * 64;
          _checkbox(Offset(0, y));
          canvas.drawLine(Offset(44, y + 24), Offset(900, y + 24), _rule);
        }
      case 'kanban':
        const cols = ['To do', 'Doing', 'Done'];
        const w = (1040 - 2 * 20) / 3;
        for (var i = 0; i < 3; i++) {
          final r = Rect.fromLTWH(i * (w + 20), 0, w, 620);
          _box(r, fill: c.menuTile, radius: 16);
          _label(cols[i], r.topLeft + const Offset(18, 18));
        }
      case 'mind':
        const center = Offset(520, 280);
        const nodes = [Offset(150, 70), Offset(890, 70), Offset(150, 490), Offset(890, 490)];
        final spoke = Paint()
          ..color = c.lineStrong
          ..strokeWidth = 2;
        for (final n in nodes) {
          canvas.drawLine(center, n, spoke);
        }
        canvas
          ..drawOval(Rect.fromCenter(center: center, width: 340, height: 170), Paint()..color = c.accentTint)
          ..drawOval(
            Rect.fromCenter(center: center, width: 340, height: 170),
            Paint()
              ..color = c.accent
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        for (final n in nodes) {
          _box(Rect.fromCenter(center: n, width: 220, height: 72), fill: c.menuTile, stroke: c.lineDashed, radius: 36);
        }
      case 'story':
        const w = (1040 - 2 * 32) / 3, h = 190.0;
        for (var i = 0; i < 6; i++) {
          final x = (i % 3) * (w + 32);
          final y = (i ~/ 3) * (h + 120);
          _box(Rect.fromLTWH(x, y, w, h), stroke: c.textFaint, radius: 4);
          canvas
            ..drawLine(Offset(x, y + h + 32), Offset(x + w, y + h + 32), _rule)
            ..drawLine(Offset(x, y + h + 68), Offset(x + w * 0.7, y + h + 68), _rule);
        }
      case 'lab':
        const sections = ['Aim', 'Materials', 'Method', 'Results', 'Conclusion'];
        for (var i = 0; i < sections.length; i++) {
          final y = i * 236.0;
          _label(sections[i], Offset(0, y), color: c.green, size: 18, weight: FontWeight.w700);
          for (var l = 0; l < 4; l++) {
            canvas.drawLine(Offset(0, y + 64 + l * 40), Offset(1000, y + 64 + l * 40), _rule);
          }
        }
    }
  }
}

/// Draws the small preview for a built-in template (Templates.dc.html),
/// in the design's 200×112 box stretched to [size].
void paintTemplatePreview(Canvas canvas, Size size, String id, EndlessColors c) {
  canvas.drawRect(Offset.zero & size, Paint()..color = c.surface);
  switch (id) {
    case 'dots':
      final dot = Paint()..color = c.lineStrong;
      for (var y = 6.0; y < size.height; y += 12) {
        for (var x = 6.0; x < size.width; x += 12) {
          canvas.drawCircle(Offset(x, y), 1.2, dot);
        }
      }
      return;
    case 'lined':
      final line = Paint()..color = c.paperLine;
      for (var y = 13.0; y < size.height; y += 14) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
      }
      canvas.drawRect(Rect.fromLTWH(24, 0, 1, size.height), Paint()..color = c.paperMargin);
      return;
    case 'graph':
      final line = Paint()..color = c.paperGrid;
      for (var y = 13.0; y < size.height; y += 14) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
      }
      for (var x = 13.0; x < size.width; x += 14) {
        canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), line);
      }
      return;
  }
  canvas
    ..save()
    ..scale(size.width / 200, size.height / 112);
  Paint stroke(Color color, double w) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;
  void lines(String d, Color color, double w) => canvas.drawPath(_path(d), stroke(color, w));
  void rrect(double x, double y, double w, double h, double r, {Color? fill, Color? line, double lw = 1.5}) {
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));
    if (fill != null) canvas.drawRRect(rr, Paint()..color = fill);
    if (line != null) canvas.drawRRect(rr, stroke(line, lw));
  }

  final muted = c.lineStrong;
  switch (id) {
    case 'cornell':
      lines('M0 22h200M60 22v64M0 86h200', c.accent, 1.5);
      lines('M70 36h110M70 48h96M70 60h118M70 72h80M10 36h40M10 48h32M10 98h150', muted, 3);
    case 'meeting':
      lines('M12 16h70', c.text, 5);
      lines('M12 30h40M110 30h60M12 48h170M12 58h150M12 68h160', muted, 3);
      rrect(12, 82, 8, 8, 1.5, line: c.accent);
      rrect(12, 96, 8, 8, 1.5, line: c.accent);
      lines('M28 86h90M28 100h70', muted, 3);
    case 'weekly':
      for (final (x, y, w) in [(8.0, 8.0, 42.0), (56.0, 8.0, 42.0), (104.0, 8.0, 42.0), (152.0, 8.0, 40.0),
        (8.0, 60.0, 42.0), (56.0, 60.0, 42.0), (104.0, 60.0, 42.0)]) {
        rrect(x, y, w, 44, 3, line: muted);
      }
      rrect(152, 60, 40, 44, 3, fill: c.stickyYellow);
    case 'todo':
      for (final y in [14.0, 36.0, 58.0, 80.0]) {
        rrect(14, y, 10, 10, 2, line: c.accent);
      }
      lines('M16 19l3 3 5-7', c.accent, 2);
      lines('M34 19h110M34 41h90M34 63h124M34 85h70', muted, 3);
    case 'kanban':
      for (final x in [8.0, 71.0, 134.0]) {
        rrect(x, 8, 58, 96, 4, fill: c.menuTile);
      }
      for (final (x, y) in [(13.0, 18.0), (13.0, 41.0), (76.0, 18.0), (139.0, 18.0), (139.0, 41.0), (139.0, 64.0)]) {
        rrect(x, y, 48, 18, 3, fill: c.surface, line: c.line, lw: 1);
      }
    case 'mind':
      lines('M100 56L40 22M100 56L40 90M100 56L160 22M100 56L160 90M100 56L100 14', muted, 2);
      final oval = Rect.fromCenter(center: const Offset(100, 56), width: 60, height: 32);
      canvas
        ..drawOval(oval, Paint()..color = c.accentTint)
        ..drawOval(oval, stroke(c.accent, 1.5));
      for (final (x, y) in [(18.0, 14.0), (18.0, 82.0), (142.0, 14.0), (142.0, 82.0)]) {
        rrect(x, y, 40, 16, 8, fill: c.menuTile, line: c.lineDashed, lw: 1);
      }
    case 'story':
      for (final (x, y) in [(10.0, 10.0), (73.0, 10.0), (136.0, 10.0), (10.0, 60.0), (73.0, 60.0), (136.0, 60.0)]) {
        rrect(x, y, 54, 34, 2, line: c.textFaint);
      }
      lines('M10 50h40M73 50h36M136 50h44M10 100h30M73 100h42M136 100h36', muted, 3);
    case 'lab':
      lines('M12 16h60M12 46h44M12 76h52', c.green, 4);
      lines('M12 28h170M12 36h140M12 58h160M12 66h120M12 88h170M12 96h100', muted, 3);
  }
  canvas.restore();
}

/// Tiny parser for the M/h/v/l/L commands the previews use.
Path _path(String d) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVv]|-?\d*\.?\d+').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = 'M';
  var x = 0.0, y = 0.0;
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (RegExp(r'[A-Za-z]').hasMatch(tokens[i])) cmd = tokens[i++];
    switch (cmd) {
      case 'M':
        x = next();
        y = next();
        path.moveTo(x, y);
        cmd = 'L';
      case 'L':
        x = next();
        y = next();
        path.lineTo(x, y);
      case 'l':
        x += next();
        y += next();
        path.lineTo(x, y);
      case 'h':
        x += next();
        path.lineTo(x, y);
      case 'v':
        y += next();
        path.lineTo(x, y);
      default:
        i++;
    }
  }
  return path;
}

// "My templates": a saved page (its paper, layout and items).

class UserTemplate {
  const UserTemplate({
    required this.id,
    required this.name,
    required this.paper,
    this.layout,
    required this.items,
    required this.createdAt,
  });

  final String id;
  final String name;
  final Paper paper;
  final String? layout;

  /// Items as stored JSON; each use gets fresh ids.
  final List<Json> items;
  final DateTime createdAt;

  /// The template's page with new item ids, ready to insert.
  List<Item> freshItems() {
    final now = DateTime.now().toUtc();
    return [
      for (final j in items) decodeItem({...j, 'id': newId('it'), 'createdAt': now.toIso8601String()}),
    ];
  }

  BoardPage previewPage() => BoardPage(id: id, paper: paper, template: layout, items: [for (final j in items) decodeItem(j)]);

  Json toJson() => {
        'format': 'endless.template',
        'id': id,
        'name': name,
        'paper': paper.name,
        'template': layout,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'items': items,
      };

  static UserTemplate? fromJson(Json j) {
    if (j['format'] != 'endless.template' || j['id'] is! String) return null;
    return UserTemplate(
      id: j['id'] as String,
      name: j['name'] as String? ?? 'My template',
      paper: paperFromName(j['paper'] as String?),
      layout: j['template'] as String?,
      items: [for (final i in (j['items'] as List? ?? const [])) (i as Map).cast<String, dynamic>()],
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.utc(2026),
    );
  }
}

Future<List<UserTemplate>> loadUserTemplates(BoardStore store) async {
  final list = [
    for (final j in await store.loadTemplates()) ?UserTemplate.fromJson(j),
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return list;
}

final initialTemplatesProvider = Provider<List<UserTemplate>>((ref) => const []);

final userTemplatesProvider = NotifierProvider<UserTemplatesNotifier, List<UserTemplate>>(UserTemplatesNotifier.new);

class UserTemplatesNotifier extends Notifier<List<UserTemplate>> {
  @override
  List<UserTemplate> build() => ref.read(initialTemplatesProvider);

  /// Saves [page] as a template called [name].
  Future<UserTemplate> saveFromPage(BoardPage page, String name) async {
    final t = UserTemplate(
      id: newId('tp'),
      name: name.trim().isEmpty ? 'My template' : name.trim(),
      paper: page.paper,
      layout: page.template is String ? page.template as String : null,
      items: [for (final i in page.items) i.toJson()],
      createdAt: DateTime.now().toUtc(),
    );
    await ref.read(boardStoreProvider).saveTemplate(t.id, t.toJson());
    state = [...state, t];
    return t;
  }

  Future<void> delete(String id) async {
    await ref.read(boardStoreProvider).deleteTemplate(id);
    state = state.where((t) => t.id != id).toList();
  }
}
