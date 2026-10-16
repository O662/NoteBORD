import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../recognition/convert.dart';
import '../../recognition/handwriting_index.dart';
import '../../recognition/models.dart';
import '../../recognition/recognized.dart';
import '../../recognition/recognizer.dart';
import '../../state/device_keyboard.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../icons.dart';

/// Convert to text (Convert.dc.html): the recognized text to check and
/// correct, other readings of words it wasn't sure of, the language, and
/// what happens to the ink. Nothing changes until Convert.
class ConvertPanel extends ConsumerStatefulWidget {
  const ConvertPanel({
    super.key,
    required this.strokes,
    required this.onCancel,
    required this.onConvert,
    this.onWholePage,
  });

  /// The handwriting to convert, in pen order.
  final List<StrokeItem> strokes;
  final VoidCallback onCancel;
  final void Function(String text, ConvertPlace place) onConvert;

  /// "Convert the whole page", or null when this is the whole page.
  final VoidCallback? onWholePage;

  static const width = 580.0;

  @override
  ConsumerState<ConvertPanel> createState() => _ConvertPanelState();
}

enum _Phase { reading, ready, unavailable, failed }

class _ConvertPanelState extends ConsumerState<ConvertPanel> {
  late final _text = _PreviewText();
  final _keys = FocusNode();
  late String _language;
  var _phase = _Phase.reading;
  var _place = ConvertPlace.replace;
  List<UnsureWord> _unsure = const [];
  int _focus = 0;
  int _reading = 0;

