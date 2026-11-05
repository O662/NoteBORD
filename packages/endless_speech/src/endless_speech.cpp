#include "endless_speech.h"

#include <cstdlib>
#include <stdlib.h>
#include <cstring>
#include <string>

#include "whisper.h"

struct es_context {
  whisper_context *whisper;
  int32_t threads;
};

namespace {

void quiet_log(enum ggml_log_level, const char *, void *) {}

void append_json_string(std::string &out, const std::string &s) {
  out += '"';
  for (const unsigned char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) {
          char buf[8];
          snprintf(buf, sizeof buf, "\\u%04x", c);
          out += buf;
        } else {
          out += static_cast<char>(c);
        }
    }
  }
  out += '"';
}

struct Watch {
  volatile int32_t *cancel;
  volatile int32_t *progress;
};

bool should_abort(void *data) {
  auto *w = static_cast<Watch *>(data);
  return w->cancel != nullptr && *w->cancel != 0;
}

bool should_continue(whisper_context *, whisper_state *, void *data) { return !should_abort(data); }

void on_progress(whisper_context *, whisper_state *, int progress, void *data) {
  auto *w = static_cast<Watch *>(data);
  if (w->progress != nullptr) *w->progress = progress;
}

}  // namespace

extern "C" {

es_context *es_open(const char *model_path, int32_t threads) {
  // ggml would start a debugger (fork + exec gdb/lldb) to print a backtrace
  // if it crashed, and whisper.cpp loads an Apple accelerator library named
  // by ANEFORGE_DYLIB. Neither is wanted here: nothing but this library and
  // the model runs.
#if _WIN32
  _putenv_s("GGML_NO_BACKTRACE", "1");
  _putenv_s("ANEFORGE_DYLIB", "");
#else
  setenv("GGML_NO_BACKTRACE", "1", 1);
  unsetenv("ANEFORGE_DYLIB");
#endif
  whisper_log_set(quiet_log, nullptr);
  whisper_context_params params = whisper_context_default_params();
  params.use_gpu = false;
  params.flash_attn = true;
  whisper_context *w = whisper_init_from_file_with_params(model_path, params);
  if (w == nullptr) return nullptr;
  auto *ctx = new es_context;
  ctx->whisper = w;
  ctx->threads = threads < 1 ? 1 : threads;
  return ctx;
}

void es_close(es_context *ctx) {
  if (ctx == nullptr) return;
  whisper_free(ctx->whisper);
  delete ctx;
}

char *es_transcribe(es_context *ctx, const float *samples, int32_t n, const char *language, const char *prompt,
                    int64_t offset_ms, volatile int32_t *cancel, volatile int32_t *progress) {
  if (ctx == nullptr || samples == nullptr || n <= 0) return nullptr;
  Watch watch{cancel, progress};

  whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  p.n_threads = ctx->threads;
  p.print_progress = false;
  p.print_realtime = false;
  p.print_timestamps = false;
  p.print_special = false;
  p.translate = false;
  p.language = (language == nullptr || language[0] == '\0') ? "auto" : language;
  p.detect_language = false;
  p.initial_prompt = (prompt != nullptr && prompt[0] != '\0') ? prompt : nullptr;
  p.token_timestamps = true;
  p.suppress_nst = true;
  p.abort_callback = should_abort;
  p.abort_callback_user_data = &watch;
  p.encoder_begin_callback = should_continue;
  p.encoder_begin_callback_user_data = &watch;
  p.progress_callback = on_progress;
  p.progress_callback_user_data = &watch;

  if (whisper_full(ctx->whisper, p, samples, n) != 0) return nullptr;
  if (should_abort(&watch)) return nullptr;

  const whisper_token eot = whisper_token_eot(ctx->whisper);
  std::string out = "{\"language\":";
  append_json_string(out, whisper_lang_str(whisper_full_lang_id(ctx->whisper)));
  out += ",\"segments\":[";
  const int segments = whisper_full_n_segments(ctx->whisper);
  for (int i = 0; i < segments; i++) {
    if (i > 0) out += ',';
    // Segment times are in 10 ms steps.
    const int64_t t0 = whisper_full_get_segment_t0(ctx->whisper, i) * 10 + offset_ms;
    const int64_t t1 = whisper_full_get_segment_t1(ctx->whisper, i) * 10 + offset_ms;
    out += "{\"t0\":" + std::to_string(t0) + ",\"t1\":" + std::to_string(t1) + ",\"text\":";
    append_json_string(out, whisper_full_get_segment_text(ctx->whisper, i));
    out += ",\"words\":[";
    // Words: tokens joined until the next one starts with a space.
    std::string word;
    int64_t w0 = -1, w1 = -1;
    bool first = true;
    auto flush = [&]() {
      if (word.empty()) return;
      if (!first) out += ',';
      first = false;
      out += '[' + std::to_string(w0 * 10 + offset_ms) + ',' + std::to_string(w1 * 10 + offset_ms) + ',';
      append_json_string(out, word);
      out += ']';
      word.clear();
    };
    const int tokens = whisper_full_n_tokens(ctx->whisper, i);
    for (int j = 0; j < tokens; j++) {
      const whisper_token_data d = whisper_full_get_token_data(ctx->whisper, i, j);
      if (d.id >= eot) continue;  // timestamps and other special tokens
      const char *text = whisper_full_get_token_text(ctx->whisper, i, j);
      if (text == nullptr || text[0] == '\0') continue;
      if (text[0] == ' ' && !word.empty()) flush();
      if (word.empty()) w0 = d.t0;
      word += text;
      w1 = d.t1;
    }
    flush();
    out += "]}";
  }
  out += "]}";

  char *result = static_cast<char *>(std::malloc(out.size() + 1));
  if (result == nullptr) return nullptr;
  std::memcpy(result, out.c_str(), out.size() + 1);
  return result;
}

void es_free_string(char *s) { std::free(s); }

const char *es_version(void) { return "whisper.cpp 1.9.5"; }

}  // extern "C"
