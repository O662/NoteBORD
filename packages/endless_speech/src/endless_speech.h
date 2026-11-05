// Endless's bridge to whisper.cpp: speech to text on the device, offline.
//
// Nothing here touches the network or the file system beyond reading the
// model file it is given.

#ifndef ENDLESS_SPEECH_H
#define ENDLESS_SPEECH_H

#include <stdint.h>

#if _WIN32
#define ES_EXPORT __declspec(dllexport)
#else
#define ES_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct es_context es_context;

// Loads a whisper.cpp model (ggml .bin). Null if it can't be read.
ES_EXPORT es_context *es_open(const char *model_path, int32_t threads);

ES_EXPORT void es_close(es_context *ctx);

// Transcribes [n] samples of 16 kHz mono audio in [-1, 1].
//
// [language] is a language code ("en", "de", …) or "auto". [prompt] (may be
// null) is the text heard just before, so a long recording read in parts
// keeps its context. [offset_ms] is added to every time.
//
// [cancel] (may be null) is read while it works: non-zero stops it.
// [progress] (may be null) is written with 0–100 as it goes.
//
// Returns JSON (free it with es_free_string), or null on failure:
//   {"language":"en","segments":[{"t0":ms,"t1":ms,"text":"…",
//     "words":[[t0,t1,"word"],…]}]}
ES_EXPORT char *es_transcribe(es_context *ctx, const float *samples, int32_t n, const char *language,
                              const char *prompt, int64_t offset_ms, volatile int32_t *cancel,
                              volatile int32_t *progress);

ES_EXPORT void es_free_string(char *s);

// The whisper.cpp version this was built from.
ES_EXPORT const char *es_version(void);

#ifdef __cplusplus
}
#endif

#endif
