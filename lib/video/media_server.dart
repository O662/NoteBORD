import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Serves videos from memory to the player and to Android's frame reader,
/// on this device only (127.0.0.1, a random port, an unguessable address
/// per video). A video on a page with a password is opened in memory and
/// played from here, so it's never written out in the clear.
class MediaServer {
  HttpServer? _server;
  final _files = <String, (Uint8List, String)>{};
  final _random = math.Random.secure();

  /// Serves [bytes] as [type] until [release]d. Returns its address.
  Future<String> serve(Uint8List bytes, String type) async {
    final server = _server ??= await _start();
    final token = List.generate(24, (_) => _random.nextInt(16).toRadixString(16)).join();
    _files[token] = (bytes, type);
    return 'http://127.0.0.1:${server.port}/$token';
  }

  void release(String url) => _files.remove(Uri.parse(url).pathSegments.lastOrNull);

  Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_answer);
    return server;
  }

  Future<void> _answer(HttpRequest req) async {
    final res = req.response;
    try {
      final file = _files[req.uri.pathSegments.lastOrNull];
      if (file == null || req.method != 'GET' && req.method != 'HEAD') {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final (bytes, type) = file;
      var start = 0, end = bytes.length - 1;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final m = range == null ? null : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      if (m != null) {
        if (m[1]!.isNotEmpty) start = int.parse(m[1]!);
        if (m[2]!.isNotEmpty) end = math.min(bytes.length - 1, int.parse(m[2]!));
        if (m[1]!.isEmpty && m[2]!.isNotEmpty) {
          start = math.max(0, bytes.length - int.parse(m[2]!));
          end = bytes.length - 1;
        }
        if (start > end || start >= bytes.length) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${bytes.length}');
          return;
        }
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${bytes.length}');
      }
      res.headers
        ..contentType = ContentType.parse(type)
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = end - start + 1;
      if (req.method == 'GET') res.add(Uint8List.sublistView(bytes, start, end + 1));
    } finally {
      await res.close().catchError((Object _) => null);
    }
  }

  Future<void> close() async {
    _files.clear();
    await _server?.close(force: true);
    _server = null;
  }
}

final mediaServerProvider = Provider<MediaServer>((ref) {
  final s = MediaServer();
  ref.onDispose(s.close);
  return s;
});
