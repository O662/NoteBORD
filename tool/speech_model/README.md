# Speech models (Phase 8a)

Transcripts and speakers are made on the tablet, offline, by three models in `assets/speech/`:

| File | What it does | Size | Licence | Where it comes from |
|---|---|---|---|---|
| `whisper-base-q5_1.bin` | Speech to text, 99 languages | 60 MB | MIT (OpenAI; ggml conversion by whisper.cpp) | Hugging Face `ggerganov/whisper.cpp`, pinned revision, SHA-256 checked |
| `segmentation-3.0.onnx` | Who speaks when, in 10 s windows | 6 MB | MIT (pyannote, CNRS) | Hugging Face `onnx-community/pyannote-segmentation-3.0`, pinned revision, SHA-256 checked |
| `speakers-ecapa.onnx` | A voice print per speaker | 22 MB | Apache-2.0 (SpeechBrain) | Exported here by `export_speakers.py`; **kept in git** |

The two downloaded files are too big for git. Before building the app:

```
dart run tool/speech_model/fetch.dart
```

It downloads them from pinned revisions and deletes anything whose SHA-256 doesn't match. Run it again at any time; matching files are left alone. A build without the models still works: the Transcript panel says the build has no speech model.

## How they run

- **Words:** whisper.cpp 1.9.5, vendored as source in `packages/endless_speech/src/whisper.cpp` (CPU only; no GPU back ends, examples, servers or downloaders) and built with the app. A small C++ bridge (`endless_speech.cpp`) runs it from a background isolate, a part of about 4 minutes at a time, cut where it's quietest. Each part is saved as it's heard, so an interrupted transcript carries on from there.
- **Speakers:** both ONNX models run on ONNX Runtime (Microsoft), which the app already uses for math (`flutter_onnxruntime`). `lib/audio/speakers.dart` groups the voice prints (agglomerative, cosine distance 0.65) and gives each line the speaker heard most during it, splitting a line where the speaker changes.

## Checking the native library has no network code

```
llvm-nm -D --undefined-only libendless_speech.so | grep -Ei 'socket|connect|getaddrinfo|gethostbyname|send|recv'
```

On the 2026-11-04 Android build this finds nothing (only `sendfile`, a local file copy from the C++ library). The bridge also sets `GGML_NO_BACKTRACE` (so ggml never launches a debugger after a crash) and clears `ANEFORGE_DYLIB` (an Apple-only accelerator library).

## Re-exporting the speaker model

```
python -m venv .venv && .venv/Scripts/activate   # Python 3.11
pip install torch==2.5.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cpu
pip install speechbrain==1.0.3 huggingface_hub==0.25.2 requests onnx==1.17.0 onnxruntime==1.20.1
python tool/speech_model/export_speakers.py --out assets/speech --work <a temp folder>
```

It downloads SpeechBrain's checkpoint at a pinned revision, checks its SHA-256, checks that the exported features and voice prints match SpeechBrain's own (cosine 1.0000 for the float model, above 0.99 for the 8-bit one), and writes `speakers.onnx`. Rename it to `speakers-ecapa.onnx` and update the hash in `fetch.dart`.

## Why these

The owner's requirements (2026-11-04): free, offline, able to tell speakers apart, and no code from companies required to share data with a government (so no Chinese-affiliated code, such as sherpa-onnx). Whisper (OpenAI, US), whisper.cpp (ggml.ai, Bulgaria), pyannote (CNRS, France), SpeechBrain (Mila and Avignon University, Canada and France) and ONNX Runtime (Microsoft, US) meet them. All the licences allow selling the app.

## Checking on a computer

`packages/endless_speech/test/whisper_native_test.dart` runs whisper.cpp for real when given the built library, the model and a WAV file:

```
cmake -S packages/endless_speech/src -B build/speech -A x64
cmake --build build/speech --config Release
ENDLESS_SPEECH_LIB=build/speech/Release/endless_speech.dll ENDLESS_SPEECH_MODEL=assets/speech/whisper-base-q5_1.bin \
ENDLESS_SPEECH_WAV=<a 16 kHz WAV> flutter test packages/endless_speech/test/whisper_native_test.dart
```
