import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'model.dart';

// Password locks (docs/BOARD_FORMAT.md). A locked page is stored as
// `pages/<pageId>.json.enc`: the page JSON sealed with AES-256-GCM under a
// key derived from the password with Argon2id. `lock.json` holds the salt,
// the Argon2id parameters, the hint and a check value that tells a wrong
// password from a damaged file. The password and key are never written.

/// Argon2id cost. The defaults follow the OWASP minimum (19 MiB, 2 passes).
class KdfParams {
  const KdfParams({this.memoryKiB = 19456, this.iterations = 2, this.parallelism = 1});

  /// Cheap parameters for tests only.
  static const fast = KdfParams(memoryKiB: 64, iterations: 1);

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Json toJson() => {'alg': 'argon2id', 'memoryKiB': memoryKiB, 'iterations': iterations, 'parallelism': parallelism};

  factory KdfParams.fromJson(Json j) => KdfParams(
        memoryKiB: (j['memoryKiB'] as num).toInt(),
        iterations: (j['iterations'] as num).toInt(),
        parallelism: (j['parallelism'] as num?)?.toInt() ?? 1,
      );
}

/// One password: for a page, or for the whole notebook.
class LockEntry {
  const LockEntry({required this.salt, required this.kdf, required this.check, this.hint, this.biometric = false});

  final Uint8List salt;
  final KdfParams kdf;

  /// [checkText] sealed with the key.
  final Uint8List check;
  final String? hint;

  /// Whether this device may unlock it with a fingerprint or face.
  final bool biometric;

  static const checkText = 'endless-lock-check';

  LockEntry copyWith({bool? biometric}) =>
      LockEntry(salt: salt, kdf: kdf, check: check, hint: hint, biometric: biometric ?? this.biometric);

  Json toJson() => {
        'kdf': kdf.toJson(),
        'salt': base64.encode(salt),
        'check': base64.encode(check),
        'hint': hint,
        'biometric': biometric,
      };

  factory LockEntry.fromJson(Json j) => LockEntry(
        salt: base64.decode(j['salt'] as String),
        kdf: KdfParams.fromJson((j['kdf'] as Map).cast<String, dynamic>()),
        check: base64.decode(j['check'] as String),
        hint: j['hint'] as String?,
        biometric: j['biometric'] as bool? ?? false,
      );
}

/// `lock.json`. A page with its own entry uses that password; any other page
/// of a locked notebook uses the notebook's.
class LockFile {
  LockFile({this.notebook, Map<String, LockEntry>? pages}) : pages = pages ?? {};

  LockEntry? notebook;
  final Map<String, LockEntry> pages;

  bool get isEmpty => notebook == null && pages.isEmpty;

  /// The entry that seals [pageId], if any.
  LockEntry? entryFor(String pageId) => pages[pageId] ?? notebook;

  Json toJson() => {
        'version': 1,
        'notebook': notebook?.toJson(),
        'pages': {for (final e in pages.entries) e.key: e.value.toJson()},
      };

  factory LockFile.fromJson(Json j) => LockFile(
        notebook: j['notebook'] == null ? null : LockEntry.fromJson((j['notebook'] as Map).cast<String, dynamic>()),
        pages: {
          for (final e in ((j['pages'] as Map?) ?? const {}).entries)
            e.key as String: LockEntry.fromJson((e.value as Map).cast<String, dynamic>()),
        },
      );
}

/// Turns a password into a 256-bit key.
abstract class Kdf {
  Future<Uint8List> derive(String password, Uint8List salt, KdfParams params);
}

/// Argon2id, on a background isolate so the UI keeps drawing.
class Argon2Kdf implements Kdf {
  const Argon2Kdf({this.background = true});

  final bool background;

  @override
  Future<Uint8List> derive(String password, Uint8List salt, KdfParams params) {
    Future<Uint8List> run() => _argon2(password, salt, params);
    return background ? Isolate.run(run) : run();
  }

