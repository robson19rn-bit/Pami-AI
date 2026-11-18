package pl.czytamsam.czytam_sam

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import org.vosk.LibVosk
import org.vosk.LogLevel
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executors
import java.util.zip.ZipInputStream

/**
 * Lokalne rozpoznawanie mowy (Vosk). Dźwięk z mikrofonu trafia wyłącznie do
 * rozpoznawania w pamięci – nic nie jest zapisywane ani wysyłane.
 */
class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var model: Model? = null
    private var speech: SpeechService? = null
    private var recognizer: Recognizer? = null
    private var pending: MethodChannel.Result? = null
    private var bestText: String = ""
    private var bestWords: JSONArray = JSONArray()
    private var heardSomething = false

    private val modelDir: File get() = File(filesDir, "vosk-model")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "czytamsam/asr")
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun isInstalled(): Boolean =
        File(modelDir, "am/final.mdl").isFile && File(modelDir, "conf").isDirectory

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "modelInstalled" -> result.success(isInstalled())
            "installModel" -> {
                val zip = call.argument<String>("zipPath")
                if (zip == null) {
                    result.success(mapOf("ok" to false, "message" to "Brak pliku."))
                    return
                }
                executor.execute {
                    val msg = try {
                        installFromZip(File(zip))
                    } catch (e: Exception) {
                        "Błąd rozpakowania: ${e.message}"
                    }
                    main.post { result.success(mapOf("ok" to (msg == null), "message" to msg)) }
                }
            }
            "removeModel" -> {
                releaseModel()
                modelDir.deleteRecursively()
                result.success(true)
            }
            "listen" -> {
                if (pending != null) {
                    result.success(mapOf("status" to "error", "message" to "Nasłuch już trwa."))
                    return
                }
                if (!isInstalled()) {
                    result.success(mapOf("status" to "noModel"))
                    return
                }
                val grammar = call.argument<List<String>>("grammar") ?: emptyList()
                val maxMs = call.argument<Int>("maxMs") ?: 6000
                pending = result
                bestText = ""
                bestWords = JSONArray()
                heardSomething = false
                executor.execute { startListening(grammar, maxMs) }
            }
            "cancel" -> {
                speech?.cancel()
                finish("noSpeech", null)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun installFromZip(zip: File): String? {
        releaseModel()
        val tmp = File(filesDir, "vosk-tmp")
        tmp.deleteRecursively()
        tmp.mkdirs()
        val base = tmp.canonicalPath + File.separator
        ZipInputStream(FileInputStream(zip)).use { zis ->
            while (true) {
                val e = zis.nextEntry ?: break
                val out = File(tmp, e.name)
                if (!out.canonicalPath.startsWith(base)) return "Nieprawidłowy plik archiwum."
                if (e.isDirectory) {
                    out.mkdirs()
                } else {
                    out.parentFile?.mkdirs()
                    out.outputStream().use { zis.copyTo(it) }
                }
            }
        }
        val root = tmp.walkTopDown().maxDepth(3).firstOrNull { File(it, "am/final.mdl").isFile }
            ?: return "To nie jest model Vosk (brak am/final.mdl)."
        modelDir.deleteRecursively()
        if (!root.renameTo(modelDir)) {
            root.copyRecursively(modelDir, overwrite = true)
        }
        tmp.deleteRecursively()
        return if (isInstalled()) null else "Model nie został poprawnie zainstalowany."
    }

    private fun releaseModel() {
        speech?.shutdown()
        speech = null
        recognizer?.close()
        recognizer = null
        model?.close()
        model = null
    }

    private fun startListening(grammar: List<String>, maxMs: Int) {
        try {
            LibVosk.setLogLevel(LogLevel.WARNINGS)
            val m = model ?: Model(modelDir.absolutePath).also { model = it }
            val words = JSONArray()
            grammar.forEach { words.put(it) }
            val rec = Recognizer(m, 16000.0f, words.toString())
            rec.setWords(true)
            recognizer = rec
            val svc = SpeechService(rec, 16000.0f)
            speech = svc
            val listener = object : RecognitionListener {
                override fun onPartialResult(hypothesis: String?) {
                    val p = hypothesis?.let { JSONObject(it).optString("partial", "") } ?: ""
                    if (p.isNotBlank()) heardSomething = true
                }

                override fun onResult(hypothesis: String?) {
                    if (take(hypothesis)) {
                        svc.stop()
                    }
                }

                override fun onFinalResult(hypothesis: String?) {
                    take(hypothesis)
                    finish(if (bestText.isBlank() && !heardSomething) "noSpeech" else "ok", null)
                }

                override fun onError(exception: Exception?) {
                    finish("error", exception?.message)
                }

                override fun onTimeout() {
                    take(rec.finalResult)
                    finish(if (bestText.isBlank() && !heardSomething) "noSpeech" else "ok", null)
                }
            }
            main.post { svc.startListening(listener, maxMs) }
        } catch (e: Exception) {
            main.post { finish("error", e.message) }
        }
    }

    /** Zapamiętuje niepusty wynik; zwraca true, gdy coś rozpoznano. */
    private fun take(hypothesis: String?): Boolean {
        if (hypothesis == null) return false
        val o = JSONObject(hypothesis)
        val text = o.optString("text", "").trim()
        if (text.isEmpty()) return false
        heardSomething = true
        bestText = text
        bestWords = o.optJSONArray("result") ?: JSONArray()
        return true
    }

    private fun finish(status: String, message: String?) {
        val r = pending ?: return
        pending = null
        val list = ArrayList<Map<String, Any>>()
        for (i in 0 until bestWords.length()) {
            val w = bestWords.getJSONObject(i)
            list.add(mapOf("word" to w.optString("word"), "conf" to w.optDouble("conf", 0.0)))
        }
        val text = if (bestText.isBlank() && heardSomething) "[unk]" else bestText
        speech?.shutdown()
        speech = null
        recognizer?.close()
        recognizer = null
        r.success(mapOf("status" to status, "text" to text, "words" to list, "message" to (message ?: "")))
    }

    override fun onDestroy() {
        releaseModel()
        executor.shutdown()
        super.onDestroy()
    }
}
