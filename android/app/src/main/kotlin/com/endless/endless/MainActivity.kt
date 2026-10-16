package com.endless.endless

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// A FragmentActivity, so local_auth can show the fingerprint and face prompt.
class MainActivity : FlutterFragmentActivity() {
    private var ink: InkRecognition? = null
    private var speech: Speech? = null
    private var keyboard: Keyboard? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Handwriting recognition (lib/recognition/recognizer.dart).
        ink = InkRecognition(flutterEngine.dartExecutor.binaryMessenger)
        // The dictionary's "Hear it" (lib/spelling/speech.dart).
        speech = Speech(this, flutterEngine.dartExecutor.binaryMessenger)
        keyboard = Keyboard(this, flutterEngine.dartExecutor.binaryMessenger)
        // Opens a Word, PowerPoint or Excel file from the board in the app
        // the tablet uses for it, which may save back to it; Endless watches
        // the file and updates the card (lib/state/office_docs.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "endless/files").setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val mime = call.argument<String>("mime")
            if (path == null || mime == null) {
                result.success(false)
                return@setMethodCallHandler
            }
            try {
                val uri = FileProvider.getUriForFile(this, "$packageName.files", File(path))
                val view = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, mime)
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_ACTIVITY_NEW_TASK,
                    )
                }
                startActivity(view)
                result.success(true)
            } catch (e: ActivityNotFoundException) {
                result.success(false)
            } catch (e: IllegalArgumentException) {
                result.success(false)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ink?.dispose()
        ink = null
        speech?.dispose()
        speech = null
        keyboard?.dispose()
        keyboard = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

/// Shares files from the app's cache folder `open/` with the app that opens
/// them (to read and save), for as long as that app has them open.
class EndlessFileProvider : FileProvider()
