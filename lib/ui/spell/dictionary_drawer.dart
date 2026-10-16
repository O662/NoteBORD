import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../spelling/dictionary.dart';
import '../../spelling/speech.dart';
import '../../spelling/spelling_state.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../icons.dart';

/// How many recent lookups are kept.
const recentLookupsKept = 8;

/// The dictionary and thesaurus drawer (Spell.dc.html's aside): look up a
/// word, its meanings with examples, similar words and opposites, recent
/// lookups, and "Add definition to page". Works offline.
class DictionaryDrawer extends ConsumerStatefulWidget {
  const DictionaryDrawer({
    super.key,
    this.query,
    this.serial = 0,
    required this.onClose,
    required this.onAddDefinition,
    required this.onFlashcard,
  });

  /// A word to look up as it opens (or when [serial] changes).
  final String? query;
  final int serial;
  final VoidCallback onClose;
  final void Function(DictEntry entry, DictSense sense) onAddDefinition;
  final VoidCallback onFlashcard;

  static const width = 400.0;

  @override
  ConsumerState<DictionaryDrawer> createState() => _DictionaryDrawerState();
}

enum _Tab { dictionary, thesaurus }

class _DictionaryDrawerState extends ConsumerState<DictionaryDrawer> {
  final _field = TextEditingController();
  Timer? _typing;
  var _tab = _Tab.dictionary;
  DictEntry? _entry;

  /// What was looked up and not found.
  String? _missing;
  List<String> _didYouMean = const [];
  int _looking = 0;

  @override
  void initState() {
    super.initState();
    if (widget.query case final q? when q.trim().isNotEmpty) {
      _field.text = q;
      _lookUp(q);
    }
  }

  @override
  void didUpdateWidget(DictionaryDrawer old) {
    super.didUpdateWidget(old);
    if (widget.serial != old.serial && widget.query != null) {
      _field.text = widget.query!;
      setState(() => _tab = _Tab.dictionary);
      _lookUp(widget.query!);
    }
  }

  @override
  void dispose() {
    _typing?.cancel();
    _field.dispose();
    super.dispose();
  }

  /// Looks [word] up; [remember] puts it in Recent.
  Future<void> _lookUp(String word, {bool remember = true}) async {
    _typing?.cancel();
    final mine = ++_looking;
    final query = word.trim();
    if (query.isEmpty) {
      setState(() {
        _entry = null;
        _missing = null;
      });
      return;
    }
    final Dictionary dictionary;
    try {
      dictionary = await ref.read(dictionaryProvider.future);
    } on Object catch (e) {
      debugPrint('Dictionary: $e');
      return;
    }
    if (!mounted || mine != _looking) return;
    final entry = dictionary.lookup(query);
    var didYouMean = const <String>[];
    if (entry == null) {
      try {
        final speller = await ref.read(spellerProvider.future);
        didYouMean = [
          for (final s in speller.suggest(query))
            if (dictionary.lookup(s) != null) s,
        ];
      } on Object catch (e) {
        debugPrint('Dictionary: $e');
      }
      if (!mounted || mine != _looking) return;
    }
    setState(() {
      _entry = entry;
      _missing = entry == null ? query : null;
      _didYouMean = didYouMean;
    });
    if (entry != null && remember) {
      ref.read(settingsProvider.notifier).apply((s) => s.copyWith(recentLookups: [
            entry.word,
            for (final w in s.recentLookups)
              if (w.toLowerCase() != entry.word.toLowerCase()) w,
          ].take(recentLookupsKept).toList()));
    }
  }

