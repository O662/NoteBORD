# endless_speech

Endless's speech to text, on the device and offline: [whisper.cpp](https://github.com/ggml-org/whisper.cpp) 1.9.5 (MIT), vendored as source in `src/whisper.cpp` (CPU only; see its `README.endless.md`), behind a small C++ bridge (`src/endless_speech.cpp`) used through `dart:ffi` (`lib/endless_speech.dart`).

The bridge only reads the model file and the samples it's given. Nothing here opens a network connection or downloads anything, at run time or at build time.

Built for Android (arm64-v8a, armeabi-v7a, x86_64) by the Android Gradle Plugin's CMake, and for Windows by the Flutter Windows build. The models and how they were chosen: `tool/speech_model/README.md` in the app.
