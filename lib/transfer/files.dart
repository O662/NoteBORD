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

/// What can be imported, by extension.
const importExtensions = ['pdf', 'board', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'];

abstract class FileTransfer {
  /// Asks for files to import. Empty when cancelled.
  Future<List<PickedFile>> pick();

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
      dialogTitle: 'Choose a PDF, image or .board file',
      // Android doesn't know a MIME type for .board, so the filter would
      // hide those files there; the dialog checks what was picked instead.
      type: Platform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isAndroid ? null : importExtensions,
    );
    return [for (final f in files) PickedFile(f.name, await f.readAsBytes())];
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
