import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../canvas/live_items.dart' show deviceTimeZone;

/// Asks Android for the device's time zone by name ("America/Chicago") for
/// the clocks on the page (`MainActivity`, channel `endless/time`). Dart
/// only knows the zone's abbreviation, which the clocks show elsewhere.
Future<void> readTimeZone() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    deviceTimeZone = await const MethodChannel('endless/time').invokeMethod<String>('zone');
  } on Object catch (e) {
    debugPrint('Time zone: $e');
  }
}
