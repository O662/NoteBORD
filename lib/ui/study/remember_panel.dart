import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/items.dart' show ImageLookup;
import '../../library/library.dart' show clockProvider;
import '../../study/remember.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../calendar/event_picker.dart';
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import 'item_preview.dart';
import 'study_format.dart';

/// What was picked in Remember this.
@immutable
class RememberChoice {
  const RememberChoice({this.why = '', this.remind = RemindKind.none, this.remindAt, this.flashcard = false, this.event});

  final String why;
  final RemindKind remind;
  final DateTime? remindAt;
  final bool flashcard;

  /// The event the reminder comes before.
  final EventLink? event;
}

/// "Remember this" (RememberMark.png): what's being remembered, why it
/// matters, when to be reminded, and "Also make it a flashcard".
class RememberPanel extends ConsumerStatefulWidget {
  const RememberPanel({
    super.key,
    required this.items,
    required this.onSave,
    required this.onCancel,
    this.images,
    this.initial,
    this.hasCard = false,
    this.onForget,
  });

  static const width = 520.0;

  /// What's remembered, drawn as on the page.
  final List<Item> items;
  final ImageLookup? images;

  /// Editing something already remembered.
  final RememberMark? initial;

  /// It's a flashcard already.
  final bool hasCard;
  final ValueChanged<RememberChoice> onSave;
  final VoidCallback onCancel;

  /// "Forget it": no longer remembered (only when editing).
  final VoidCallback? onForget;

  @override
  ConsumerState<RememberPanel> createState() => _RememberPanelState();
}

class _RememberPanelState extends ConsumerState<RememberPanel> {
  late final _why = TextEditingController(text: widget.initial?.why ?? '');
  late RemindKind _remind = widget.initial?.remind ?? RemindKind.none;
  late DateTime? _at = widget.initial?.remindAt;
  late EventLink? _event = widget.initial?.event;
  late bool _card = widget.hasCard;

  DateTime get _now => ref.read(clockProvider)();

  @override
  void dispose() {
    _why.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = _now;
    final start = (_remind == RemindKind.date ? _at : null)?.toLocal() ?? tomorrowMorning(now);
    final day = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Remind me on',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: start.hour, minute: start.minute),
      helpText: 'At',
    );
    if (time == null || !mounted) return;
    setState(() {
      _remind = RemindKind.date;
      _at = DateTime(day.year, day.month, day.day, time.hour, time.minute).toUtc();
    });
  }

  Future<void> _pickEvent() async {
    final picked = await showEventPicker(context, current: _remind == RemindKind.event ? _event : null);
    if (picked == null || !mounted) return;
    setState(() {
      _remind = RemindKind.event;
      _event = picked.$1;
      _at = picked.$2;
    });
  }

  void _save() {
    final at = switch (_remind) {
      RemindKind.none => null,
      RemindKind.tomorrow => tomorrowMorning(_now).toUtc(),
      _ => _at,
    };
    widget.onSave(RememberChoice(
      why: _why.text.trim(),
      remind: at == null ? RemindKind.none : _remind,
      remindAt: at,
      flashcard: _card,
      event: _remind == RemindKind.event ? _event : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = _now;
    final label = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.96, color: c.textMuted);

    Widget chip(String text, bool on, VoidCallback onTap) => Semantics(
          button: true,
          inMutuallyExclusiveGroup: true,
          checked: on,
          label: text,
          excludeSemantics: true,
          child: Material(
            color: on ? c.inverse : Colors.transparent,
            shape: StadiumBorder(side: BorderSide(color: on ? c.inverse : c.lineStrong)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                // As wide as its words: the chips share rows.
                child: Center(
                  widthFactor: 1,
                  child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? c.onInverse : c.text)),
                ),
              ),
            ),
          ),
        );

    final picked = _remind == RemindKind.date && _at != null;
    return Semantics(
      container: true,
      label: 'Remember this',
      explicitChildNodes: true,
      child: Container(
        width: RememberPanel.width,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(18),
          boxShadow: c.dialogShadow,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
          Row(spacing: 10, children: [
            EIcon(EIcons.star, size: 22, color: c.gold),
            Expanded(
              child: Text('Remember this', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
            ),
            Transform.translate(
              offset: const Offset(10, 0),
              child: ChromeButton(label: 'Close', icon: EIcons.close, iconSize: 18, foreground: c.textMuted, onPressed: widget.onCancel),
            ),
          ]),
          // What's remembered (RememberMark.dc.html's yellow box).
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.rememberPaper,
              border: Border.all(color: c.rememberLine),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ItemsPreview(items: widget.items, images: widget.images, maxScale: 1, alignment: Alignment.centerLeft),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
            Text('WHY IT MATTERS (OPTIONAL)', style: label),
            DashedBorder(
              color: c.lineStrong,
              radius: 12,
              child: SizedBox(
                height: 52,
                child: Semantics(
                  label: 'Why it matters (optional)',
                  textField: true,
                  child: TextField(
                    controller: _why,
                    maxLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(fontFamily: FontFamilies.handwritingSample, fontSize: 24, color: c.text),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      hintText: 'always on the exam…',
                      hintStyle: TextStyle(fontFamily: FontFamilies.handwritingSample, fontSize: 24, color: c.textFaint),
                    ),
                  ),
                ),
              ),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            Text('REMIND ME', style: label),
            Semantics(
              container: true,
              label: 'Reminder',
              explicitChildNodes: true,
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                chip('No reminder', _remind == RemindKind.none, () => setState(() => _remind = RemindKind.none)),
                chip('Tomorrow', _remind == RemindKind.tomorrow, () => setState(() => _remind = RemindKind.tomorrow)),
                chip(_remind == RemindKind.event && _event != null ? beforeLabel(_event!) : 'Before an event', _remind == RemindKind.event, _pickEvent),
                chip(picked ? reminderChip(_at!, now) : 'Pick a date', picked, _pickDate),
              ]),
            ),
          ]),
          Semantics(
            checked: _card,
            label: 'Also make it a flashcard',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.hasCard ? null : () => setState(() => _card = !_card),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(spacing: 10, children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _card,
                      onChanged: widget.hasCard ? null : (v) => setState(() => _card = v ?? false),
                      activeColor: c.accent,
                      side: BorderSide(color: c.lineStrong, width: 1.5),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  Text(
                    widget.hasCard ? 'It’s a flashcard too' : 'Also make it a flashcard',
                    style: TextStyle(fontSize: 14, color: c.text),
                  ),
                ]),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
            child: Row(spacing: 8, children: [
              Expanded(
                child: widget.onForget != null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: widget.onForget,
                          style: TextButton.styleFrom(foregroundColor: c.danger, minimumSize: const Size(44, 44)),
                          child: const Text('Forget it', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          'Tip: draw a star next to anything to mark it',
                          style: TextStyle(fontSize: 13, height: 1.35, color: c.textMuted),
                        ),
                      ),
              ),
              SecondaryButton(label: 'Cancel', height: 46, onPressed: widget.onCancel),
              PrimaryButton(label: 'Save', height: 46, onPressed: _save),
            ]),
          ),
        ]),
      ),
    );
  }
}
