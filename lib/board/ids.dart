import 'dart:math';

final _random = Random.secure();
const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; // Crockford base32

/// Sortable unique id with a type prefix, e.g. `it_01J9Z3K4XQ7H2M8RTV`.
/// 10 chars of millisecond time, then 10 random chars (like a ULID).
String newId(String prefix, {DateTime? now}) {
  var t = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
  final time = List.filled(10, '0');
  for (var i = 9; i >= 0; i--) {
    time[i] = _alphabet[t % 32];
    t ~/= 32;
  }
  final rand = List.generate(10, (_) => _alphabet[_random.nextInt(32)]);
  return '${prefix}_${time.join()}${rand.join()}';
}
