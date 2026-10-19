package org.simplerunning.simplerunning

import android.media.AudioManager
import android.media.ToneGenerator
import android.speech.tts.TextToSpeech
import java.util.Locale
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent

class MainActivity : FlutterActivity() {
    private var speech: TextToSpeech? = null
    private var tones: ToneGenerator? = null
    private var pendingPicker: MethodChannel.Result? = null
    private var ready = false
    private var speechLocale: Locale? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        speech = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ready = true
                usePhoneLanguage()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "simplerunning/coach").setMethodCallHandler { call, result ->
            when (call.method) {
                "pickBackup" -> {
                    if (pendingPicker != null) { result.error("busy", "A file chooser is already open", null) }
                    else {
                        pendingPicker = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream"))
                            }, 8042)
                        } catch (_: RuntimeException) { pendingPicker = null; result.error("picker", "Cannot open file chooser", null) }
                    }
                }
                "speak" -> {
                    val text = call.arguments as? String ?: ""
                    if (ready && usePhoneLanguage()) {
                        speech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "coach")
                    }
                    result.success(null)
                }
                "beep" -> {
                    try {
                        if (tones == null) tones = ToneGenerator(AudioManager.STREAM_MUSIC, 80)
                        val countdown = call.arguments == "countdown"
                        tones?.startTone(
                            if (countdown) ToneGenerator.TONE_PROP_BEEP else ToneGenerator.TONE_PROP_ACK,
                            if (countdown) 100 else 350
                        )
                    } catch (_: RuntimeException) { /* Audio must not interrupt a workout. */ }
                    result.success(null)
                }
                "stop" -> { speech?.stop(); tones?.stopTone(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun usePhoneLanguage(): Boolean {
        val locale = Locale.getDefault()
        if (speechLocale == locale) return true
        val result = speech?.setLanguage(locale) ?: TextToSpeech.LANG_NOT_SUPPORTED
        if (result < TextToSpeech.LANG_AVAILABLE) return false
        speechLocale = locale
        return true
    }

    @Deprecated("Activity result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 8042) return
        val result = pendingPicker ?: return
        pendingPicker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        Thread {
            try {
                val text = contentResolver.openInputStream(uri)?.use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    var total = 0
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > 20 * 1024 * 1024) throw java.io.IOException("Backup too large")
                        output.write(buffer, 0, count)
                    }
                    output.toString("UTF-8")
                } ?: throw java.io.IOException("Cannot read backup")
                runOnUiThread { result.success(text) }
            } catch (_: Exception) { runOnUiThread { result.error("read", "Cannot read backup", null) } }
        }.start()
    }

    override fun onDestroy() {
        speech?.stop()
        speech?.shutdown()
        tones?.release()
        tones = null
        super.onDestroy()
    }
}
