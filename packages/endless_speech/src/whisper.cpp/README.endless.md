# whisper.cpp, vendored

This is whisper.cpp **v1.9.5** (MIT, https://github.com/ggml-org/whisper.cpp), from the release tarball
`https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.9.5.tar.gz`
(SHA-256 `ff1a9053feb509ff9d7729703355541ae9690073a6b1c40eb692c962e0dc1720`), with only what a CPU build needs:

- kept: `CMakeLists.txt`, `cmake/`, `include/`, `src/` (whisper itself), `ggml/` with its CPU back end, `LICENSE`, `AUTHORS`;
- removed: examples, bindings, tests, models, samples, scripts, the server, and every GPU or accelerator back end (CUDA, Metal, Vulkan, OpenCL, SYCL, CANN, WebGPU, …), Core ML, OpenVINO, Vitis AI, KleidiAI and SpacemiT code.

Nothing was changed in the files kept. `../CMakeLists.txt` builds it with no downloads, no OpenMP and no GPU, and links it into `libendless_speech`.

To update: download a newer release, copy the same folders over these, and check that `../endless_speech.cpp` still builds against `include/whisper.h`.
