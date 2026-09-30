import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../board/model.dart';
import '../../canvas/canvas_view.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' show FontFamilies, Radii;
import '../common.dart';
import '../icons.dart';

/// Sizes the A− and A+ buttons step through (page px).
const textSizes = [14.0, 18.0, 22.0, 28.0, 36.0, 48.0, 64.0];

/// What's being typed on the page: a new text box, an existing one, or the
/// text on a sticky note.
class TextEditSession {
  TextEditSession({
    required this.pageId,
    this.target,
    required this.origin,
    this.angle = 0,
    required this.wrap,
    required this.autoWidth,
    required this.font,
    required this.size,
    required this.color,
    String text = '',
    this.onPaper = false,
  }) : controller = TextEditingController(text: text) {
    controller.selection = TextSelection.collapsed(offset: text.length);
  }

  final String pageId;

  /// The text box or sticky note being edited, or null for a new text box.
  final BoxItem? target;

  /// Where the text's top-left corner is on the page, and its rotation.
  final Offset origin;
  final double angle;

  /// Where it wraps; with [autoWidth] the box grows with the text up to it.
  final double wrap;
  final bool autoWidth;
  String font;
  double size;
  final Color color;

  /// On a sticky note: the paper and its text look the same in dark mode.
  final bool onPaper;

  final TextEditingController controller;
  final focus = FocusNode();
  final undo = UndoHistoryController();

  void dispose() {
    controller.dispose();
    focus.dispose();
    undo.dispose();
  }
}

/// The text field over the page while typing, with its font and size bar.
/// It follows the page as it pans and zooms.
class TextEditor extends StatefulWidget {
  const TextEditor({
    super.key,
    required this.session,
    required this.view,
    required this.onDone,
    required this.onStyle,
    this.chrome = EdgeInsets.zero,
  });

  final TextEditSession session;
  final CanvasView view;
  final VoidCallback onDone;

  /// The font or size changed.
  final VoidCallback onStyle;

  /// How far the floating chrome reaches in from each edge.
  final EdgeInsets chrome;

  @override
  State<TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<TextEditor> {
  final _field = GlobalKey();
  Object? _checked;

  TextEditSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(TextEditor old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.controller.removeListener(_changed);
      s.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    s.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Keeps the bottom of the text on screen as it grows or the keyboard
  /// comes up. Runs when the text or the space changes, not when the page
  /// is panned, so you can still look elsewhere while typing.
  void _keepVisible(Size space) {
    final key = (s.controller.text, s.size, s.font, space);
    if (key == _checked) return;
    _checked = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final field = _field.currentContext?.findRenderObject();
      final host = context.findRenderObject();
      if (field is! RenderBox || host is! RenderBox || !field.hasSize) return;
      final corners = [
        for (final p in [Offset.zero, field.size.bottomRight(Offset.zero), field.size.bottomLeft(Offset.zero)])
          field.localToGlobal(p, ancestor: host),
      ];
      final bottom = corners.map((p) => p.dy).reduce(math.max);
      final limit = space.height - math.max(widget.chrome.bottom, 12) - 8;
      if (bottom > limit) widget.view.panBy(Offset(0, limit - bottom));
    });
  }

  void _setFont(String font) {
    s.font = font;
    widget.onStyle();
    s.focus.requestFocus();
  }

