import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tablet's on-screen keyboard, as far as an app can tell.
abstract interface class DeviceKeyboard {
  /// Whether it's held back because Android thinks a physical keyboard is
  /// attached (a keyboard cover, Bluetooth, or Samsung's Multi Control
  /// sharing a PC's keyboard), with "Show on-screen keyboard" off. Then it
  /// doesn't open in any app, whatever the app asks.
  Future<bool> heldBack();

  /// Opens the tablet's physical keyboard settings; false if it couldn't.
  Future<bool> openSettings();
}

/// Android, through the app's channel (`Keyboard.kt`, `endless/keyboard`).
class ChannelDeviceKeyboard implements DeviceKeyboard {
  static const _channel = MethodChannel('endless/keyboard');

  bool get _android => !kIsWeb && Platform.isAndroid;

  @override
  Future<bool> heldBack() async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('heldBack') ?? false;
    } on Object catch (e) {
      debugPrint('Keyboard: $e');
      return false;
    }
  }

  @override
  Future<bool> openSettings() async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on Object catch (e) {
      debugPrint('Keyboard: $e');
      return false;
    }
  }
}

final deviceKeyboardProvider = Provider<DeviceKeyboard>((ref) => ChannelDeviceKeyboard());
