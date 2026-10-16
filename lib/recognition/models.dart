import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library.dart' show clockProvider;
import 'recognizer.dart';

enum ModelPhase { downloading, ready, failed }

/// Where a language's handwriting model is, for the small note that shows
/// while it downloads ("Getting English handwriting ready…").
class ModelNote {
  const ModelNote(this.language, this.phase);

  final String language;
  final ModelPhase phase;

  String get text {
    final name = inkLanguage(language).name;
    return switch (phase) {
      ModelPhase.downloading => 'Getting $name handwriting ready · first time only, about 20 MB',
      ModelPhase.ready => '$name handwriting is ready · works offline now',
      ModelPhase.failed => 'Couldn’t download $name handwriting · it will try again when you’re online',
    };
  }
}

/// How long to wait after a failed download before trying again.
const modelRetry = Duration(minutes: 1);

/// Handwriting models on this device: checks for one, downloads it on
/// first use (one download per language however many ask), and says what's
/// happening in [state] for the note.
class InkModels extends Notifier<ModelNote?> {
  final _ready = <String>{};
  final _pending = <String, Future<bool>>{};
  final _failedAt = <String, DateTime>{};

  @override
  ModelNote? build() => null;

  InkRecognizer get _recognizer => ref.read(inkRecognizerProvider);

  /// Whether [language] can be read now, downloading its model if need be
  /// (and [download] allows). False when there is no recognizer, the model
  /// couldn't be downloaded, or it failed less than [modelRetry] ago.
  Future<bool> ensure(String language, {bool download = true}) {
    if (!_recognizer.available) return Future.value(false);
    if (_ready.contains(language)) return Future.value(true);
    return _pending[language] ??= _ensure(language, download).whenComplete(() {
      // A block, not `=> remove()`: that would return this future to itself.
      _pending.remove(language);
    });
  }

  Future<bool> _ensure(String language, bool download) async {
    try {
      return await _check(language, download);
    } on Object catch (e) {
      // Never leave anyone waiting: an error is a model we don't have.
      debugPrint('Handwriting model for $language: $e');
      _failedAt[language] = ref.read(clockProvider)();
      if (ref.mounted && state?.language == language && state?.phase == ModelPhase.downloading) {
        state = ModelNote(language, ModelPhase.failed);
      }
      return false;
    }
  }

  Future<bool> _check(String language, bool download) async {
    final r = _recognizer;
    if (await r.hasModel(language)) {
      _ready.add(language);
      return true;
    }
    final failed = _failedAt[language];
    final now = ref.read(clockProvider)();
    if (!download || (failed != null && now.difference(failed) < modelRetry)) return false;
    if (!ref.mounted) return false;
    state = ModelNote(language, ModelPhase.downloading);
    final ok = await r.downloadModel(language) && await r.hasModel(language);
    if (!ref.mounted) return ok;
    if (ok) {
      _ready.add(language);
      _failedAt.remove(language);
    } else {
      _failedAt[language] = ref.read(clockProvider)();
    }
    state = ModelNote(language, ok ? ModelPhase.ready : ModelPhase.failed);
    return ok;
  }

  /// Clears the note (it was shown).
  void seen(ModelNote note) {
    if (state == note) state = null;
  }
}

final inkModelsProvider = NotifierProvider<InkModels, ModelNote?>(InkModels.new);