  void _step(int direction) {
    final at = textSizes.indexWhere((v) => v >= s.size - 0.01);
    final i = direction > 0
        ? textSizes.indexWhere((v) => v > s.size + 0.01)
        : (at < 0 ? textSizes.length : at) - 1;
    if (i < 0 || i >= textSizes.length) return;
    s.size = textSizes[i];
    widget.onStyle();
    s.focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final brightness = s.onPaper ? Brightness.light : Theme.of(context).brightness;
    final style = textStyleFor(s.font, s.size, color: displayInk(s.color, brightness));

    final field = MediaQuery.withNoTextScaling(
      child: CallbackShortcuts(
        // Undo and redo what was typed, not the page, while typing.
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): s.undo.undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): s.undo.redo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): s.undo.redo,
        },
        child: TextField(
          key: _field,
          controller: s.controller,
          focusNode: s.focus,
          undoController: s.undo,
          autofocus: true,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          style: style,
          cursorColor: s.onPaper ? s.color : c.accent,
          scrollPadding: EdgeInsets.zero,
          decoration: const InputDecoration.collapsed(hintText: null),
          onTapOutside: (_) => widget.onDone(),
        ),
      ),
    );

    return LayoutBuilder(builder: (context, box) {
      _keepVisible(box.biggest);
      return ListenableBuilder(
        listenable: widget.view,
        builder: (context, _) {
          final scale = widget.view.scale;
          final at = widget.view.toScreen(s.origin);
          final lines = layoutText(s.controller.text, s.font, s.size, s.wrap);
          final height = lines.height * scale;
          lines.dispose();
          // The bar sits above the text, or below it under the top chrome.
          var barTop = at.dy - 60;
          if (barTop < widget.chrome.top) barTop = at.dy + height + 14;
          barTop = barTop.clamp(0.0, math.max(0.0, box.maxHeight - 56)).toDouble();
          final barLeft = (at.dx - 8).clamp(widget.chrome.left, math.max(widget.chrome.left, box.maxWidth - 330)).toDouble();

          return Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: at.dx,
              top: at.dy,
              child: Transform(
                transform: Matrix4.identity()
                  ..rotateZ(s.angle)
                  ..scaleByDouble(scale, scale, 1, 1),
                child: Transform.translate(
                  // The outline sits around the text, which stays at the origin.
                  offset: const Offset(-7.5, -5.5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: c.accent, width: 1.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ConstrainedBox(
                      constraints: s.autoWidth
                          ? BoxConstraints(minWidth: s.size * 2, maxWidth: s.wrap)
                          : BoxConstraints.tightFor(width: s.wrap),
                      child: s.autoWidth ? IntrinsicWidth(child: field) : field,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(left: barLeft, top: barTop, child: TextFieldTapRegion(child: _bar(c))),
          ]);
        },
      );
    });
  }

  Widget _bar(EndlessColors c) {
    Widget font(String id, String label, String family) => ChromeButton(
          label: label,
          width: 40,
          height: 40,
          radius: Radii.key,
          selected: s.font == id,
          onPressed: () => _setFont(id),
          child: Text(
            'Aa',
            style: TextStyle(
              fontFamily: family,
              fontSize: id == 'hand' ? 20 : 16,
              fontWeight: FontWeight.w500,
              color: s.font == id ? c.onInverse : c.text,
            ),
          ),
        );
    Widget size(String label, String text, int direction, bool enabled) => ChromeButton(
          label: label,
          width: 40,
          height: 40,
          radius: Radii.key,
          enabled: enabled,
          onPressed: () => _step(direction),
          child: Text(
            text,
            style: TextStyle(
              fontSize: direction > 0 ? 17 : 13,
              fontWeight: FontWeight.w600,
              color: c.text.withValues(alpha: enabled ? 1 : 0.35),
            ),
          ),
        );
    return Semantics(
      container: true,
      label: 'Text style',
      explicitChildNodes: true,
      child: Pill(
        radius: 12,
        padding: const EdgeInsets.all(3),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          font('ui', 'Plain font', FontFamilies.ui),
          font('serif', 'Serif font', FontFamilies.serif),
          font('hand', 'Handwriting font', FontFamilies.handwritingSample),
          const PillDivider(),
          size('Smaller text', 'A', -1, s.size > textSizes.first + 0.01),
          size('Larger text', 'A', 1, s.size < textSizes.last - 0.01),
          const PillDivider(),
          ChromeButton(
            label: 'Done typing',
            width: null,
            padding: 12,
            height: 40,
            radius: Radii.key,
            background: c.inverse,
            foreground: c.onInverse,
            onPressed: widget.onDone,
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              EIcon(EIcons.check, size: 16, color: c.onInverse),
              Text('Done', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.onInverse)),
            ]),
          ),
        ]),
      ),
    );
  }
}
