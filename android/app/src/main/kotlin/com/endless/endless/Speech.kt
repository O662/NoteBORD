package com.endless.endless

import android.content.Context
import android.speech.tts.TextToSpeech
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/// Says a word out loud for the dictionary's "Hear it" (lib/spelling/speech.dart).
/// The engine starts on first use; every call answers exactly once.
class Speech(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "endless/speech")
    private var tts: TextToSpeech? = null
    private var ready = false
    private val waiting = mutableListOf<() -> Unit>()

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "speak") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val text = call.argument<String>("text")
            val language = call.argument<String>("language") ?: "en-US"
            if (text.isNullOrBlank()) {
                result.success(false)
                return@setMethodCallHandler
            }
            whenReady { ok ->
                val engine = tts
                if (!ok || engine == null) {
                    result.success(false)
                    return@whenReady
                }
                val set = engine.setLanguage(Locale.forLanguageTag(language))
                if (set == TextToSpeech.LANG_MISSING_DATA || set == TextToSpeech.LANG_NOT_SUPPORTED) {
                    result.success(false)
                    return@whenReady
                }
                result.success(engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "endless-word") == TextToSpeech.SUCCESS)
            }
        }
    }

    private fun whenReady(then: (Boolean) -> Unit) {
        if (ready) {
            then(true)
            return
        }
        waiting.add { then(ready) }
        if (tts != null) return
        tts = TextToSpeech(context) { status ->
            ready = status == TextToSpeech.SUCCESS
            if (!ready) {
                tts?.shutdown()
                tts = null
            }
            val calls = waiting.toList()
            waiting.clear()
            calls.forEach { it() }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        tts?.shutdown()
        tts = null
        ready = false
    }
}
