package com.endless.endless

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.Configuration
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// Whether the on-screen keyboard is held back because Android thinks a
/// physical keyboard is attached (lib/state/device_keyboard.dart), and the
/// settings that change it.
///
/// With a keyboard attached (a cover keyboard, Bluetooth, or Samsung's Multi
/// Control sharing a PC's keyboard) keyboards don't open on screen unless
/// "Show on-screen keyboard" is on; no app call gets round that.
class Keyboard(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "endless/keyboard")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "heldBack" -> result.success(heldBack())
                "openSettings" -> result.success(openSettings())
                else -> result.notImplemented()
            }
        }
    }

    private fun heldBack(): Boolean {
        val config = activity.resources.configuration
        val attached = config.keyboard != Configuration.KEYBOARD_NOKEYS &&
            config.hardKeyboardHidden == Configuration.HARDKEYBOARDHIDDEN_NO
        if (!attached) return false
        // "Show on-screen keyboard": readable on most devices; if not, assume it's off.
        val showAnyway = try {
            Settings.Secure.getInt(activity.contentResolver, "show_ime_with_hard_keyboard", 0) == 1
        } catch (e: Exception) {
            false
        }
        return !showAnyway
    }

    private fun openSettings(): Boolean {
        for (action in listOf(Settings.ACTION_HARD_KEYBOARD_SETTINGS, Settings.ACTION_INPUT_METHOD_SETTINGS)) {
            try {
                activity.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: ActivityNotFoundException) {
                continue
            }
        }
        return false
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
