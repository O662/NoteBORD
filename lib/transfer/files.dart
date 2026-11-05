import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

// Files in and out of the app: the system file picker, its Save dialog, the
// share sheet and the print dialog. Tests supply their own.

/// A file the user picked.
class PickedFile {
  const PickedFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;

  String get extension => p.extension(name).toLowerCase().replaceFirst('.', '');
}

/// A video picked: its name, its size, and its bytes as a stream (it can
/// be big; Android may hand over a content:// address, not a path).
class PickedVideo {
  const PickedVideo(this.name, this.length, this.read);

  /// Bytes in memory (tests).
  factory PickedVideo.bytes(String name, Uint8List bytes) =>
      PickedVideo(name, () async => bytes.length, () => Stream.value(bytes));

  final String name;
  final Future<int?> Function() length;
  final Stream<List<int>> Function() read;

  Future<Uint8List> readAll() async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in read()) {
      out.add(chunk);
    }
    return out.takeBytes();
  }
}

/// What can be imported, by extension.
const importExtensions = ['pdf', 'board', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'docx', 'pptx', 'xlsx'];

abstract class FileTransfer {
  /// Asks for files to import. Empty when cancelled.
  Future<List<PickedFile>> pick();

  /// Asks for one file with one of [extensions]. Null when cancelled.
  Future<PickedFile?> pickOne(List<String> extensions, {required String title});

  /// Asks for a video (not read into memory: it can be big). Null when
  /// cancelled.
  Future<PickedVideo?> pickVideo();

  /// Asks where to save [bytes] as [name]. False when cancelled.
  Future<bool> save(String name, Uint8List bytes, String mime);

  /// Opens the share sheet with the file.
  Future<void> share(String name, Uint8List bytes, String mime);

  /// Opens the print dialog for a PDF.
  Future<void> print(String name, Uint8List pdf);
}

class DeviceFileTransfer implements FileTransfer {
  const DeviceFileTransfer();

  @override
  Future<List<PickedFile>> pick() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose a PDF, image, Office or .board file',
      // Android doesn't know a MIME type for .board, so the filter would
      // hide those files there; the dialog checks what was picked instead.
      type: Platform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isAndroid ? null : importExtensions,
    );
    return [for (final f in files) PickedFile(f.name, await f.readAsBytes())];
  }

  @override
  Future<PickedFile?> pickOne(List<String> extensions, {required String title}) async {
    final files = await FilePicker.pickFiles(dialogTitle: title, type: FileType.custom, allowedExtensions: extensions);
    final f = files.firstOrNull;
    return f == null ? null : PickedFile(f.name, await f.readAsBytes());
  }

  @override
  Future<PickedVideo?> pickVideo() async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Choose a video', type: FileType.video);
    final f = files.firstOrNull;
    if (f == null) return null;
    return PickedVideo(f.name, f.length, f.readAsByteStream);
  }

  @override
  Future<bool> save(String name, Uint8List bytes, String mime) async =>
      await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mime, dialogTitle: 'Save $name') != null;

  @override
  Future<void> share(String name, Uint8List bytes, String mime) async {
    final dir = await getTemporaryDirectory();
    final out = Directory(p.join(dir.path, 'share'));
    await out.create(recursive: true);
    final file = File(p.join(out.path, name));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime, name: name)], title: name));
  }

  @override
  Future<void> print(String name, Uint8List pdf) => Printing.layoutPdf(onLayout: (_) async => pdf, name: name);
}

final fileTransferProvider = Provider<FileTransfer>((ref) => const DeviceFileTransfer());

/// [title] as a file name: no characters file systems refuse, at most 80
/// long, and [ext] on the end.
String fileNameFor(String title, String ext) {
  var name = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '-').trim();
  if (name.length > 80) name = name.substring(0, 80).trim();
  if (name.isEmpty || name.startsWith('.')) name = 'Notebook$name';
  return '$name.$ext';
}