  static Future<Uint8List> _argon2(String password, Uint8List salt, KdfParams p) async {
    final algorithm = DartArgon2id(
      memory: p.memoryKiB,
      iterations: p.iterations,
      parallelism: p.parallelism,
      hashLength: 32,
      maxIsolates: 1,
    );
    final key = await algorithm.deriveKeyFromPassword(password: password, nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }
}

/// Seals and opens locked pages.
class LockCrypto {
  LockCrypto({this.kdf = const Argon2Kdf(), this.params = const KdfParams(), this.background = true});

  final Kdf kdf;
  final KdfParams params;

  /// Run AES on a background isolate. Tests turn this off.
  final bool background;

  static final _magic = ascii.encode('EBL1');
  static final _random = Random.secure();

  static Uint8List _randomBytes(int n) => Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  /// A new password: returns its entry for lock.json and the key.
  Future<(LockEntry, Uint8List)> create(String password, {String? hint, bool biometric = false}) async {
    final salt = _randomBytes(16);
    final key = await kdf.derive(password, salt, params);
    final check = await seal(key, LockEntry.checkText);
    final trimmed = hint?.trim();
    return (
      LockEntry(
        salt: salt,
        kdf: params,
        check: check,
        hint: trimmed == null || trimmed.isEmpty ? null : trimmed,
        biometric: biometric,
      ),
      key,
    );
  }

  /// The key for [entry], or null if the password is wrong.
  Future<Uint8List?> open(LockEntry entry, String password) async {
    final key = await kdf.derive(password, entry.salt, entry.kdf);
    return await verify(entry, key) ? key : null;
  }

  /// Whether [key] opens [entry] (a key restored with biometrics is checked too).
  Future<bool> verify(LockEntry entry, Uint8List key) async {
    try {
      return await unseal(key, entry.check) == LockEntry.checkText;
    } on SecretBoxAuthenticationError {
      return false;
    }
  }

  /// `EBL1` · 12-byte nonce · 16-byte tag · ciphertext.
  Future<Uint8List> seal(Uint8List key, String plain) {
    final nonce = _randomBytes(12);
    Uint8List run() => _seal(key, nonce, utf8.encode(plain));
    return background ? Isolate.run(run) : Future.value(run());
  }

  /// Throws [SecretBoxAuthenticationError] for a wrong key or a damaged file.
  Future<String> unseal(Uint8List key, Uint8List sealed) {
    String run() => utf8.decode(_unseal(key, sealed));
    return background ? Isolate.run(run) : Future.sync(run);
  }

  /// Seals a file (an image on a locked page), in the same layout as a page.
  Future<Uint8List> sealBytes(Uint8List key, Uint8List clear) {
    final nonce = _randomBytes(12);
    Uint8List run() => _seal(key, nonce, clear);
    return background ? Isolate.run(run) : Future.value(run());
  }

  /// Throws [SecretBoxAuthenticationError] for a wrong key or a damaged file.
  Future<Uint8List> unsealBytes(Uint8List key, Uint8List sealed) {
    Uint8List run() => Uint8List.fromList(_unseal(key, sealed));
    return background ? Isolate.run(run) : Future.sync(run);
  }

  static Uint8List _seal(Uint8List key, Uint8List nonce, List<int> clear) {
    final box = DartAesGcm.with256bits().encryptSync(clear, secretKeyData: SecretKeyData(key), nonce: nonce);
    return Uint8List.fromList([..._magic, ...nonce, ...box.mac.bytes, ...box.cipherText]);
  }

  static List<int> _unseal(Uint8List key, Uint8List data) {
    if (data.length < 32 || !_startsWithMagic(data)) {
      throw const FormatException('Not a sealed Endless page');
    }
    final box = SecretBox(data.sublist(32), nonce: data.sublist(4, 16), mac: Mac(data.sublist(16, 32)));
    return DartAesGcm.with256bits().decryptSync(box, secretKeyData: SecretKeyData(key));
  }

  static bool _startsWithMagic(Uint8List data) {
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) return false;
    }
    return true;
  }
}
