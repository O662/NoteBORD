package com.endless.endless

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Files opened with Endless from another app (a board file from Gmail,
/// Drive, OneDrive or Files: "Open with" or "Share to"), copied into the
/// app's cache and handed to Dart, which imports them
/// (lib/transfer/incoming.dart).
class Incoming(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "endless/incoming")
    private val pending = mutableListOf<Map<String, String>>()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "take" -> {
                    result.success(pending.toList())
                    pending.clear()
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Takes the files [intent] brings, if any; true if it brought some.
    /// The intent is emptied, so turning the tablet doesn't bring them again.
    fun take(intent: Intent?, notify: Boolean): Boolean {
        if (intent == null) return false
        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(stream(intent))
            else -> emptyList()
        }
        if (uris.isEmpty()) return false
        intent.action = null
        intent.data = null
        for (uri in uris) {
            try {
                val name = nameOf(uri)
                val dir = File(context.cacheDir, "incoming").apply { mkdirs() }
                val file = File(dir, "${System.nanoTime()}-$name")
                context.contentResolver.openInputStream(uri)?.use { input ->
                    file.outputStream().use { input.copyTo(it) }
                } ?: continue
                pending.add(mapOf("name" to name, "path" to file.path))
            } catch (e: Exception) {
                // Not readable (permission gone, or not a file): skipped.
            }
        }
        if (notify && pending.isNotEmpty()) channel.invokeMethod("arrived", null)
        return pending.isNotEmpty()
    }

    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM)

    /// The file's name as the other app gives it, made safe as a file name.
    private fun nameOf(uri: Uri): String {
        var name: String? = null
        if (uri.scheme == "content") {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) name = c.getString(0)
            }
        }
        if (name == null) name = uri.lastPathSegment
        return (name ?: "shared.board").substringAfterLast('/').replace(Regex("[\\\\/:*?\"<>|]"), "-").take(120)
    }
}
