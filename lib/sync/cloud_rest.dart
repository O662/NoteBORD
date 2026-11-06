import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cloud.dart';
import 'cloud_auth.dart';

// Google Drive (v3) and OneDrive (Microsoft Graph) as [CloudDrive]s, by
// path inside the sync folder.

/// Calls with a token, signing in again once if it's refused, and turns
/// failures into [CloudException]s.
abstract class _Rest implements CloudDrive {
  _Rest(this.auth, this.client);

  final CloudAuth auth;
  final http.Client client;

  /// Sends [build]'s request with the token; on 401 once more with a new one.
  Future<http.Response> send(http.BaseRequest Function(String token) build) async {
    for (var attempt = 0;; attempt++) {
      final token = await auth.token(fresh: attempt > 0);
      final http.Response r;
      try {
        r = await http.Response.fromStream(await client.send(build(token)));
      } on SocketException catch (e) {
        throw CloudException(CloudFailure.offline, e.message);
      } on http.ClientException catch (e) {
        throw CloudException(CloudFailure.offline, e.message);
      } on TimeoutException {
        throw const CloudException(CloudFailure.offline, 'The cloud didn’t answer');
      }
      if (r.statusCode == 401 && attempt == 0) continue;
      if (r.statusCode == 401) throw CloudException(CloudFailure.signedOut, 'Sign in to ${kind.label} again');
      if (r.statusCode == 507 || r.statusCode == 403 && r.body.contains('uota')) {
        throw CloudException(CloudFailure.full, '${kind.label} is full');
      }
      return r;
    }
  }

  Never fail(http.Response r, String what) =>
      throw CloudException(r.statusCode >= 500 ? CloudFailure.offline : CloudFailure.other, '$what failed (${r.statusCode})');

  http.Request req(String method, Uri url, String token, {Map<String, String>? headers, List<int>? body}) {
    final q = http.Request(method, url)..headers['Authorization'] = 'Bearer $token';
    if (headers != null) q.headers.addAll(headers);
    if (body != null) q.bodyBytes = body;
    return q;
  }

  /// Sends [file] in [chunk]-byte parts to [target] (a resumable upload
  /// address), reporting progress.
  Future<http.Response> sendChunks(
    Uri target,
    File file, {
    required int chunk,
    required bool withToken,
    void Function(double)? progress,
    CloudCancel? cancel,
  }) async {
    final size = await file.length();
    final raf = await file.open();
    try {
      var at = 0;
      while (true) {
        if (cancel?.cancelled ?? false) throw const CloudCancelled();
        final n = math.min(chunk, size - at);
        await raf.setPosition(at);
        final bytes = await raf.read(n);
        final headers = {
          'Content-Length': '$n',
          'Content-Range': size == 0 ? 'bytes */0' : 'bytes $at-${at + n - 1}/$size',
        };
        final http.Response r;
        if (withToken) {
          r = await send((t) => req('PUT', target, t, headers: headers, body: bytes));
        } else {
          try {
            r = await http.Response.fromStream(await client.send(http.Request('PUT', target)
              ..headers.addAll(headers)
              ..bodyBytes = bytes));
          } on SocketException catch (e) {
            throw CloudException(CloudFailure.offline, e.message);
          } on http.ClientException catch (e) {
            throw CloudException(CloudFailure.offline, e.message);
          }
        }
        at += n;
        progress?.call(size == 0 ? 1 : at / size);
        if (r.statusCode == 200 || r.statusCode == 201) return r;
        if (r.statusCode != 308 && r.statusCode != 202) fail(r, 'Uploading');
        if (at >= size) return r;
      }
    } finally {
      await raf.close();
    }
  }

  /// Streams [url] into [to], reporting progress.
  Future<void> streamTo(Uri url, File to, {Map<String, String> headers = const {}, void Function(double)? progress, CloudCancel? cancel}) async {
    final token = await auth.token();
    final http.StreamedResponse r;
    try {
      r = await client.send(http.Request('GET', url)
        ..headers.addAll({'Authorization': 'Bearer $token', ...headers}));
    } on SocketException catch (e) {
      throw CloudException(CloudFailure.offline, e.message);
    }
    if (r.statusCode != 200) throw CloudException(CloudFailure.other, 'Downloading failed (${r.statusCode})');
    await to.parent.create(recursive: true);
    final part = File('${to.path}.part');
    final sink = part.openWrite();
    var got = 0;
    final total = r.contentLength ?? 0;
    try {
      await for (final c in r.stream) {
        if (cancel?.cancelled ?? false) throw const CloudCancelled();
        sink.add(c);
        got += c.length;
        if (total > 0) progress?.call(got / total);
      }
    } finally {
      await sink.close();
    }
    await part.rename(to.path);
    progress?.call(1);
  }
}

