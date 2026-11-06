import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

// Where notebooks are copied to: Google Drive, OneDrive, or (for tests and
// trying two installs on one computer) a folder. Paths are relative to the
// folder picked for sync ("Endless Notebooks"), with `/` between parts.

/// Which cloud.
enum CloudKind {
  google('Google Drive'),
  onedrive('OneDrive'),
  folder('a folder');

  const CloudKind(this.label);

  /// As it's named to people: "Synced to Google Drive".
  final String label;
}

/// Why a cloud call failed.
enum CloudFailure {
  /// No connection (or the server couldn't be reached).
  offline,

  /// Signed out, or the sign-in ran out: sign in again.
  signedOut,

  /// The cloud is full.
  full,

  /// Anything else.
  other,
}

class CloudException implements Exception {
  const CloudException(this.failure, this.message);

  final CloudFailure failure;
  final String message;

  @override
  String toString() => 'CloudException(${failure.name}): $message';
}

/// One thing in a cloud folder.
class CloudEntry {
  const CloudEntry(this.name, {this.folder = false, this.size});

  final String name;
  final bool folder;
  final int? size;
}

/// Lets an upload or download be stopped.
class CloudCancel {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class CloudCancelled implements Exception {
  const CloudCancelled();
}

/// A cloud folder, by path.
abstract class CloudDrive {
  CloudKind get kind;

  /// What's directly in [dir] ('' is the sync folder itself); empty if it
  /// doesn't exist.
  Future<List<CloudEntry>> list(String dir);

  /// A file's contents, or null if there's no such file.
  Future<Uint8List?> read(String path);

  /// Writes a file (making its folders), replacing any.
  Future<void> write(String path, Uint8List bytes);

  /// Deletes a file or a folder and everything in it (nothing if absent).
  Future<void> delete(String path);

  /// Sends a big file in parts, reporting how far it's got (0–1).
  Future<void> upload(String path, File file, {void Function(double)? progress, CloudCancel? cancel});

  /// Fetches a big file to [to], reporting how far it's got (0–1).
  Future<void> download(String path, File to, {void Function(double)? progress, CloudCancel? cancel});

  /// Where the file can be read from with byte ranges, and the headers that
  /// go with it (for playing a video from the cloud), or null.
  Future<(Uri, Map<String, String>)?> media(String path);
}

/// A cloud kept in memory, for tests.
class MemoryCloud implements CloudDrive {
  MemoryCloud({this.kind = CloudKind.google});

  @override
  final CloudKind kind;

  final files = <String, Uint8List>{};

  /// Every write, in order (for tests to count requests).
  final writes = <String>[];
  final reads = <String>[];

  /// Set to make every call fail.
  CloudFailure? failing;

  void _check() {
    if (failing != null) throw CloudException(failing!, 'failing');
  }

  @override
  Future<List<CloudEntry>> list(String dir) async {
    _check();
    final prefix = dir.isEmpty ? '' : '$dir/';
    final out = <String, CloudEntry>{};
    for (final e in files.entries) {
      if (!e.key.startsWith(prefix)) continue;
      final rest = e.key.substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        out[rest] = CloudEntry(rest, size: e.value.length);
      } else {
        final name = rest.substring(0, slash);
        out[name] = CloudEntry(name, folder: true);
      }
    }
    return out.values.toList();
  }

  @override
  Future<Uint8List?> read(String path) async {
    _check();
    reads.add(path);
    return files[path];
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    _check();
    writes.add(path);
    files[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String path) async {
    _check();
    files.removeWhere((k, _) => k == path || k.startsWith('$path/'));
  }

  @override
  Future<void> upload(String path, File file, {void Function(double)? progress, CloudCancel? cancel}) async {
    _check();
    final bytes = await file.readAsBytes();
    for (var i = 1; i <= 4; i++) {
      if (cancel?.cancelled ?? false) throw const CloudCancelled();
      progress?.call(i / 4);
      await Future<void>.delayed(Duration.zero);
    }
    await write(path, bytes);
  }

  @override
  Future<void> download(String path, File to, {void Function(double)? progress, CloudCancel? cancel}) async {
    final bytes = await read(path);
    if (bytes == null) throw CloudException(CloudFailure.other, 'No such file: $path');
    await to.parent.create(recursive: true);
    await to.writeAsBytes(bytes);
    progress?.call(1);
  }

  @override
  Future<(Uri, Map<String, String>)?> media(String path) async => null;
}

/// A folder on this computer, used as the cloud: two installs pointed at
/// the same folder sync with each other (tests, and trying sync out).
class FolderCloud implements CloudDrive {
  FolderCloud(this.root);

  final Directory root;

  @override
  CloudKind get kind => CloudKind.folder;

  File _file(String path) => File(p.joinAll([root.path, ...path.split('/').where((s) => s.isNotEmpty && s != '..')]));

  @override
  Future<List<CloudEntry>> list(String dir) async {
    final d = dir.isEmpty ? root : Directory(_file(dir).path);
    if (!await d.exists()) return [];
    return [
      await for (final e in d.list())
        if (!e.path.endsWith('.part'))
          CloudEntry(p.basename(e.path), folder: e is Directory, size: e is File ? await e.length() : null),
    ];
  }

  @override
  Future<Uint8List?> read(String path) async {
    final f = _file(path);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    final f = _file(path);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String path) async {
    final f = _file(path);
    if (await f.exists()) {
      await f.delete();
    } else if (await Directory(f.path).exists()) {
      await Directory(f.path).delete(recursive: true);
    }
  }

  @override
  Future<void> upload(String path, File file, {void Function(double)? progress, CloudCancel? cancel}) async {
    if (cancel?.cancelled ?? false) throw const CloudCancelled();
    final f = _file(path);
    await f.parent.create(recursive: true);
    await file.copy(f.path);
    progress?.call(1);
  }

  @override
  Future<void> download(String path, File to, {void Function(double)? progress, CloudCancel? cancel}) async {
    final f = _file(path);
    if (!await f.exists()) throw CloudException(CloudFailure.other, 'No such file: $path');
    await to.parent.create(recursive: true);
    await f.copy(to.path);
    progress?.call(1);
  }

  @override
  Future<(Uri, Map<String, String>)?> media(String path) async => (Uri.file(_file(path).path), const <String, String>{});
}
