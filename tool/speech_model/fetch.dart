// Fetches the speech models into assets/speech/ and checks them.
//
//   dart run tool/speech_model/fetch.dart
//
// Each file comes from a pinned revision on Hugging Face and must match its
// SHA-256, or it is deleted and the script fails. Files already there and
// matching are left alone. The speaker model (speakers-ecapa.onnx) is kept
// in git; it is checked too. See tool/speech_model/README.md.

import 'dart:io';

import 'package:cryptography/dart.dart';

const _models = [
  (
    file: 'whisper-base-q5_1.bin',
    url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base-q5_1.bin',
    sha256: '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898',
  ),
  (
    file: 'segmentation-3.0.onnx',
    url: 'https://huggingface.co/onnx-community/pyannote-segmentation-3.0/resolve/733a93b6473d019a773298e08cefa686894b1854/onnx/model.onnx',
    sha256: '057ee564753071c0b09b5b611648b50ac188d50846bff5f01e9f7bbf1591ea25',
  ),
];

const _kept = (file: 'speakers-ecapa.onnx', sha256: '7f8463b0a19148bb62b3aca75a2dd0b54121538ee24e9eef86b6168f487408dc');

Future<String> _sha(File f) async {
  final sink = const DartSha256().newHashSink();
  await for (final chunk in f.openRead()) {
    sink.add(chunk);
  }
  sink.close();
  final hash = await sink.hash();
  return [for (final b in hash.bytes) b.toRadixString(16).padLeft(2, '0')].join();
}

Future<void> main() async {
  final dir = Directory('assets/speech');
  if (!dir.existsSync()) {
    stderr.writeln('Run this from the repository root.');
    exitCode = 2;
    return;
  }
  final client = HttpClient()..userAgent = 'endless-model-fetch';
  try {
    for (final m in _models) {
      final out = File('${dir.path}/${m.file}');
      if (out.existsSync() && await _sha(out) == m.sha256) {
        stdout.writeln('${m.file}: already here, checked');
        continue;
      }
      stdout.writeln('${m.file}: downloading…');
      final part = File('${out.path}.part');
      var uri = Uri.parse(m.url);
      HttpClientResponse res;
      // Hugging Face answers with a redirect to its file store.
      for (var hops = 0;; hops++) {
        final req = await client.getUrl(uri);
        req.followRedirects = false;
        res = await req.close();
        if (res.isRedirect && hops < 5) {
          uri = uri.resolve(res.headers.value(HttpHeaders.locationHeader)!);
          await res.drain<void>();
          continue;
        }
        break;
      }
      if (res.statusCode != 200) {
        stderr.writeln('${m.file}: HTTP ${res.statusCode}');
        exitCode = 1;
        return;
      }
      await res.pipe(part.openWrite());
      final got = await _sha(part);
      if (got != m.sha256) {
        await part.delete();
        stderr.writeln('${m.file}: SHA-256 $got, expected ${m.sha256}. Deleted.');
        exitCode = 1;
        return;
      }
      await part.rename(out.path);
      stdout.writeln('${m.file}: ${(out.lengthSync() / 1e6).toStringAsFixed(1)} MB, checked');
    }
    final kept = File('${dir.path}/${_kept.file}');
    if (!kept.existsSync() || await _sha(kept) != _kept.sha256) {
      stderr.writeln('${_kept.file}: missing or changed (export it with tool/speech_model/export_speakers.py).');
      exitCode = 1;
      return;
    }
    stdout.writeln('${_kept.file}: checked');
  } finally {
    client.close();
  }
}
