import 'dart:convert';

import '../board/ids.dart';
import '../recognition/segment.dart' show fnv64;

// Stamps say when something last changed, so two devices agree on which
// change is newer. A stamp is a hybrid logical clock: milliseconds since
// 1970, a counter for changes in the same millisecond (or when this clock
// is behind one already seen), and the device, as one string that sorts in
// time order: `000001790000000.000000.dv_01J…`.

/// Whether stamp [a] is newer than [b] (null is older than everything).
bool newer(String? a, String? b) => (a ?? '').compareTo(b ?? '') > 0;

/// The newer of two stamps.
String? newest(String? a, String? b) => newer(a, b) ? a : b;

/// The milliseconds since 1970 in [stamp].
int stampMillis(String stamp) => int.tryParse(stamp.split('.').first) ?? 0;

String _stamp(int ms, int counter, String device) =>
    '${ms.toString().padLeft(15, '0')}.${counter.toString().padLeft(6, '0')}.$device';

/// Gives out this device's stamps. A change is stamped with when it was
/// made, but always later than the stamp it replaces (the same item's
/// previous one, maybe from another device), so an edit made after seeing
/// another device's change wins over it even when this device's clock is
/// behind. Changes made at the same time on two devices compare by when
/// they were made.
class Stamper {
  Stamper(this.device, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// A new device id.
  static String newDevice() => newId('dv');

  final String device;
  final DateTime Function() _clock;

  /// A stamp for a change made at [at] (now if null; never in the future)
  /// to something last stamped [previous].
  String after(String? previous, [DateTime? at]) {
    final now = _clock().toUtc().millisecondsSinceEpoch;
    var ms = at == null ? now : at.toUtc().millisecondsSinceEpoch;
    if (ms > now) ms = now;
    var counter = 0;
    if (previous != null && previous.isNotEmpty) {
      final parts = previous.split('.');
      final pms = int.tryParse(parts.first) ?? 0;
      final pc = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      if (ms <= pms) {
        ms = pms;
        counter = pc + 1;
      }
    }
    return _stamp(ms, counter, device);
  }
}

/// [value] as JSON with every object's keys sorted, so the same data always
/// gives the same text (and hash).
String canonicalJson(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is List) return [for (final e in v) _sorted(e)];
  return v;
}

/// [value] as indented JSON with sorted keys (stable text, for files
/// people may look at).
String sortedJson(Object? value) => const JsonEncoder.withIndent('  ').convert(_sorted(value));

/// A short hash of [value]'s canonical JSON.
String hashJson(Object? value) => fnv64(canonicalJson(value));

/// A short hash of bytes.
String hashBytes(List<int> bytes) {
  // FNV-1a, 64-bit, in two 32-bit halves as fnv64 does, plus the length.
  var hi = 0xcbf29ce4, lo = 0x84222325;
  for (final unit in bytes) {
    lo ^= unit;
    final loMul = lo * 0x1b3;
    final hiMul = hi * 0x1b3 + (lo << 8) + (loMul ~/ 0x100000000);
    lo = loMul & 0xffffffff;
    hi = hiMul & 0xffffffff;
  }
  return '${hi.toRadixString(16).padLeft(8, '0')}${lo.toRadixString(16).padLeft(8, '0')}-${bytes.length}';
}
