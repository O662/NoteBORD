import 'dart:async' show TimeoutException;
import 'dart:io' show Platform;
import 'dart:ui' show Locale, Size;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel, MissingPluginException, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/model.dart';

/// A handwriting language: ML Kit's language tag and its name in itself.
class InkLanguage {
  const InkLanguage(this.tag, this.name);

  final String tag;
  final String name;
}

/// The languages offered (ML Kit reads 300 or so; these are the common
/// ones, named as their writers name them).
const inkLanguages = [
  InkLanguage('en-US', 'English'),
  InkLanguage('en-GB', 'English (UK)'),
  InkLanguage('es-ES', 'Español'),
  InkLanguage('fr-FR', 'Français'),
  InkLanguage('de-DE', 'Deutsch'),
  InkLanguage('it-IT', 'Italiano'),
  InkLanguage('pt-BR', 'Português'),
  InkLanguage('nl-NL', 'Nederlands'),
  InkLanguage('pl-PL', 'Polski'),
  InkLanguage('sv-SE', 'Svenska'),
  InkLanguage('tr-TR', 'Türkçe'),
  InkLanguage('ru-RU', 'Русский'),
  InkLanguage('uk-UA', 'Українська'),
  InkLanguage('hi-IN', 'हिन्दी'),
  InkLanguage('ja-JP', '日本語'),
  InkLanguage('ko-KR', '한국어'),
  InkLanguage('zh-Hani-CN', '中文'),
];

InkLanguage inkLanguage(String tag) =>
    inkLanguages.firstWhere((l) => l.tag == tag, orElse: () => InkLanguage(tag, tag));

/// The handwriting language for a tablet set to [locale]: its own when it
/// is offered, else English.
String inkLanguageFor(Locale? locale) {
  if (locale == null) return 'en-US';
  final exact = '${locale.languageCode}-${locale.countryCode ?? ''}';
  if (inkLanguages.any((l) => l.tag == exact)) return exact;
  if (locale.languageCode == 'zh') return 'zh-Hani-CN';
  return inkLanguages.where((l) => l.tag.startsWith('${locale.languageCode}-')).firstOrNull?.tag ?? 'en-US';
}

/// A point of a stroke for the recognizer: page px and absolute time (ms).
typedef InkSamplePoint = ({double x, double y, int t});

/// The points of [s] as the recognizer wants them, timed from when it was
/// written.
List<InkSamplePoint> samplesOf(StrokeItem s) {
  final t0 = s.createdAt.millisecondsSinceEpoch;
  return [for (final p in s.pageInk) (x: p.x, y: p.y, t: t0 + p.t)];
}

/// Raised when recognition can't run: no model, or the recognizer failed.
class RecognitionFailed implements Exception {
  const RecognitionFailed(this.message);

  final String message;

  @override
  String toString() => 'RecognitionFailed: $message';
}

/// Reads handwriting on this device.
abstract class InkRecognizer {
  const InkRecognizer();

  /// Whether this device can recognize handwriting at all.
  bool get available;

  /// Whether [language]'s model is on the device.
  Future<bool> hasModel(String language);

  /// Downloads [language]'s model (about 20 MB). Returns false if it
  /// couldn't (offline, no space, not a language it knows).
  Future<bool> downloadModel(String language);

  /// What [strokes] (one line, in pen order) say, best reading first.
  /// [preContext] is the text just before it; [area] the size of the line.
  Future<List<String>> recognize(
    List<List<InkSamplePoint>> strokes, {
    required String language,
    String preContext = '',
    Size? area,
  });

  void dispose() {}
}

/// For desktops and the web: no on-device handwriting recognition yet.
class NoInkRecognizer extends InkRecognizer {
  const NoInkRecognizer();

  @override
  bool get available => false;

  @override
  Future<bool> hasModel(String language) async => false;

  @override
  Future<bool> downloadModel(String language) async => false;

  @override
  Future<List<String>> recognize(
    List<List<InkSamplePoint>> strokes, {
    required String language,
    String preContext = '',
    Size? area,
  }) async =>
      throw const RecognitionFailed('Handwriting recognition isn’t available on this device');
}

/// Google ML Kit Digital Ink, on the tablet, through the app's own Android
/// code (android/…/InkRecognition.kt, channel `endless/ink`). Models are
/// downloaded once per language, then everything runs offline.
///
/// Not the google_mlkit_digital_ink_recognition plugin: 0.15.0 (the newest
/// for this Flutter) doesn't work on Android. Its Dart side calls a channel
/// its Android side doesn't register, and its model check never replies.
///
/// Every call has a time limit, so a stuck native call can't leave the app
/// "reading" forever.
class MlKitInkRecognizer extends InkRecognizer {
  MlKitInkRecognizer({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'endless/ink';

  static const checkLimit = Duration(seconds: 20);

  /// About 20 MB on a slow connection.
  static const downloadLimit = Duration(minutes: 10);
  static const readLimit = Duration(seconds: 30);

  final MethodChannel _channel;

  @override
  bool get available => true;

  @override
  Future<bool> hasModel(String language) async {
    try {
      return await _channel.invokeMethod<bool>('check', {'language': language}).timeout(checkLimit) ?? false;
    } on Object catch (e) {
      debugPrint('Handwriting model check for $language: $e');
      return false;
    }
  }

  @override
  Future<bool> downloadModel(String language) async {
    try {
      return await _channel.invokeMethod<bool>('download', {'language': language}).timeout(downloadLimit) ?? false;
    } on Object catch (e) {
      debugPrint('Handwriting model download for $language: $e');
      return false;
    }
  }

  @override
  Future<List<String>> recognize(
    List<List<InkSamplePoint>> strokes, {
    required String language,
    String preContext = '',
    Size? area,
  }) async {
    // ML Kit reads the last 20 characters of what came before.
    final pre = preContext.length > 20 ? preContext.substring(preContext.length - 20) : preContext;
    try {
      final result = await _channel.invokeMethod<List<Object?>>('recognize', {
        'language': language,
        'strokes': [
          for (final s in strokes) [for (final p in s) ...[p.x, p.y, p.t]],
        ],
        'preContext': pre,
        if (area != null) ...{'width': area.width, 'height': area.height},
      }).timeout(readLimit);
      return [for (final c in result ?? const <Object?>[]) if (c is String) c];
    } on PlatformException catch (e) {
      throw RecognitionFailed(e.message ?? e.code);
    } on TimeoutException {
      throw const RecognitionFailed('Reading the handwriting took too long');
    } on MissingPluginException {
      throw const RecognitionFailed('Handwriting recognition isn’t in this build of the app');
    }
  }

  @override
  void dispose() {
    _channel.invokeMethod<void>('close').catchError((_) {});
  }
}

/// ML Kit Digital Ink runs on Android. iOS needs its own native side (when
/// that build exists); desktops and the web another recognizer (CLAUDE.md).
/// Until then they have none.
final inkRecognizerProvider = Provider<InkRecognizer>((ref) {
  final r = !kIsWeb && Platform.isAndroid ? MlKitInkRecognizer() : const NoInkRecognizer();
  ref.onDispose(r.dispose);
  return r;
});