  @override
  void initState() {
    super.initState();
    _language = handwritingLanguage(ref.read(settingsProvider));
    _text.addListener(_moved);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _read();
    });
  }

  @override
  void didUpdateWidget(ConvertPanel old) {
    super.didUpdateWidget(old);
    if (old.strokes.length != widget.strokes.length ||
        old.strokes.indexed.any((e) => e.$2.id != widget.strokes[e.$1].id)) {
      _read();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _keys.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final index = ref.read(handwritingIndexProvider);
    final mine = ++_reading;
    if (!index.canRecognize) {
      setState(() => _phase = _Phase.unavailable);
      return;
    }
    setState(() {
      _phase = _Phase.reading;
      _unsure = const [];
      _text.unsure = const [];
      _text.text = '';
    });
    PageRecognition read;
    try {
      read = await index.read(widget.strokes, language: _language);
    } on Object catch (e) {
      // Whatever went wrong, the panel says so instead of reading forever.
      debugPrint('Convert to text: $e');
      if (mounted && mine == _reading) setState(() => _phase = _Phase.failed);
      return;
    }
    if (!mounted || mine != _reading) return;
    final preview = previewOf(read);
    setState(() {
      _phase = _Phase.ready;
      _unsure = preview.unsure;
      _focus = 0;
      _text.unsure = preview.unsure;
      _text.text = preview.text;
    });
  }

  void _pickLanguage(String tag) {
    if (tag == _language) return;
    setState(() => _language = tag);
    _read();
  }

  /// The cursor moved: an unsure word it's on becomes the one the chips are for.
  void _moved() {
    final at = _text.selection.baseOffset;
    if (at < 0) return;
    final ranges = tokenRanges(_text.text);
    final token = ranges.indexWhere((r) => at >= r.$1 && at <= r.$2);
    final i = _unsure.indexWhere((u) => u.token == token);
    if (i >= 0 && i != _focus) setState(() => _focus = i);
  }

  /// Brings up the tablet's keyboard. When it doesn't come up and Android
  /// says a physical keyboard is attached, says so, with the setting that
  /// changes it.
  Future<void> _showKeyboard() async {
    if (_keys.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _keys.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) => SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
    }
    final keyboard = ref.read(deviceKeyboardProvider);
    // The keyboard takes a moment to slide in.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted || View.of(context).viewInsets.bottom > 0) return;
    if (!await keyboard.heldBack() || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: const Text(
        'Your tablet thinks a physical keyboard is connected, so it won’t show the on-screen one. '
        'Turn on “Show on-screen keyboard” in its keyboard settings.',
      ),
      width: 520,
      duration: const Duration(seconds: 8),
      action: SnackBarAction(label: 'Settings', onPressed: keyboard.openSettings),
    ));
  }

  /// Deletes what's selected, or the character before the cursor (the last
  /// one when there's no cursor).
  void _backspace() {
    final v = _text.value;
    final t = v.text;
    final sel = v.selection;
    String text;
    int at;
    if (sel.isValid && !sel.isCollapsed) {
      text = t.replaceRange(sel.start, sel.end, '');
      at = sel.start;
    } else {
      final end = sel.isValid ? sel.baseOffset.clamp(0, t.length) : t.length;
      if (end == 0) return;
      final kept = t.substring(0, end).characters.skipLast(1).toString();
      text = kept + t.substring(end);
      at = kept.length;
    }
    _text.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at));
    setState(() {});
  }

  void _choose(UnsureWord u, String word) {
    final text = replaceToken(_text.text, u.token, word);
    _text.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    setState(() {});
  }

  String _current(UnsureWord u) {
    final ranges = tokenRanges(_text.text);
    if (u.token >= ranges.length) return '';
    final (s, e) = ranges[u.token];
    return coreOf(_text.text.substring(s, e)).$2;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = ref.watch(inkModelsProvider);
    final downloading = _phase == _Phase.reading && note?.phase == ModelPhase.downloading && note?.language == _language;
    final name = inkLanguage(_language).name;
    final status = switch (_phase) {
      _Phase.reading => downloading ? note!.text : 'Reading your handwriting…',
      _Phase.unavailable => 'Handwriting recognition runs on the tablet. Type the text here to put it on the page.',
      _Phase.failed => 'Couldn’t read this in $name. Connect to the internet once so the $name model can download, '
          'then try again, or type the text here.',
      _Phase.ready when _text.text.trim().isEmpty => 'Couldn’t make out any words here. Type them, or try another language.',
      _ => null,
    };
    final canConvert = _phase != _Phase.reading && _text.text.trim().isNotEmpty;
    final u = _unsure.isEmpty ? null : _unsure[_focus.clamp(0, _unsure.length - 1)];

    return Semantics(
      container: true,
      label: 'Handwriting to text',
      explicitChildNodes: true,
      child: Container(
        width: ConvertPanel.width,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Radii.dialog),
          boxShadow: c.dialogShadow,
        ),
        // Scrolls when the on-screen keyboard leaves too little room.
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
            Row(spacing: 10, children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Convert to text', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
                ),
              ),
              _LanguageButton(language: _language, onPick: _pickLanguage),
              Transform.translate(
                offset: const Offset(10, 0),
                child: _IconTap(label: 'Close', icon: EIcons.close, onTap: widget.onCancel),
              ),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
              Semantics(
                label: 'Recognized text, editable',
                textField: true,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.accent, width: 1.5),
                    borderRadius: BorderRadius.circular(Radii.button),
                  ),
                  child: TextField(
                    controller: _text,
                    focusNode: _keys,
                    readOnly: _phase == _Phase.reading,
                    minLines: 1,
                    maxLines: 6,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 22, height: 1.35, color: c.text),
                    cursorColor: c.accent,
                    decoration: const InputDecoration.collapsed(hintText: ''),
                  ),
                ),
              ),
              // Under the text, on the right: the keyboard, and backspace (hold to keep deleting).
              // They count as part of the text: on Android an S Pen tap outside a text field
              // takes the cursor out of it, which would close the keyboard as it opens.
              TextFieldTapRegion(
                child: Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 4, children: [
                  _IconTap(
                    label: 'Show keyboard',
                    icon: EIcons.keyboard,
                    onTap: _phase == _Phase.reading ? null : _showKeyboard,
                  ),
                  _HoldTap(
                    label: 'Backspace',
                    icon: EIcons.backspace,
                    onTap: _phase == _Phase.reading || _text.text.isEmpty ? null : _backspace,
                  ),
                ]),
              ),
            ]),
            if (status != null)
              Row(spacing: 8, children: [
                if (_phase == _Phase.reading)
                  SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
                Expanded(child: Text(status, style: TextStyle(fontSize: 13, height: 1.35, color: c.textMuted))),
                if (_phase == _Phase.failed) _TextTap(label: 'Try again', onTap: _read),
              ]),
            if (u != null)
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(
                  _unsure.length == 1 ? 'Not sure about one word:' : 'Not sure about ${_unsure.length} words:',
                  style: TextStyle(fontSize: 13, color: c.textMuted),
                ),
                for (final option in u.options)
                  _Chip(
                    label: option,
                    selected: plainWord(option) == plainWord(_current(u)),
                    onTap: () => _choose(u, option),
                  ),
                if (_unsure.length > 1)
                  _IconTap(
                    label: 'Next word I’m not sure of',
                    icon: EIcons.chevronRight,
                    size: 36,
                    onTap: () => setState(() => _focus = (_focus + 1) % _unsure.length),
                  ),
              ]),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
              Semantics(
                header: true,
                child: Text('THEN', style: TypeScale.sectionLabel.copyWith(color: c.textMuted)),
              ),
              _Places(place: _place, onPick: (p) => setState(() => _place = p)),
            ]),
            Row(children: [
              if (widget.onWholePage != null) _TextTap(label: 'Convert the whole page', onTap: widget.onWholePage!),
              const Spacer(),
              _Button(label: 'Cancel', onTap: widget.onCancel),
              const SizedBox(width: 8),
              _Button(
                label: _place == ConvertPlace.copy ? 'Copy text' : 'Convert',
                primary: true,
                onTap: canConvert ? () => widget.onConvert(_text.text.trim(), _place) : null,
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The preview's text, with the words recognition wasn't sure of underlined
/// in dots (while they still read as one of its readings).
class _PreviewText extends TextEditingController {
  List<UnsureWord> unsure = const [];

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (unsure.isEmpty || (withComposing && value.isComposingRangeValid)) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final ranges = tokenRanges(text);
    final marked = <(int, int)>[
      for (final u in unsure)
        if (u.token < ranges.length)
          if (u.options.any((o) => plainWord(o) == plainWord(coreOf(text.substring(ranges[u.token].$1, ranges[u.token].$2)).$2)))
            ranges[u.token],
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final dotted = TextStyle(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: context.colors.clay,
      decorationThickness: 2,
    );
    final children = <TextSpan>[];
    var at = 0;
    for (final (s, e) in marked) {
      if (s < at) continue;
      if (s > at) children.add(TextSpan(text: text.substring(at, s)));
      children.add(TextSpan(text: text.substring(s, e), style: dotted));
      at = e;
    }
    if (at < text.length) children.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: children);
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.language, required this.onPick});

  final String language;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<String>(
      tooltip: '',
      onSelected: onPick,
      color: c.surface,
      constraints: const BoxConstraints(maxHeight: 420),
      itemBuilder: (context) => [
        for (final l in inkLanguages)
          PopupMenuItem(
            value: l.tag,
            height: 44,
            child: Text(
              l.name,
              style: TextStyle(fontSize: 14, fontWeight: l.tag == language ? FontWeight.w600 : FontWeight.w400, color: c.text),
            ),
          ),
      ],
      child: Semantics(
        button: true,
        label: 'Handwriting language: ${inkLanguage(language).name}',
        excludeSemantics: true,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: c.lineStrong),
            borderRadius: BorderRadius.circular(Radii.key),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            Text(inkLanguage(language).name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.text)),
            EIcon(EIcons.chevronDown, size: 14, color: c.text),
          ]),
        ),
      ),
    );
  }
}

