import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/calendar_model.dart';
import '../../calendar/feed_sync.dart';
import '../../calendar/feeds.dart';
import '../../theme/colors.dart';
import '../dialogs.dart';

// Add a calendar link (the Calendar's Connect panel): the private iCal
// address of a Google or Outlook calendar, read at once so a wrong link
// says so here. Its events show view only.

/// Asks for a calendar link and adds it. Returns the calendar added.
Future<CalendarInfo?> showAddFeed(BuildContext context) =>
    // The keyboard's height is read outside the dialog: Dialog takes it
    // out of what its contents see.
    showEndlessDialog<CalendarInfo>(context, builder: (context) => _AddFeed(keyboard: MediaQuery.viewInsetsOf(context).bottom));

class _AddFeed extends ConsumerStatefulWidget {
  const _AddFeed({required this.keyboard});

  /// How much of the screen the on-screen keyboard covers.
  final double keyboard;

  @override
  ConsumerState<_AddFeed> createState() => _AddFeedState();
}

class _AddFeedState extends ConsumerState<_AddFeed> {
  final _link = TextEditingController();
  final _name = TextEditingController();
  final _actions = GlobalKey();
  bool _busy = false;
  double _inset = 0;
  Timer? _scroll;
  String? _error;

  /// While the on-screen keyboard comes up (it takes half a tablet's
  /// height), Cancel and Add are scrolled to just above it, once it and the
  /// dialog have stopped moving.
  void _keepActionsShown(double inset) {
    if (inset == _inset) return;
    final rising = inset > _inset;
    _inset = inset;
    if (!rising) return;
    _scroll?.cancel();
    _scroll = Timer(const Duration(milliseconds: 160), () {
      final ctx = _actions.currentContext;
      if (mounted && ctx != null) Scrollable.ensureVisible(ctx, alignment: 1, duration: const Duration(milliseconds: 120));
    });
  }

  @override
  void dispose() {
    _scroll?.cancel();
    _link.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cal = await ref.read(feedSyncProvider.notifier).add(_link.text, name: _name.text);
      if (mounted) Navigator.of(context).pop(cal);
    } on FeedException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inset = widget.keyboard;
    final keyboard = inset > 0;
    _keepActionsShown(inset);
    final muted = TextStyle(fontSize: 14, height: 1.45, color: c.textMuted);
    Widget where(String app, String steps) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$app: ',
            style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
          ),
          TextSpan(text: steps),
        ],
      ),
      style: muted,
    );
    return SingleChildScrollView(
      child: DialogFrame(
        title: 'Add a calendar link',
        width: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            // Out of the way while the keyboard is up.
            if (!keyboard)
              Text(
                'Paste a calendar’s private iCal (.ics) address. Its events show here, view only, and refresh every 15 minutes while Endless is open.',
                style: TextStyle(fontSize: 15, height: 1.45, color: c.textMuted),
              ),
            LabeledField(
              label: 'Calendar link',
              controller: _link,
              hint: 'https://calendar.google.com/calendar/ical/…',
              autofocus: true,
              errorText: _error,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() => _error = null),
            ),
            LabeledField(
              label: 'Name (optional)',
              controller: _name,
              hint: 'School',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_busy && _link.text.trim().isNotEmpty) _add();
              },
            ),
            // The buttons come before the help, so they stay above the
            // on-screen keyboard.
            Row(
              key: _actions,
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 10,
              children: [
                SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
                PrimaryButton(label: _busy ? 'Reading…' : 'Add', onPressed: _busy || _link.text.trim().isEmpty ? null : _add),
              ],
            ),
            Container(height: 1, color: c.lineSoft),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                where('Google Calendar', 'on the web, Settings → your calendar → Integrate calendar → Secret address in iCal format.'),
                where('Outlook', 'Settings → Calendar → Shared calendars → Publish a calendar → Can view all details → Publish, then the ICS link.'),
              ],
            ),
            Text(
              'Anyone with the link can see the calendar, so Endless keeps it like a password.',
              style: TextStyle(fontSize: 13, height: 1.4, color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
