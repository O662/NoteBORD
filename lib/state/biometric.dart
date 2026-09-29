import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// "Unlock with fingerprint or face": the key of a locked page or notebook
/// is kept in the platform's secure storage (Android Keystore, Windows
/// Credential Manager…) and handed back only after a biometric check.
/// The password itself is never stored.
abstract class BiometricUnlock {
  /// Whether this device can check a fingerprint or face.
  Future<bool> isAvailable();

  Future<void> save(String slot, Uint8List key);

  /// Asks for a fingerprint or face, then returns the saved key (null if
  /// cancelled, failed, or nothing is saved).
  Future<Uint8List?> read(String slot, {required String reason});

  Future<void> delete(String slot);
}

/// The storage slot for a page's or notebook's key.
String biometricSlot(String notebookId, String? pageId) => 'lock.$notebookId.${pageId ?? 'notebook'}';

class PlatformBiometricUnlock implements BiometricUnlock {
  final _auth = LocalAuthentication();
  final _storage = const FlutterSecureStorage();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } on Object catch (e) {
      debugPrint('Biometric check failed: $e');
      return false;
    }
  }

  @override
  Future<void> save(String slot, Uint8List key) => _storage.write(key: slot, value: base64.encode(key));

  @override
  Future<Uint8List?> read(String slot, {required String reason}) async {
    try {
      final saved = await _storage.read(key: slot);
      if (saved == null) return null;
      final ok = await _auth.authenticate(localizedReason: reason, biometricOnly: true);
      return ok ? base64.decode(saved) : null;
    } on Object catch (e) {
      debugPrint('Biometric unlock failed: $e');
      return null;
    }
  }

  @override
  Future<void> delete(String slot) async {
    try {
      await _storage.delete(key: slot);
    } on Object catch (e) {
      debugPrint('Could not remove the saved key: $e');
    }
  }
}

final biometricProvider = Provider<BiometricUnlock>((ref) => PlatformBiometricUnlock());