/// Google Drive. With the `drive.file` scope Endless sees only the files
/// and folders it made, so the sync folder is one Endless made (in My
/// Drive, by name).
class GoogleDriveCloud extends _Rest {
  GoogleDriveCloud(super.auth, super.client, {required this.folder});

  @override
  CloudKind get kind => CloudKind.google;

  /// The sync folder's name, in My Drive.
  final String folder;

  static final _api = Uri.parse('https://www.googleapis.com/drive/v3/files');
  static final _upload = Uri.parse('https://www.googleapis.com/upload/drive/v3/files');
  static const _folderMime = 'application/vnd.google-apps.folder';

  /// Path → file id, as found.
  final _ids = <String, String>{};

  static String _q(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  Future<List<Map<String, dynamic>>> _query(String q) async {
    final out = <Map<String, dynamic>>[];
    String? page;
    do {
      final url = _api.replace(queryParameters: {
        'q': q,
        'fields': 'nextPageToken,files(id,name,mimeType,size)',
        'pageSize': '1000',
        'spaces': 'drive',
        'pageToken': ?page,
      });
      final r = await send((t) => req('GET', url, t));
      if (r.statusCode != 200) fail(r, 'Listing');
      final j = jsonDecode(r.body) as Map;
      out.addAll([for (final f in j['files'] as List) (f as Map).cast<String, dynamic>()]);
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  /// Folders Endless made in My Drive (to pick another sync folder).
  Future<List<String>> folders() async =>
      [for (final f in await _query("mimeType='$_folderMime' and 'root' in parents and trashed=false")) f['name'] as String];

  Future<String?> _id(String path, {bool make = false}) async {
    if (_ids[path] case final id?) return id;
    String? parent;
    String parentPath;
    String name;
    if (path.isEmpty) {
      parent = 'root';
      parentPath = '';
      name = folder;
    } else {
      final slash = path.lastIndexOf('/');
      parentPath = slash < 0 ? '' : path.substring(0, slash);
      name = slash < 0 ? path : path.substring(slash + 1);
      parent = await _id(parentPath, make: make);
      if (parent == null) return null;
    }
    final found = await _query("'$parent' in parents and name='${_q(name)}' and trashed=false");
    if (found.isNotEmpty) return _ids[path] = found.first['id'] as String;
    if (!make) return null;
    final r = await send((t) => req('POST', _api.replace(queryParameters: {'fields': 'id'}), t,
        headers: {'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode({'name': name, 'mimeType': _folderMime, 'parents': [parent]}))));
    if (r.statusCode != 200) fail(r, 'Making a folder');
    return _ids[path] = (jsonDecode(r.body) as Map)['id'] as String;
  }

  static (String, String) _split(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? ('', path) : (path.substring(0, slash), path.substring(slash + 1));
  }

  @override
  Future<List<CloudEntry>> list(String dir) async {
    final id = await _id(dir);
    if (id == null) return [];
    return [
      for (final f in await _query("'$id' in parents and trashed=false"))
        () {
          final name = f['name'] as String;
          _ids[dir.isEmpty ? name : '$dir/$name'] = f['id'] as String;
          return CloudEntry(name, folder: f['mimeType'] == _folderMime, size: int.tryParse('${f['size']}'));
        }(),
    ];
  }

  @override
  Future<Uint8List?> read(String path) async {
    final id = await _id(path);
    if (id == null) return null;
    final r = await send((t) => req('GET', _api.replace(path: '${_api.path}/$id', queryParameters: {'alt': 'media'}), t));
    if (r.statusCode == 404) {
      _ids.remove(path);
      return null;
    }
    if (r.statusCode != 200) fail(r, 'Reading');
    return r.bodyBytes;
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    final id = await _id(path);
    if (id != null) {
      final r = await send((t) => req('PATCH', _upload.replace(path: '${_upload.path}/$id', queryParameters: {'uploadType': 'media'}), t,
          headers: {'Content-Type': 'application/octet-stream'}, body: bytes));
      if (r.statusCode == 200) return;
      if (r.statusCode != 404) fail(r, 'Writing');
      _ids.remove(path);
    }
    final (dir, name) = _split(path);
    final parent = await _id(dir, make: true);
    const boundary = 'endless-sync-boundary';
    final body = <int>[
      ...utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'),
      ...utf8.encode(jsonEncode({'name': name, 'parents': [parent]})),
      ...utf8.encode('\r\n--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n'),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--'),
    ];
    final r = await send((t) => req('POST', _upload.replace(queryParameters: {'uploadType': 'multipart', 'fields': 'id'}), t,
        headers: {'Content-Type': 'multipart/related; boundary=$boundary'}, body: body));
    if (r.statusCode != 200) fail(r, 'Writing');
    _ids[path] = (jsonDecode(r.body) as Map)['id'] as String;
  }

  @override
  Future<void> delete(String path) async {
    final id = await _id(path);
    if (id == null) return;
    final r = await send((t) => req('DELETE', _api.replace(path: '${_api.path}/$id'), t));
    if (r.statusCode != 204 && r.statusCode != 200 && r.statusCode != 404) fail(r, 'Deleting');
    _ids.removeWhere((k, _) => k == path || k.startsWith('$path/'));
  }

  @override
  Future<void> rename(String path, String name) async {
    final id = await _id(path);
    if (id == null) return;
    final r = await send((t) => req('PATCH', _api.replace(path: '${_api.path}/$id', queryParameters: {'fields': 'id'}), t,
        headers: {'Content-Type': 'application/json'}, body: utf8.encode(jsonEncode({'name': name}))));
    if (r.statusCode != 200) fail(r, 'Renaming');
    _ids.removeWhere((k, _) => k == path || k.startsWith('$path/'));
  }

  @override
  Future<void> upload(String path, File file, {void Function(double)? progress, CloudCancel? cancel}) async {
    final existing = await _id(path);
    final (dir, name) = _split(path);
    final parent = existing == null ? await _id(dir, make: true) : null;
    final size = await file.length();
    final start = await send((t) => req(
          existing == null ? 'POST' : 'PATCH',
          _upload.replace(path: existing == null ? _upload.path : '${_upload.path}/$existing', queryParameters: {'uploadType': 'resumable', 'fields': 'id'}),
          t,
          headers: {'Content-Type': 'application/json; charset=UTF-8', 'X-Upload-Content-Length': '$size'},
          body: utf8.encode(jsonEncode({if (existing == null) ...{'name': name, 'parents': [parent]}})),
        ));
    final location = start.headers['location'];
    if (start.statusCode != 200 || location == null) fail(start, 'Starting the upload');
    final done = await sendChunks(Uri.parse(location), file, chunk: 8 * 1024 * 1024, withToken: true, progress: progress, cancel: cancel);
    _ids[path] = (jsonDecode(done.body) as Map)['id'] as String;
  }

  @override
  Future<void> download(String path, File to, {void Function(double)? progress, CloudCancel? cancel}) async {
    final id = await _id(path);
    if (id == null) throw CloudException(CloudFailure.other, 'It’s not in Google Drive any more');
    await streamTo(_api.replace(path: '${_api.path}/$id', queryParameters: {'alt': 'media'}), to, progress: progress, cancel: cancel);
  }

  @override
  Future<(Uri, Map<String, String>)?> media(String path) async {
    final id = await _id(path);
    if (id == null) return null;
    return (_api.replace(path: '${_api.path}/$id', queryParameters: {'alt': 'media'}), {'Authorization': 'Bearer ${await auth.token()}'});
  }
}

/// OneDrive, through Microsoft Graph, by path from the drive's top.
class OneDriveCloud extends _Rest {
  OneDriveCloud(super.auth, super.client, {required this.folder});

  @override
  CloudKind get kind => CloudKind.onedrive;

  final String folder;

  static const _graph = 'https://graph.microsoft.com/v1.0/me/drive';

  /// The item at [path] (in the sync folder), as Graph addresses it.
  String _item(String path) {
    final parts = [folder, ...path.split('/').where((s) => s.isNotEmpty)].map(Uri.encodeComponent).join('/');
    return '$_graph/root:/$parts:';
  }

  /// Folders at the top of the drive (to pick another sync folder).
  Future<List<String>> folders() async {
    final out = <String>[];
    var url = Uri.parse('$_graph/root/children?\$select=name,folder&\$top=200');
    while (true) {
      final r = await send((t) => req('GET', url, t));
      if (r.statusCode != 200) fail(r, 'Listing');
      final j = jsonDecode(r.body) as Map;
      out.addAll([
        for (final f in j['value'] as List)
          if ((f as Map)['folder'] != null) f['name'] as String,
      ]);
      final next = j['@odata.nextLink'] as String?;
      if (next == null) return out;
      url = Uri.parse(next);
    }
  }

  @override
  Future<List<CloudEntry>> list(String dir) async {
    final out = <CloudEntry>[];
    var url = Uri.parse('${_item(dir)}/children?\$select=name,size,folder&\$top=1000');
    while (true) {
      final r = await send((t) => req('GET', url, t));
      if (r.statusCode == 404) return out;
      if (r.statusCode != 200) fail(r, 'Listing');
      final j = jsonDecode(r.body) as Map;
      for (final f in j['value'] as List) {
        final m = f as Map;
        out.add(CloudEntry(m['name'] as String, folder: m['folder'] != null, size: (m['size'] as num?)?.toInt()));
      }
      final next = j['@odata.nextLink'] as String?;
      if (next == null) return out;
      url = Uri.parse(next);
    }
  }

  @override
  Future<Uint8List?> read(String path) async {
    final r = await send((t) => req('GET', Uri.parse('${_item(path)}/content'), t));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) fail(r, 'Reading');
    return r.bodyBytes;
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    if (bytes.length > 4 * 1024 * 1024) {
      final tmp = File('${Directory.systemTemp.path}/endless_up_${DateTime.now().microsecondsSinceEpoch}');
      await tmp.writeAsBytes(bytes);
      try {
        return await upload(path, tmp);
      } finally {
        await tmp.delete();
      }
    }
    final r = await send((t) => req('PUT', Uri.parse('${_item(path)}/content'), t,
        headers: {'Content-Type': 'application/octet-stream'}, body: bytes));
    if (r.statusCode != 200 && r.statusCode != 201) fail(r, 'Writing');
  }

  @override
  Future<void> delete(String path) async {
    final r = await send((t) => req('DELETE', Uri.parse(_item(path)), t));
    if (r.statusCode != 204 && r.statusCode != 200 && r.statusCode != 404) fail(r, 'Deleting');
  }

  @override
  Future<void> rename(String path, String name) async {
    final r = await send((t) => req('PATCH', Uri.parse(_item(path)), t,
        headers: {'Content-Type': 'application/json'}, body: utf8.encode(jsonEncode({'name': name}))));
    if (r.statusCode != 200 && r.statusCode != 404) fail(r, 'Renaming');
  }

  @override
  Future<void> upload(String path, File file, {void Function(double)? progress, CloudCancel? cancel}) async {
    final start = await send((t) => req('POST', Uri.parse('${_item(path)}/createUploadSession'), t,
        headers: {'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode({
          'item': {'@microsoft.graph.conflictBehavior': 'replace'},
        }))));
    if (start.statusCode != 200) fail(start, 'Starting the upload');
    final url = (jsonDecode(start.body) as Map)['uploadUrl'] as String;
    // Parts must be multiples of 320 KiB.
    await sendChunks(Uri.parse(url), file, chunk: 320 * 1024 * 32, withToken: false, progress: progress, cancel: cancel);
  }

  @override
  Future<void> download(String path, File to, {void Function(double)? progress, CloudCancel? cancel}) =>
      streamTo(Uri.parse('${_item(path)}/content'), to, progress: progress, cancel: cancel);

  @override
  Future<(Uri, Map<String, String>)?> media(String path) async {
    final r = await send((t) => req('GET', Uri.parse('${_item(path)}?\$select=id,@microsoft.graph.downloadUrl'), t));
    if (r.statusCode != 200) return null;
    final url = (jsonDecode(r.body) as Map)['@microsoft.graph.downloadUrl'] as String?;
    return url == null ? null : (Uri.parse(url), const <String, String>{});
  }
}
