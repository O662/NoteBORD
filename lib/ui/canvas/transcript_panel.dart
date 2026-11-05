import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/playback.dart';
import '../../audio/transcript_lines.dart';
import '../../audio/transcription.dart';
import '../../board/model.dart';
import '../../canvas/pane.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../common.dart';
import '../icons.dart';
import 'audio_actions.dart';

/// Audio.png's Transcript panel (420 wide, at the right): the recording's
/// lines with their times and speakers, the one playing highlighted; tap a
/// line to play from there, or a speaker to name them. Search, Close, and
/// Add to page as text, Copy and Export.
///
/// Edit (the pencil, or a long press on a line) makes every line a text
/// field to fix what was misheard; Done saves the changes as one undo
/// step (a line left empty is removed), Cancel drops them.
class TranscriptPanel extends ConsumerStatefulWidget {
  const TranscriptPanel({super.key, required this.pane, required this.itemId, required this.onClose});

  final Pane pane;
  final String itemId;
  final VoidCallback onClose;

  @override
  ConsumerState<TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends ConsumerState<TranscriptPanel> {
  final _scroll = ScrollController();
  final _query = TextEditingController();
  final _current = GlobalKey();
  bool _searching = false;
  int? _shown;

  /// Editing: each line's text as it's being changed, by its start time.
  bool _editing = false;
  final _edits = <int, TextEditingController>{};

  /// The line a long press started editing (its field takes the focus).
  int? _editFrom;

  @override
  void dispose() {
    _scroll.dispose();
    _query.dispose();
    _dropEdits();
    super.dispose();
  }

  void _dropEdits() {
    for (final c in _edits.values) {
      c.dispose();
    }
    _edits.clear();
  }

  void _startEditing({int? at}) => setState(() {
    _editing = true;
    _editFrom = at;
  });

  /// Done: the changed lines are saved (one undo step).
  void _saveEdits() {
    final changes = {for (final e in _edits.entries) e.key: e.value.text};
    editTranscript(ref, widget.pane, widget.itemId, changes);
    _endEditing();
  }

  void _endEditing() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _editing = false;
      _editFrom = null;
      _dropEdits();
    });
  }

  /// Closing keeps what was edited.
  void _close() {
    if (_editing) _saveEdits();
    widget.onClose();
  }

  /// Keeps the line playing in view.
  void _follow(int index) {
    if (_shown == index) return;
    _shown = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _current.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, alignment: 0.25, duration: const Duration(milliseconds: 250));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nbId = widget.pane.notebookId;
    ref.watch(notebookProvider(nbId).select((s) => s.revision));
    final clip = ref.read(notebookProvider(nbId).notifier).mediaClip(widget.itemId)?.$2;
    if (clip == null) {
      // The recording was deleted (or undone): the panel goes with it.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
      return const SizedBox.shrink();
    }
    final play = ref.watch(playbackProvider);
    final progress = ref.watch(transcriptionProvider)[clip.id];
    final error = ref.watch(transcriptErrorsProvider)[clip.id];
    final playing = play != null && play.isOf(nbId, clip.id) ? play : null;

    // The line playing: the last one started.
    var current = -1;
    if (playing != null) {
      for (final (i, l) in clip.transcript.indexed) {
        if (l.tMs <= playing.positionMs) current = i;
      }
      if (current >= 0) _follow(current);
    }

    final q = _query.text.trim().toLowerCase();
    final lines = [
      for (final (i, l) in clip.transcript.indexed)
        if (q.isEmpty || l.text.toLowerCase().contains(q) || clip.speakerName(l.speaker).toLowerCase().contains(q)) (i, l),
    ];
    final language = languageName(clip.language);
    final subtitle = _editing
        ? 'Editing · fix any line, then Done'
        : [clip.name.isEmpty ? 'Recording' : clip.name, if (language.isNotEmpty) language, 'made on this tablet'].join(' · ');

    return Semantics(
      container: true,
      label: 'Transcript',
      explicitChildNodes: true,
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(0, 20), blurRadius: 40, spreadRadius: -24)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        'Transcript',
                        style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 22, color: c.text),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                ChromeButton(
                  label: _editing ? 'Stop editing' : 'Edit transcript',
                  icon: EIcons.pen,
                  selected: _editing,
                  onPressed: clip.transcript.isEmpty ? null : (_editing ? _saveEdits : _startEditing),
                  enabled: clip.transcript.isNotEmpty,
                ),
                ChromeButton(
                  label: 'Search transcript',
                  icon: EIcons.search,
                  selected: _searching,
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _query.clear();
                  }),
                ),
                ChromeButton(label: 'Close transcript', icon: EIcons.close, foreground: c.textMuted, onPressed: _close),
              ],
            ),
            if (_searching)
              TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 15, color: c.text),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Find in the transcript',
                  hintStyle: TextStyle(color: c.textFaint),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: EIcon(EIcons.search, size: 18, color: c.textMuted),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  filled: true,
                  fillColor: c.surfaceSunk,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.line),
                  ),
                ),
              ),
            ?_status(clip, progress, error, c),
            Expanded(
              child: lines.isEmpty
                  ? _empty(clip, q, c)
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: lines.length,
                      itemBuilder: (context, n) {
                        final (i, l) = lines[n];
                        if (_editing) {
                          return _EditLine(
                            key: ValueKey(l.tMs),
                            clip: clip,
                            line: l,
                            controller: _edits.putIfAbsent(l.tMs, () => TextEditingController(text: l.text)),
                            autofocus: l.tMs == _editFrom,
                          );
                        }
                        return _Line(
                          key: i == current ? _current : null,
                          clip: clip,
                          line: l,
                          current: i == current,
                          query: q,
                          onTap: () async {
                            if (!await playMomentOf(ref, nbId, clip, l.tMs)) widget.pane.toast(cantPlay);
                          },
                          onSpeaker: l.speaker == null ? null : () => nameSpeaker(context, ref, widget.pane, clip, l.speaker!),
                          onEdit: () => _startEditing(at: l.tMs),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.lineSoft)),
              ),
              child: Row(
                spacing: 8,
                children: _editing
                    ? [
                        const Spacer(),
                        _Button(label: 'Cancel', onPressed: _endEditing),
                        _Button(label: 'Done', primary: true, onPressed: _saveEdits),
                      ]
                    : [
                        Expanded(
                          child: _Button(
                            label: 'Add to page as text',
                            primary: true,
                            onPressed: clip.transcript.isEmpty
                                ? null
                                : () => addTranscriptAsText(ref, widget.pane, clip, color: ref.read(settingsProvider).penColor),
                          ),
                        ),
                        _Button(label: 'Copy', onPressed: clip.transcript.isEmpty ? null : () => copyTranscript(widget.pane, clip)),
                        _Button(
                          label: 'Export',
                          onPressed: clip.transcript.isEmpty ? null : () => exportTranscript(ref, widget.pane, clip),
                        ),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// How the transcript is going, when it isn't done.
  Widget? _status(Transcribed clip, TranscriptProgress? progress, String? error, EndlessColors c) {
    final String text;
    Widget? action;
    if (error != null || clip.state == TranscriptState.failed) {
      text = 'Couldn’t make the transcript. ${error ?? ''}'.trim();
      action = _Button(label: 'Try again', onPressed: () => retryTranscript(ref, widget.pane.notebookId, clip));
    } else if (progress != null) {
      text = progress.speakers
          ? 'Finding who speaks · ${progress.percent}%'
          : 'Making the transcript on this tablet · ${progress.percent}%';
    } else if (clip.state == TranscriptState.waiting || clip.state == TranscriptState.working) {
      text = 'The transcript carries on in a moment';
    } else {
      return null;
    }
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: c.accentWash, borderRadius: BorderRadius.circular(12)),
        child: Row(
          spacing: 10,
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 13, height: 1.35, color: c.accentDeep, fontWeight: FontWeight.w600),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }

  Widget _empty(Transcribed clip, String q, EndlessColors c) {
    final text = q.isNotEmpty
        ? 'Nothing in the transcript says “${_query.text.trim()}”.'
        : clip.state == TranscriptState.done
        ? 'No speech was heard in this recording.'
        : 'Lines show here as they’re heard. Everything stays on this tablet.';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: TextStyle(fontSize: 14, height: 1.45, color: c.textMuted)),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    super.key,
    required this.clip,
    required this.line,
    required this.current,
    required this.query,
    required this.onTap,
    this.onSpeaker,
    this.onEdit,
  });

  final Transcribed clip;
  final TranscriptLine line;
  final bool current;
  final String query;
  final VoidCallback onTap;
  final VoidCallback? onSpeaker;

  /// A long press: edit the transcript, starting here.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final who = clip.speakerName(line.speaker);
    final style = TextStyle(fontSize: 15, height: 1.45, color: c.text, fontWeight: current ? FontWeight.w600 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: true,
        selected: current,
        label: '${clockOf(line.tMs)}${who.isEmpty ? '' : ', $who'}: ${line.text}',
        hint: 'Plays from here; hold to edit',
        excludeSemantics: onSpeaker == null,
        child: Material(
          color: current ? c.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            onLongPress: onEdit,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  SizedBox(
                    width: 44,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        clockOf(line.tMs),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: current ? c.accentDeep : c.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        if (who.isNotEmpty)
                          Semantics(
                            button: true,
                            label: 'Name $who',
                            excludeSemantics: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onSpeaker,
                              child: Text(
                                who,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.textMuted),
                              ),
                            ),
                          ),
                        Text.rich(_highlighted(line.text, query, style, c)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static TextSpan _highlighted(String text, String query, TextStyle style, EndlessColors c) {
    if (query.isEmpty) return TextSpan(text: text, style: style);
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var at = 0;
    while (true) {
      final i = lower.indexOf(query, at);
      if (i < 0) break;
      if (i > at) spans.add(TextSpan(text: text.substring(at, i)));
      spans.add(
        TextSpan(
          text: text.substring(i, i + query.length),
          style: TextStyle(backgroundColor: c.searchHit),
        ),
      );
      at = i + query.length;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }
}

/// A line being edited: its time and speaker, and its text in a field.
class _EditLine extends StatelessWidget {
  const _EditLine({super.key, required this.clip, required this.line, required this.controller, this.autofocus = false});

  final Transcribed clip;
  final TranscriptLine line;
  final TextEditingController controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final who = clip.speakerName(line.speaker);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, left: 12),
              child: Text(
                clockOf(line.tMs),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                if (who.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      who,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.textMuted),
                    ),
                  ),
                TextField(
                  controller: controller,
                  autofocus: autofocus,
                  minLines: 1,
                  maxLines: null,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  style: TextStyle(fontSize: 15, height: 1.45, color: c.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Empty: the line is removed',
                    hintStyle: TextStyle(color: c.textFaint, fontSize: 14),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: c.surfaceSunk,
                    semanticCounterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.accent, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The panel's buttons (44 high, 12 radius): dark for Add to page as text,
/// outlined for the rest.
class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onPressed, this.primary = false});

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null;
    final fg = primary ? c.onInverse : c.text;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: primary ? c.inverse : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: primary ? BorderSide.none : BorderSide(color: c.lineStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
                color: enabled ? fg : fg.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
