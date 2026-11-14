import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'windows_zones.dart';

// The tablet's time zone by name, for events sent to Google and Outlook: a
// weekly lecture at 10:00 has to stay at 10:00 when the clocks change, so
// its zone goes with it ("America/Chicago"), not just today's offset.
// Dart gives only the zone's abbreviation ("CST") on Android, and its
// Windows name ("Central Standard Time") on Windows, so the zone is found
// by name when it can be, else as the zone whose offsets match the
// tablet's all through this year and next (zones that match give the
// same times, so any of them will do).

/// A time zone, as Google ([iana]) and Microsoft ([windows], when it has
/// one) name it.
typedef LocalZone = ({String iana, String? windows});

var _zones = false;

void ensureZones() {
  if (_zones) return;
  tzdata.initializeTimeZones();
  _zones = true;
}

LocalZone? _cached;

/// The tablet's time zone ("UTC" if no zone matches).
LocalZone localZone() => _cached ??= findZone(
  name: DateTime.now().timeZoneName,
  offsetAt: (t) => t.toLocal().timeZoneOffset,
  around: DateTime.now(),
);

/// The zone named [name], or whose offsets match [offsetAt] around [around].
LocalZone findZone({required String name, required Duration Function(DateTime utc) offsetAt, required DateTime around}) {
  ensureZones();
  String? windowsOf(String iana) {
    for (final e in windowsZones.entries) {
      if (e.value == iana) return e.key;
    }
    return null;
  }

  if (windowsZones[name] case final iana?) return (iana: iana, windows: name);
  if (tz.timeZoneDatabase.locations.containsKey(name) && name.contains('/')) return (iana: name, windows: windowsOf(name));

  // The first and fifteenth of each month this year and next, at noon UTC.
  final samples = [
    for (var m = 0; m < 24; m++)
      for (final d in const [1, 15]) DateTime.utc(around.year, 1 + m, d, 12),
  ];
  final want = [for (final s in samples) offsetAt(s)];
  bool matches(tz.Location loc) {
    for (var i = 0; i < samples.length; i++) {
      if (tz.TZDateTime.from(samples[i], loc).timeZoneOffset != want[i]) return false;
    }
    return true;
  }

  // Zones Windows names first (the main zone for each place), and among
  // them one whose abbreviation is the tablet's ("CST").
  final main = [for (final z in windowsZones.values.toSet()) ?tz.timeZoneDatabase.locations[z]];
  final hits = main.where(matches).toList();
  final now = around.toUtc();
  final named = hits.where((l) => tz.TZDateTime.from(now, l).timeZoneName == name).firstOrNull;
  if ((named ?? hits.firstOrNull) case final l?) return (iana: l.name, windows: windowsOf(l.name));
  for (final l in tz.timeZoneDatabase.locations.values) {
    if (matches(l)) return (iana: l.name, windows: windowsOf(l.name));
  }
  return (iana: 'UTC', windows: 'UTC');
}
