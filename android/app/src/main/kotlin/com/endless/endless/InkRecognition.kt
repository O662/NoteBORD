package com.endless.endless

import com.google.mlkit.common.MlKitException
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognition
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognitionModel
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognitionModelIdentifier
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognizer
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognizerOptions
import com.google.mlkit.vision.digitalink.recognition.Ink
import com.google.mlkit.vision.digitalink.recognition.RecognitionContext
import com.google.mlkit.vision.digitalink.recognition.WritingArea
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Handwriting recognition with Google ML Kit Digital Ink, for
 * lib/recognition/recognizer.dart (channel `endless/ink`).
 *
 * Endless talks to ML Kit itself: google_mlkit_digital_ink_recognition
 * 0.15.0 doesn't work on Android (its Dart side calls a channel its Android
 * side doesn't register, and its model check never replies).
 *
 * Every call answers exactly once, so nothing on the Dart side waits forever.
 *  - `check` {language} → whether the model is on the tablet
 *  - `download` {language} → whether it downloaded (false offline)
 *  - `recognize` {language, strokes: [[x, y, t, x, y, t, …], …],
 *    preContext, width, height} → readings, best first
 *  - `close` → frees the recognizers
 */
class InkRecognition(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "endless/ink")
    private val models = RemoteModelManager.getInstance()
    private val recognizers = mutableMapOf<String, DigitalInkRecognizer>()

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        close()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "check" -> check(call, result)
            "download" -> download(call, result)
            "recognize" -> recognize(call, result)
            "close" -> {
                close()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** The model for a language tag, or null if ML Kit has none for it. */
    private fun model(tag: String?): DigitalInkRecognitionModel? {
        if (tag == null) return null
        val id = try {
            DigitalInkRecognitionModelIdentifier.fromLanguageTag(tag)
        } catch (e: MlKitException) {
            null
        } ?: return null
        return DigitalInkRecognitionModel.builder(id).build()
    }

    private fun check(call: MethodCall, result: MethodChannel.Result) {
        val model = model(call.argument("language")) ?: return result.success(false)
        try {
            models.isModelDownloaded(model)
                .addOnSuccessListener { result.success(it == true) }
                .addOnFailureListener { result.success(false) }
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun download(call: MethodCall, result: MethodChannel.Result) {
        val model = model(call.argument("language")) ?: return result.success(false)
        try {
            // Not only on Wi-Fi: the model is about 20 MB and asked for once.
            models.download(model, DownloadConditions.Builder().build())
                .addOnSuccessListener { result.success(true) }
                .addOnFailureListener { result.success(false) }
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun recognize(call: MethodCall, result: MethodChannel.Result) {
        val tag = call.argument<String>("language")
        val model = model(tag) ?: return result.error("language", "No handwriting model for $tag", null)
        val strokes = call.argument<List<List<Number>>>("strokes") ?: emptyList()
        val ink = Ink.builder()
        for (flat in strokes) {
            val stroke = Ink.Stroke.builder()
            var i = 0
            while (i + 2 < flat.size) {
                stroke.addPoint(Ink.Point.create(flat[i].toFloat(), flat[i + 1].toFloat(), flat[i + 2].toLong()))
                i += 3
            }
            ink.addStroke(stroke.build())
        }
        val context = RecognitionContext.builder().setPreContext(call.argument<String>("preContext") ?: "")
        val width = call.argument<Number>("width")?.toFloat()
        val height = call.argument<Number>("height")?.toFloat()
        if (width != null && height != null && width > 0 && height > 0) context.setWritingArea(WritingArea(width, height))
        try {
            val recognizer = recognizers.getOrPut(tag!!) {
                DigitalInkRecognition.getClient(DigitalInkRecognizerOptions.builder(model).build())
            }
            recognizer.recognize(ink.build(), context.build())
                .addOnSuccessListener { r -> result.success(r.candidates.map { it.text }) }
                .addOnFailureListener { e -> result.error("recognize", e.message ?: e.toString(), null) }
        } catch (e: Exception) {
            result.error("recognize", e.message ?: e.toString(), null)
        }
    }

    private fun close() {
        for (r in recognizers.values) r.close()
        recognizers.clear()
    }
}
