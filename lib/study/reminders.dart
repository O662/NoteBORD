import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../library/library.dart';
import '../recognition/handwriting_index.dart';
import 'study_rows.dart';
import 'study_state.dart';

// Reminders from Need to remember (RememberMark.png's REMIND ME), as local
// notifications on the device. Nothing leaves it. They are set for the
// things to remember the index knows about: when one is changed, undone or
// unstarred, its reminder changes or goes too.

/// A notification set for later.
@immutable
class Reminder {
  const Reminder({required this.id, required this.at, required this.title, required this.body, required this.payload});

  final int id;
  final DateTime at;
  final String title;
  final String body;

  /// Where to go when it's tapped (see [ReminderTarget]).
  final String payload;

  /// Changes when anything shown or its time changes.
  String get signature => '${at.toUtc().toIso8601String()}|$title|$body|$payload';
}

/// Where a reminder leads: a thing to remember on a page.
@immutable
class ReminderTarget {
  const ReminderTarget(this.notebookId, this.pageId, this.rect);

  static ReminderTarget? parse(String? payload) {
    if (payload == null) return null;
    try {
      final j = jsonDecode(payload);
      if (j is! Map || j['nb'] is! String || j['pg'] is! String) return null;
      final r = (j['at'] as List?)?.whereType<num>().map((v) => v.toDouble()).toList();
      return ReminderTarget(
        j['nb'] as String,
        j['pg'] as String,
        r == null || r.length != 4 ? null : Rect.fromLTWH(r[0], r[1], r[2], r[3]),
      );
    } on FormatException {
      return null;
    }
  }

  final String notebookId;
  final String pageId;
  final Rect? rect;
}

/// Shows reminders. The app's runs on the tablet's notifications; tests
/// supply their own.
abstract interface class ReminderService {
  /// Whether reminders can be shown on this device.
  bool get available;

  /// Gets ready; [onOpen] is called with a reminder's payload when one is
  /// tapped (also when it opened the app).
  Future<void> start(void Function(String payload) onOpen);

  /// Asks to show notifications (Android 13 and later ask once). False if
  /// the answer was no.
  Future<bool> askPermission();

  Future<void> schedule(Reminder r);
  Future<void> cancel(int id);

  /// Ids of the reminders set now.
  Future<Set<int>> scheduled();
}

/// No reminders here (Windows and Linux, for now).
class NoReminders implements ReminderService {
  const NoReminders();

  @override
  bool get available => false;

  @override
  Future<void> start(void Function(String payload) onOpen) async {}

  @override
  Future<bool> askPermission() async => false;

  @override
  Future<void> schedule(Reminder r) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<Set<int>> scheduled() async => const {};
}

/// flutter_local_notifications on Android, iOS and macOS. Android's are
/// inexact alarms, so they may come a few minutes late, and need no
/// permission to set exact alarms.
class LocalNotificationReminders implements ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _started = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'remember',
      'Need to remember',
      channelDescription: 'Reminders for what you marked to remember',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  @override
  bool get available => true;

  @override
  Future<void> start(void Function(String payload) onOpen) async {
    if (_started) return;
    _started = true;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Permission is asked when the first reminder is set, not at start.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload case final p?) onOpen(p);
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        if (launch!.notificationResponse?.payload case final p?) onOpen(p);
      }
    } on Object catch (e) {
      debugPrint('Reminders unavailable: $e');
    }
  }

  @override
  Future<bool> askPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
      final mac = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      if (mac != null) return await mac.requestPermissions(alert: true, sound: true) ?? false;
    } on Object catch (e) {
      debugPrint('Notification permission: $e');
    }
    return false;
  }

  @override
  Future<void> schedule(Reminder r) async {
    try {
      // An instant in UTC: the device turns it into its own time.
      await _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
        payload: r.payload,
      );
    } on Object catch (e) {
      debugPrint('Could not set a reminder: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } on Object catch (e) {
      debugPrint('Could not cancel a reminder: $e');
    }
  }

  @override
  Future<Set<int>> scheduled() async {
    try {
      return {for (final p in await _plugin.pendingNotificationRequests()) p.id};
    } on Object {
      return const {};
    }
  }
}