  /// A word tapped in the drawer: shown in the field and looked up.
  void _go(String word) {
    _field.text = word;
    setState(() => _tab = _Tab.dictionary);
    _lookUp(word);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final opening = ref.watch(dictionaryProvider).isLoading;
    final recent = ref.watch(settingsProvider.select((s) => s.recentLookups));
    final entry = _entry;
    return Semantics(
      container: true,
      label: 'Dictionary and thesaurus',
      explicitChildNodes: true,
      child: Container(
        width: DictionaryDrawer.width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Radii.dialog),
          boxShadow: c.dialogShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
          Row(spacing: 6, children: [
            Expanded(child: _SearchField(controller: _field, onSubmit: _lookUp, onChanged: _changed)),
            _RoundButton(label: 'Close the dictionary', icon: EIcons.close, onTap: widget.onClose, size: 44, border: false),
          ]),
          _Tabs(tab: _tab, onPick: (t) => setState(() => _tab = t)),
          Expanded(
            child: entry != null
                ? _EntryView(entry: entry, tab: _tab, onWord: _go)
                : _Placeholder(opening: opening, missing: _missing, didYouMean: _didYouMean, onWord: _go),
          ),
          if (recent.isNotEmpty)
            Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Semantics(header: true, child: Text('RECENT', style: TypeScale.sectionLabel.copyWith(color: c.textMuted))),
              // One row, as many as fit.
              ClipRect(
                child: SizedBox(
                  height: 44,
                  child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (final w in recent) _Pill(label: w, onTap: () => _go(w)),
                  ]),
                ),
              ),
            ]),
          Row(spacing: 8, children: [
            Expanded(
              child: _Button(
                label: 'Add definition to page',
                primary: true,
                onTap: entry == null ? null : () => widget.onAddDefinition(entry, entry.senses.first),
              ),
            ),
            _Button(label: 'Make flashcard', onTap: entry == null ? null : widget.onFlashcard),
          ]),
          Text('Works offline · English (US)', style: TextStyle(fontSize: 12, color: c.textMuted)),
        ]),
      ),
    );
  }

  void _changed(String text) {
    _typing?.cancel();
    // Looked up as you type, after a pause; only a search or a tap goes in Recent.
    _typing = Timer(const Duration(milliseconds: 400), () => _lookUp(text, remember: false));
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onSubmit, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(Radii.button),
      ),
      child: Row(spacing: 10, children: [
        EIcon(EIcons.search, size: 18, color: c.textMuted),
        Expanded(
          child: Semantics(
            label: 'Look up a word',
            textField: true,
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmit,
              onChanged: onChanged,
              style: TextStyle(fontSize: 16, color: c.text),
              cursorColor: c.accent,
              decoration: InputDecoration.collapsed(
                hintText: 'Look up a word',
                hintStyle: TextStyle(fontSize: 16, color: c.textFaint),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.onPick});

  final _Tab tab;
  final ValueChanged<_Tab> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: 'Dictionary or thesaurus',
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(spacing: 2, children: [
          for (final (t, label) in [(_Tab.dictionary, 'Dictionary'), (_Tab.thesaurus, 'Thesaurus')])
            Expanded(
              child: Semantics(
                inMutuallyExclusiveGroup: true,
                selected: t == tab,
                button: true,
                label: label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(t),
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t == tab ? c.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: t == tab
                          ? [BoxShadow(color: c.shadow.withValues(alpha: 0.15), offset: const Offset(0, 1), blurRadius: 2)]
                          : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 14, fontWeight: t == tab ? FontWeight.w700 : FontWeight.w500, color: c.text),
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

/// The word, how it's said, and its meanings or its similar words.
class _EntryView extends ConsumerWidget {
  const _EntryView({required this.entry, required this.tab, required this.onWord});

  final DictEntry entry;
  final _Tab tab;
  final ValueChanged<String> onWord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final speech = ref.watch(speechProvider);
    final label = TypeScale.sectionLabel.copyWith(color: c.textMuted);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        Row(spacing: 10, children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: entry.word),
                  if (entry.say != null)
                    TextSpan(
                      text: '   ${entry.say}',
                      // Figtree has no ə: it comes from Newsreader.
                      style: TextStyle(
                        fontFamily: FontFamilies.ui,
                        fontFamilyFallback: const [FontFamilies.serif],
                        fontSize: 14,
                        height: 1,
                        color: c.textMuted,
                      ),
                    ),
                ]),
                style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 34, height: 1.15, color: c.text),
              ),
            ),
          ),
          if (speech.available)
            _RoundButton(label: 'Hear it', icon: EIcons.speaker, onTap: () => speech.say(entry.word)),
        ]),
        if (tab == _Tab.dictionary)
          for (final (wc, senses) in entry.groups) ...[
            Text(wc.label, style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: c.textMuted)),
            for (final (i, s) in senses.indexed) _Sense(number: i + 1, sense: s),
          ]
        else ...[
          Semantics(header: true, child: Text('SIMILAR WORDS', style: label)),
          if (entry.similar.isEmpty)
            Text('None in this dictionary', style: TextStyle(fontSize: 14, color: c.textMuted))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final w in entry.similar) _Pill(label: w, onTap: () => onWord(w), similar: true),
            ]),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(header: true, child: Text('OPPOSITES', style: label)),
          ),
          if (entry.opposites.isEmpty)
            Text('None in this dictionary', style: TextStyle(fontSize: 14, color: c.textMuted))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final w in entry.opposites) _Pill(label: w, onTap: () => onWord(w), opposite: true),
            ]),
        ],
      ]),
    );
  }
}

