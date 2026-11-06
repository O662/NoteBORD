import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'files.dart';

// Files opened with Endless from another app: a board file sent by email or
// shared from Drive, OneDrive or Files ("Open with Endless", or "Share to
// Endless"). Android copies each into the app's cache (Incoming.kt); here
// they're read and handed to the app, which imports them.

abstract class IncomingFiles {
  /// The files waiting, taken (each once).
  Future<List<PickedFile>> take();

  /// Calls [onArrived] when more arrive while Endless is open.
  void listen(void Function() onArrived);
}

/// `endless/incoming` on Android; nothing elsewhere yet.
class PlatformIncomingFiles implements IncomingFiles {
  static const _channel = MethodChannel('endless/incoming');

  @override
  Future<List<PickedFile>> take() async {
    if (!Platform.isAndroid) return const [];
    try {
      final list = await _channel.invokeListMethod<Map<Object?, Object?>>('take') ?? const [];
      final out = <PickedFile>[];
      for (final m in list) {
        final path = m['path'] as String?;
        if (path == null) continue;
        final f = File(path);
        if (!await f.exists()) continue;
        out.add(PickedFile(m['name'] as String? ?? 'shared.board', await f.readAsBytes()));
        await f.delete().catchError((Object _) => f);
      }
      return out;
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  @override
  void listen(void Function() onArrived) {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'arrived') onArrived();
    });
  }
}

final incomingFilesProvider = Provider<IncomingFiles>((ref) => PlatformIncomingFiles());