final reminderServiceProvider = Provider<ReminderService>((ref) {
  if (kIsWeb) return const NoReminders();
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => LocalNotificationReminders(),
    _ => const NoReminders(),
  };
});

/// A reminder's id: the same thing to remember always gets the same one
/// (FNV-1a, 31 bits).
int reminderId(String notebookId, String rememberId) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode('$notebookId/$rememberId')) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h & 0x7FFFFFFF;
}

/// The reminders [things] want, after [now]. [titles] are notebook titles.
List<Reminder> remindersFor(Iterable<RememberedThing> things, Map<String, String> titles, DateTime now) => [
      for (final t in things)
        if (t.hasReminder && t.remindAt!.isAfter(now))
          Reminder(
            id: reminderId(t.notebookId, t.id),
            at: t.remindAt!,
            title: 'Need to remember',
            body: [
              if (t.said.isNotEmpty) t.said else 'What you marked in ${titles[t.notebookId] ?? 'your notes'}',
              if (t.why.isNotEmpty) '“${t.why}”',
            ].join('\n'),
            payload: jsonEncode({
              'nb': t.notebookId,
              'pg': t.pageId,
              'at': [t.rect.left, t.rect.top, t.rect.width, t.rect.height].map((v) => (v * 10).round() / 10).toList(),
            }),
          ),
    ];

/// Keeps the device's reminders matching what's remembered.
class ReminderSync {
  ReminderSync(this.ref);

  final Ref ref;
  final _set = <int, String>{};
  bool _first = true;
  Future<void> _tail = Future.value();

  ReminderService get _service => ref.read(reminderServiceProvider);

  /// Brings the reminders up to date with [things] (one update at a time).
  Future<void> sync(List<RememberedThing> things) => _tail = _tail.then((_) => _sync(things)).catchError((Object e) {
        debugPrint('Reminder sync: $e');
      });

  Future<void> _sync(List<RememberedThing> things) async {
    final service = _service;
    if (!service.available) return;
    final library = ref.read(libraryProvider);
    final titles = {for (final n in library.notebooks) n.id: n.title};
    final now = ref.read(clockProvider)().toUtc();
    final wanted = {for (final r in remindersFor(things, titles, now)) r.id: r};
    // Reminders whose time has come: Android's inexact alarms may still be
    // on their way (a few minutes late), so they're never cancelled.
    final due = {
      for (final t in things)
        if (t.hasReminder && !t.remindAt!.isAfter(now)) reminderId(t.notebookId, t.id),
    };
    // Left over from before (a thing unstarred while the app was closed);
    // only once the index has every notebook, or every reminder would look
    // left over just after an update.
    if (_first && ref.read(handwritingIndexProvider).caughtUp) {
      _first = false;
      for (final id in await service.scheduled()) {
        if (!wanted.containsKey(id) && !due.contains(id)) await service.cancel(id);
      }
    }
    for (final id in [..._set.keys]) {
      if (wanted.containsKey(id) || due.contains(id)) continue;
      // Forgotten, unstarred, or no reminder any more.
      _set.remove(id);
      await service.cancel(id);
    }
    for (final r in wanted.values) {
      if (_set[r.id] == r.signature) continue;
      await service.schedule(r);
      _set[r.id] = r.signature;
    }
  }
}

/// Watches what's remembered and keeps the reminders up to date (read once
/// by the app; does nothing where reminders aren't available).
final reminderSyncProvider = Provider<ReminderSync>((ref) {
  final sync = ReminderSync(ref);
  if (ref.read(reminderServiceProvider).available) {
    ref.listen(studyProvider, (_, next) {
      if (next != null) sync.sync(next.remembered);
    }, fireImmediately: true);
  }
  return sync;
});
