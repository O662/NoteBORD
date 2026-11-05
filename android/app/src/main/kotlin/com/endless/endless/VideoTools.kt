package com.endless.endless

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/// Videos on the page (lib/video/video_tools.dart), with Android's own
/// MediaMetadataRetriever. `source` is a file path, or an http://127.0.0.1
/// address the app serves a sealed video from (nothing leaves the device).
///
/// - `info {source}`: `{durationMs, width, height}` (as shown, turned).
/// - `frame {source, ms, maxWidth}`: the frame at that moment, as JPEG.
/// - `strip {source, count, maxWidth, fromMs, toMs}`: [count] frames evenly
///   between the two times, as JPEGs (the Trim dialog's strip).
class VideoTools(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "endless/video")
    private val work = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            val source = call.argument<String>("source")
            if (source == null) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            when (call.method) {
                "info" -> run(result) { info(source) }
                "frame" -> run(result) {
                    frame(source, (call.argument<Number>("ms") ?: 0).toLong(), call.argument<Int>("maxWidth") ?: 1280)
                }
                "strip" -> run(result) {
                    strip(
                        source,
                        call.argument<Int>("count") ?: 8,
                        call.argument<Int>("maxWidth") ?: 160,
                        (call.argument<Number>("fromMs") ?: 0).toLong(),
                        (call.argument<Number>("toMs") ?: 0).toLong(),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun run(result: MethodChannel.Result, job: () -> Any?) {
        work.execute {
            try {
                val value = job()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("video", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun open(source: String): MediaMetadataRetriever {
        val r = MediaMetadataRetriever()
        if (source.startsWith("http://")) r.setDataSource(source, HashMap()) else r.setDataSource(source)
        return r
    }

    private fun info(source: String): Map<String, Any> {
        val r = open(source)
        try {
            val ms = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            var w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            var h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val turn = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (turn == 90 || turn == 270) {
                val t = w
                w = h
                h = t
            }
            val audio = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            return mapOf("durationMs" to ms, "width" to w, "height" to h, "audio" to audio)
        } finally {
            r.release()
        }
    }

    private fun jpeg(bitmap: Bitmap, maxWidth: Int): ByteArray {
        val scaled = if (bitmap.width > maxWidth) {
            Bitmap.createScaledBitmap(bitmap, maxWidth, bitmap.height * maxWidth / bitmap.width, true)
        } else {
            bitmap
        }
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 88, out)
        if (scaled !== bitmap) scaled.recycle()
        bitmap.recycle()
        return out.toByteArray()
    }

    private fun frame(source: String, ms: Long, maxWidth: Int): ByteArray? {
        val r = open(source)
        try {
            val b = r.getFrameAtTime(ms * 1000, MediaMetadataRetriever.OPTION_CLOSEST) ?: return null
            return jpeg(b, maxWidth)
        } finally {
            r.release()
        }
    }

    private fun strip(source: String, count: Int, maxWidth: Int, fromMs: Long, toMs: Long): List<ByteArray> {
        val r = open(source)
        try {
            val out = ArrayList<ByteArray>()
            for (i in 0 until count) {
                val t = fromMs + (toMs - fromMs) * (2 * i + 1) / (2 * count)
                val b = r.getFrameAtTime(t * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: continue
                out.add(jpeg(b, maxWidth))
            }
            return out
        } finally {
            r.release()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        work.shutdown()
    }
}
