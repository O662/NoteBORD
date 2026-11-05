import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../board/ids.dart';
import '../library/library.dart' show clockProvider;
import '../state/settings.dart' show boardStoreProvider;
import 'calendar_model.dart';
import 'calendar_state.dart';
import 'feeds.dart';

// Calendar links, kept up to date: added from the Connect panel, read
// again every [FeedSync.every] while Endless is open, when the Calendar or
// Planner opens, and at start. The last copy of each link's file is kept
// (calendars/<id>.ics), so its events show offline; the link itself is in
// the platform's secure storage. Nothing is ever sent to the calendar.

/// Where calendar links are kept: anyone with one can read the calendar,
/// so they're kept like a password.
abstract class FeedLinks {
  Future<String?> read(String calendarId);
  Future<void> write(String calendarId, String link);
  Future<void> delete(String calendarId);
}

class SecureFeedLinks implements FeedLinks {
  final _storage = const FlutterSecureStorage();

  static String _key(String id) => 'calendar-link.$id';

  @override
  Future<String?> read(String calendarId) async {
    try {
      return await _storage.read(key: _key(calendarId));
    } on Object catch (e) {
      debugPrint('Calendar link unreadable: $e');
      return null;
    }
  }

  @override
  Future<void> write(String calendarId, String link) => _storage.write(key: _key(calendarId), value: link);

  @override
  Future<void> delete(String calendarId) async {
    try {
      await _storage.delete(key: _key(calendarId));
    } on Object catch (e) {
      debugPrint('Calendar link not deleted: $e');
    }
  }
}

class MemoryFeedLinks implements FeedLinks {
  final links = <String, String>{};

  @override
  Future<String?> read(String calendarId) async => links[calendarId];

  @override
  Future<void> write(String calendarId, String link) async => links[calendarId] = link;

  @override
  Future<void> delete(String calendarId) async => links.remove(calendarId);
}

typedef FeedReader = Future<FeedRead> Function(String ics, String calendarId, DateTime now);

final feedLinksProvider = Provider<FeedLinks>((ref) => SecureFeedLinks());
final feedFetcherProvider = Provider<FeedFetcher>((ref) => HttpFeedFetcher());
final feedReaderProvider = Provider<FeedReader>((ref) => readFeedInBackground);

/// The calendar links being read right now (their ids).
final feedSyncProvider = NotifierProvider<FeedSync, Set<String>>(FeedSync.new);

class FeedSync extends Notifier<Set<String>> {
  /// How often links are read again while Endless is open.
  static const every = Duration(minutes: 15);

  /// Opening the Calendar or Planner reads a link again if it's older.
  static const fresh = Duration(minutes: 5);

  Timer? _timer;
  bool _started = false, _alive = true;
  Future<void>? _loading;

  @override
  Set<String> build() {
    ref.onDispose(() {
      _alive = false;
      _timer?.cancel();
    });
    return const {};
  }

  Calendars get _calendars => ref.read(calendarProvider.notifier);
  DateTime get _now => ref.read(clockProvider)().toUtc();
  List<CalendarInfo> get _feeds => [
    for (final c in ref.read(calendarProvider).calendars)
      if (c.viewOnly) c,
  ];

  /// At start: the copies kept, then the links read again (if there are any).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _loadCopies();
    if (_feeds.isNotEmpty) {
      _watch();
      await refreshAll(olderThan: Duration.zero);
    }
  }

  void _watch() => _timer ??= Timer.periodic(every, (_) => unawaited(refreshAll(olderThan: Duration.zero)));

  /// Each link's events from the copy of its file kept on the tablet.
  Future<void> _loadCopies() => _loading ??= () async {
    final store = ref.read(boardStoreProvider);
    for (final cal in _feeds) {
      final text = await store.loadFeed(cal.id);
      if (text == null || !_alive) continue;
      try {
        final read = await ref.read(feedReaderProvider)(text, cal.id, _now);
        if (_alive) _calendars.setFeed(cal.id, events: read.events);
      } on Object catch (e) {
        debugPrint('Calendar copy unreadable (${cal.id}): $e');
      }
    }
  }();

  /// Reads again every link last read more than [olderThan] ago.
  Future<void> refreshAll({Duration olderThan = fresh}) async {
    await _loadCopies();
    final now = _now;
    await Future.wait([
      for (final cal in _feeds)
        if (cal.fetchedAt == null || now.difference(cal.fetchedAt!) >= olderThan) refresh(cal.id),
    ]);
  }

  /// Reads calendar link [calendarId] again. Returns why it couldn't, or
  /// null; its events stay as they were if it couldn't.
  Future<String?> refresh(String calendarId) async {
    if (state.contains(calendarId) || !_alive) return null;
    state = {...state, calendarId};
    try {
      final link = await ref.read(feedLinksProvider).read(calendarId);
      final uri = link == null ? null : feedUri(link);
      if (uri == null) throw FeedException.forgotten;
      final text = await ref.read(feedFetcherProvider).fetch(uri);
      final now = _now;
      final read = await ref.read(feedReaderProvider)(text, calendarId, now);
      if (!_alive || ref.read(calendarProvider).calendar(calendarId) == null) return null;
      await ref.read(boardStoreProvider).saveFeed(calendarId, text);
      _calendars.setFeed(calendarId, events: read.events, fetchedAt: now, error: () => null);
      return null;
    } on FeedException catch (e) {
      if (_alive) _calendars.setFeed(calendarId, error: () => e.message);
      return e.message;
    } on Object catch (e) {
      debugPrint('Calendar link not read ($calendarId): $e');
      if (_alive) _calendars.setFeed(calendarId, error: () => FeedException.notCalendar.message);
      return FeedException.notCalendar.message;
    } finally {
      if (_alive) state = {...state}..remove(calendarId);
    }
  }

  /// Adds the calendar at [link], named [name] (else as the calendar
  /// names itself). Throws a [FeedException] if it can't be read.
  Future<CalendarInfo> add(String link, {String? name}) async {
    final uri = feedUri(link);
    if (uri == null) throw FeedException.notLink;
    final links = ref.read(feedLinksProvider);
    for (final cal in _feeds) {
      if (await links.read(cal.id) case final saved? when feedUri(saved) == uri) {
        throw FeedException('That calendar is here already, as “${cal.name}”.');
      }
    }
    final text = await ref.read(feedFetcherProvider).fetch(uri);
    final now = _now;
    final id = newId('cal', now: now);
    final read = await ref.read(feedReaderProvider)(text, id, now);
    final from = feedFromOf(uri);
    final given = name?.trim() ?? '';
    final title = given.isNotEmpty
        ? given
        : read.name ??
              switch (from) {
                FeedFrom.google => 'Google calendar',
                FeedFrom.outlook => 'Outlook calendar',
                FeedFrom.web => uri.host,
              };
    await links.write(id, uri.toString());
    await ref.read(boardStoreProvider).saveFeed(id, text);
    final cal = _calendars.addFeed(id: id, name: title, from: from, fetchedAt: now);
    _calendars.setFeed(id, events: read.events);
    _watch();
    return cal;
  }

  /// Takes calendar link [calendarId] off this tablet: its events, its
  /// copy and the link.
  Future<void> remove(String calendarId) async {
    _calendars.removeCalendar(calendarId);
    await ref.read(feedLinksProvider).delete(calendarId);
    await ref.read(boardStoreProvider).deleteFeed(calendarId);
    if (_feeds.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }
}
