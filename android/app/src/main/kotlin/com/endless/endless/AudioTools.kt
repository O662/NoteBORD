package com.endless.endless

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

/// Recording audio (lib/audio/platform_audio.dart): keeps the app going
/// while the screen is off or another app is in front, and finishes and
/// reads the recordings. Nothing here uses the network.
///
/// - `keepGoing {on, kind, title, text}` starts or stops [KeepGoingService]:
///   `record` while recording (the microphone keeps working in the
///   background), `transcribe` while a transcript is being made.
/// - `finish {from, to}` puts a recording's AAC frames (ADTS, which survive
///   the app being stopped mid-recording) into an .m4a file, so it can be
///   played and seeked exactly. Returns its length in ms.
/// - `decode {from, to}` writes the audio of [from] as 16 kHz mono 32-bit
///   floats (little-endian) for speech to text. Returns the sample count.
class AudioTools(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "endless/audio")
    private val work = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "keepGoing" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    if (on) {
                        val intent = Intent(context, KeepGoingService::class.java)
                            .putExtra("kind", call.argument<String>("kind") ?: "record")
                            .putExtra("title", call.argument<String>("title") ?: "Endless")
                            .putExtra("text", call.argument<String>("text") ?: "")
                        try {
                            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Not allowed from the background (Android 12+), or no
                            // microphone permission yet.
                            result.success(false)
                        }
                    } else {
                        context.stopService(Intent(context, KeepGoingService::class.java))
                        result.success(true)
                    }
                }
                "finish" -> run(result) { finish(call.argument<String>("from")!!, call.argument<String>("to")!!) }
                "decode" -> run(result) { decode(call.argument<String>("from")!!, call.argument<String>("to")!!) }
                else -> result.notImplemented()
            }
        }
    }

    private fun run(result: MethodChannel.Result, job: () -> Long) {
        work.execute {
            try {
                val value = job()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("audio", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun audioTrack(extractor: MediaExtractor): Int {
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) return i
        }
        throw IllegalArgumentException("No audio in this file")
    }

    private fun finish(from: String, to: String): Long {
        val extractor = MediaExtractor()
        extractor.setDataSource(from)
        val track = audioTrack(extractor)
        extractor.selectTrack(track)
        val part = File("$to.part")
        val muxer = MediaMuxer(part.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var last = 0L
        try {
            val out = muxer.addTrack(extractor.getTrackFormat(track))
            muxer.start()
            val buffer = ByteBuffer.allocate(256 * 1024)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                info.set(0, size, extractor.sampleTime, MediaCodec.BUFFER_FLAG_KEY_FRAME)
                last = extractor.sampleTime
                muxer.writeSampleData(out, buffer, info)
                extractor.advance()
            }
            muxer.stop()
        } finally {
            muxer.release()
            extractor.release()
        }
        if (!part.renameTo(File(to))) throw IllegalStateException("Couldn't save the recording")
        return last / 1000
    }

    private fun decode(from: String, to: String): Long {
        val extractor = MediaExtractor()
        extractor.setDataSource(from)
        val track = audioTrack(extractor)
        extractor.selectTrack(track)
        val format = extractor.getTrackFormat(track)
        val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(format, null, null, 0)
        codec.start()
        var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var floats = false
        val part = File("$to.part")
        val out = BufferedOutputStream(FileOutputStream(part), 1 shl 16)
        val resampler = Resampler()
        var written = 0L
        try {
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            while (true) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(10_000)
                    if (i >= 0) {
                        val buf = codec.getInputBuffer(i)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(i, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, 10_000)
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val f = codec.outputFormat
                    rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (f.containsKey(MediaFormat.KEY_PCM_ENCODING)) floats = f.getInteger(MediaFormat.KEY_PCM_ENCODING) == 4
                } else if (o >= 0) {
                    val buf = codec.getOutputBuffer(o)!!.order(ByteOrder.LITTLE_ENDIAN)
                    buf.position(info.offset)
                    buf.limit(info.offset + info.size)
                    val mono: FloatArray
                    if (floats) {
                        val fb = buf.asFloatBuffer()
                        val frames = fb.remaining() / channels
                        mono = FloatArray(frames) { f ->
                            var sum = 0f
                            for (c in 0 until channels) sum += fb.get(f * channels + c)
                            sum / channels
                        }
                    } else {
                        val shorts = buf.asShortBuffer()
                        val frames = shorts.remaining() / channels
                        mono = FloatArray(frames) { f ->
                            var sum = 0f
                            for (c in 0 until channels) sum += shorts.get(f * channels + c) / 32768f
                            sum / channels
                        }
                    }
                    written += resampler.write(mono, rate, out)
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally {
            out.close()
            codec.stop()
            codec.release()
            extractor.release()
        }
        if (!part.renameTo(File(to))) throw IllegalStateException("Couldn't read the recording")
        return written
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        work.shutdown()
    }
}

/// Linear resampling to 16 kHz, carried across buffers.
private class Resampler {
    private var pos = 0.0
    private var prev = 0f

    fun write(input: FloatArray, rate: Int, out: BufferedOutputStream): Long {
        if (input.isEmpty()) return 0
        val samples: FloatArray
        if (rate == 16000) {
            samples = input
        } else {
            val step = rate / 16000.0
            val list = ArrayList<Float>(((input.size - pos) / step).toInt() + 2)
            // pos is where the next output sample falls; -1 is `prev`.
            while (pos < input.size - 1) {
                val i = Math.floor(pos).toInt()
                val t = (pos - i).toFloat()
                val a = if (i < 0) prev else input[i]
                val b = input[i + 1]
                list.add(a + (b - a) * t)
                pos += step
            }
            pos -= input.size
            prev = input[input.size - 1]
            samples = list.toFloatArray()
        }
        val bytes = ByteBuffer.allocate(samples.size * 4).order(ByteOrder.LITTLE_ENDIAN)
        bytes.asFloatBuffer().put(samples)
        out.write(bytes.array())
        return samples.size.toLong()
    }
}

/// A foreground service with a notification: Android lets the microphone
/// keep recording, and the work keep running, while the screen is off or
/// another app is in front.
class KeepGoingService : Service() {
    private var wake: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val kind = intent?.getStringExtra("kind") ?: "record"
        val title = intent?.getStringExtra("title") ?: "Endless"
        val text = intent?.getStringExtra("text") ?: ""
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel("recording", "Recording, transcripts and sync", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "recording") else Notification.Builder(this)
        val notification = builder
            .setContentTitle(title)
            .setContentText(text)
            // Recording keeps the microphone (it says what's happening); syncing
            // shows the Endless mark.
            .setSmallIcon(if (kind == "record") android.R.drawable.ic_btn_speak_now else R.drawable.ic_notification)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        val type = when {
            Build.VERSION.SDK_INT < 29 -> 0
            kind == "record" -> ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            else -> ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
        if (Build.VERSION.SDK_INT >= 29) startForeground(7, notification, type) else startForeground(7, notification)
        if (wake == null) {
            wake = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "endless:keepgoing")
                .apply { acquire(4 * 60 * 60 * 1000L) }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wake?.let { if (it.isHeld) it.release() }
        wake = null
        super.onDestroy()
    }
}
