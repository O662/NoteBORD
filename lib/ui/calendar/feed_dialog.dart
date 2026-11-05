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
    showEndlessDialog<CalendarInfo>(context, builder: (context) => const _AddFeed());

class _AddFeed extends ConsumerStatefulWidget {
  const _AddFeed();

  @override
  ConsumerState<_AddFeed> createState() => _AddFeedState();
}

class _AddFeedState extends ConsumerState<_AddFeed> {
  final _link = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 10,
              children: [
                SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
                PrimaryButton(label: _busy ? 'Reading…' : 'Add', onPressed: _busy || _link.text.trim().isEmpty ? null : _add),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