/// Replace the ink / Keep ink too / Copy text only.
class _Places extends StatelessWidget {
  const _Places({required this.place, required this.onPick});

  final ConvertPlace place;
  final ValueChanged<ConvertPlace> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: 'What happens to the ink',
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(spacing: 2, children: [
          for (final p in ConvertPlace.values)
            Expanded(
              child: Semantics(
                inMutuallyExclusiveGroup: true,
                checked: p == place,
                button: true,
                label: p.label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(p),
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p == place ? c.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: p == place
                          ? [BoxShadow(color: c.shadow.withValues(alpha: 0.15), offset: const Offset(0, 1), blurRadius: 2)]
                          : null,
                    ),
                    child: Text(
                      p.label,
                      style: TextStyle(fontSize: 14, fontWeight: p == place ? FontWeight.w600 : FontWeight.w500, color: c.text),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.inverse : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? c.inverse : c.lineStrong)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // As wide as the word: a Wrap lets children be as wide as it is.
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: selected ? c.onInverse : c.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap, this.primary = false});

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    final bg = primary ? (enabled ? c.inverse : c.inverse.withValues(alpha: 0.4)) : Colors.transparent;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          side: primary ? BorderSide.none : BorderSide(color: c.lineStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: Container(
            height: 46,
            padding: EdgeInsets.symmetric(horizontal: primary ? 20 : 18),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
                color: primary ? c.onInverse : c.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextTap extends StatelessWidget {
  const _TextTap({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.small),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.accent)),
          ),
        ),
      );
}

class _IconTap extends StatelessWidget {
  const _IconTap({required this.label, required this.icon, required this.onTap, this.size = 44});

  final String label;
  final EIconData icon;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        excludeSemantics: true,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.button),
            onTap: onTap,
            child: SizedBox.square(
              dimension: size,
              child: Center(child: EIcon(icon, size: 18, color: context.colors.textMuted)),
            ),
          ),
        ),
      );
}

/// A button that acts once when pressed, then again and again while it's
/// held (backspace).
class _HoldTap extends StatefulWidget {
  const _HoldTap({required this.label, required this.icon, required this.onTap});

  final String label;
  final EIconData icon;
  final VoidCallback? onTap;

  @override
  State<_HoldTap> createState() => _HoldTapState();
}

class _HoldTapState extends State<_HoldTap> {
  Timer? _repeat;
  bool _down = false;

  void _press() {
    final tap = widget.onTap;
    if (tap == null) return;
    tap();
    setState(() => _down = true);
    _repeat = Timer(const Duration(milliseconds: 450), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 70), (_) => widget.onTap?.call());
    });
  }

  void _release() {
    _repeat?.cancel();
    _repeat = null;
    if (_down) setState(() => _down = false);
  }

  @override
  void didUpdateWidget(_HoldTap old) {
    super.didUpdateWidget(old);
    // Nothing left to delete: stop.
    if (widget.onTap == null) _release();
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _press(),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: Opacity(
          opacity: widget.onTap == null ? 0.4 : 1,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _down ? c.side : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.button),
            ),
            child: Center(child: EIcon(widget.icon, size: 18, color: c.textMuted)),
          ),
        ),
      ),
    );
  }
}
