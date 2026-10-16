import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Says a word out loud (the dictionary's "Hear it"), with the device's
/// own text-to-speech, which works offline once its voice is installed.
abstract interface class Speech {
  /// Whether this device can.
  bool get available;

  /// Says [text]; false if it couldn't.
  Future<bool> say(String text, {String language = 'en-US'});
}

/// Android's TextToSpeech, through the app's own channel
/// (`Speech.kt`, channel `endless/speech`). Other platforms have none yet.
class ChannelSpeech implements Speech {
  static const _channel = MethodChannel('endless/speech');

  @override
  bool get available => !kIsWeb && Platform.isAndroid;

  @override
  Future<bool> say(String text, {String language = 'en-US'}) async {
    if (!available) return false;
    try {
      return await _channel
              .invokeMethod<bool>('speak', {'text': text, 'language': language})
              .timeout(const Duration(seconds: 10)) ??
          false;
    } on Object catch (e) {
      debugPrint('Speech: $e');
      return false;
    }
  }
}

final speechProvider = Provider<Speech>((ref) => ChannelSpeech());