class _Sense extends StatelessWidget {
  const _Sense({required this.number, required this.sense});

  final int number;
  final DictSense sense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.side, shape: BoxShape.circle),
        child: Text('$number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.text)),
      ),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          Text(sentence(sense.definition), style: TextStyle(fontSize: 15, height: 1.45, color: c.text)),
          if (sense.example != null)
            Text(
              '“${sense.example}”',
              style: TextStyle(fontSize: 14, height: 1.4, fontStyle: FontStyle.italic, color: c.textMuted),
            ),
        ]),
      ),
    ]);
  }
}

/// A definition as a sentence: a capital first, a full stop last.
String sentence(String definition) {
  final d = definition.trim();
  if (d.isEmpty) return d;
  final first = d[0].toUpperCase() + d.substring(1);
  return RegExp(r'[.!?)]$').hasMatch(first) ? first : '$first.';
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.opening, required this.missing, required this.didYouMean, required this.onWord});

  final bool opening;
  final String? missing;
  final List<String> didYouMean;
  final ValueChanged<String> onWord;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (opening) {
      return Align(
        alignment: Alignment.topLeft,
        child: Row(spacing: 10, children: [
          SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
          Text('Opening the dictionary…', style: TextStyle(fontSize: 14, color: c.textMuted)),
        ]),
      );
    }
    if (missing == null) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          'Type a word to see what it means, words like it and its opposites.',
          style: TextStyle(fontSize: 15, height: 1.45, color: c.textMuted),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
      Text('“$missing” isn’t in the dictionary.', style: TextStyle(fontSize: 15, height: 1.45, color: c.text)),
      if (didYouMean.isNotEmpty) ...[
        Text('DID YOU MEAN', style: TypeScale.sectionLabel.copyWith(color: c.textMuted)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final w in didYouMean) _Pill(label: w, onTap: () => onWord(w), similar: true),
        ]),
      ],
    ]);
  }
}

/// A word to tap: a recent lookup, a similar word (blue) or an opposite
/// (clay).
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.similar = false, this.opposite = false});

  final String label;
  final VoidCallback onTap;
  final bool similar;
  final bool opposite;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg, border) = similar
        ? (c.accentTint, c.text, c.accent.withValues(alpha: 0.25))
        : opposite
            ? (c.clayTint, c.clayDeep, null)
            : (c.side, c.text, null);
    final height = similar ? 40.0 : 36.0;
    return Semantics(
      button: true,
      label: 'Look up $label',
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: border == null ? BorderSide.none : BorderSide(color: border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: similar ? 14 : 12),
            child: Center(
              widthFactor: 1,
              child: Text(label, style: TextStyle(fontSize: similar || opposite ? 14 : 13, fontWeight: FontWeight.w600, color: fg)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.label, required this.icon, required this.onTap, this.size = 40, this.border = true});

  final String label;
  final EIconData icon;
  final VoidCallback onTap;
  final double size;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(side: border ? BorderSide(color: c.lineStrong) : BorderSide.none),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: size,
            child: Center(child: EIcon(icon, size: 16, color: border ? c.text : c.textMuted)),
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
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: primary ? c.inverse : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.button),
            side: primary ? BorderSide.none : BorderSide(color: c.lineStrong),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.button),
            onTap: onTap,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
                  color: primary ? c.onInverse : c.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
