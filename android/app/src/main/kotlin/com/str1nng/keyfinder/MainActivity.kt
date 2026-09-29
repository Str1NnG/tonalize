package com.str1nng.keyfinder

import com.str1nng.keyfinder.audio.AudioEngine
import com.str1nng.keyfinder.audio.KeyConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val engine = AudioEngine()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "tonalize/control").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val mode = if (call.argument<String>("mode") == "tuner") AudioEngine.Mode.TUNER else AudioEngine.Mode.KEY
                    val sensitivity = call.argument<Int>("sensitivity") ?: 1
                    val harmonics = call.argument<Int>("harmonics") ?: 4
                    val peakThreshold = (call.argument<Double>("peakThreshold") ?: 0.01).toFloat()
                    val minTonalness = (call.argument<Double>("minTonalness") ?: 1.5).toFloat()
                    val bassEnabled = call.argument<Boolean>("bassEnabled") ?: true
                    val config = KeyConfig(harmonics, peakThreshold, minTonalness, bassEnabled)
                    try {
                        engine.start(mode, sensitivity, config)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", e.message, null)
                    }
                }
                "stop" -> {
                    engine.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "tonalize/chroma").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { engine.chromaSink = events }
            override fun onCancel(arguments: Any?) { engine.chromaSink = null }
        })
        EventChannel(messenger, "tonalize/pitch").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { engine.pitchSink = events }
            override fun onCancel(arguments: Any?) { engine.pitchSink = null }
        })

        MethodChannel(messenger, "tonalize/bench").setMethodCallHandler { call, result ->
            when (call.method) {
                "benchDir" -> {
                    val benchDir = context.getExternalFilesDir(null)?.resolve("tonalize_bench")
                        ?: context.filesDir.resolve("tonalize_bench")
                    if (!benchDir.exists()) benchDir.mkdirs()
                    result.success(benchDir.absolutePath)
                }
                "exportBench" -> {
                    try {
                        val benchDir = context.getExternalFilesDir(null)?.resolve("tonalize_bench")
                            ?: context.filesDir.resolve("tonalize_bench")
                        if (!benchDir.exists() || benchDir.listFiles().isNullOrEmpty()) {
                            result.error("EMPTY_BENCH", "Nenhuma sessão encontrada para exportar", null)
                            return@setMethodCallHandler
                        }
                        val timeStamp = java.text.SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.US).format(java.util.Date())
                        val zipFile = java.io.File(context.cacheDir, "tonalize_bench_$timeStamp.zip")
                        zipDirectory(benchDir, zipFile)
                        shareZipFile(zipFile, "Exportar bancada de testes")
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("EXPORT_ERROR", e.message, null)
                    }
                }
                "exportSession" -> {
                    try {
                        val sessionPath = call.argument<String>("sessionDir")
                        if (sessionPath == null) {
                            result.error("INVALID_ARGS", "sessionDir é obrigatório", null)
                            return@setMethodCallHandler
                        }
                        val sessionDir = java.io.File(sessionPath)
                        if (!sessionDir.exists()) {
                            result.error("NOT_FOUND", "Pasta de sessão não encontrada: $sessionPath", null)
                            return@setMethodCallHandler
                        }
                        val zipFile = java.io.File(context.cacheDir, "${sessionDir.name}.zip")
                        zipDirectory(sessionDir, zipFile)
                        shareZipFile(zipFile, "Exportar sessão: ${sessionDir.name}")
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("EXPORT_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun zipDirectory(sourceDir: java.io.File, zipFile: java.io.File) {
        if (zipFile.exists()) zipFile.delete()
        java.io.FileOutputStream(zipFile).use { fos ->
            java.util.zip.ZipOutputStream(fos).use { zos ->
                val rootPath = sourceDir.parentFile?.absolutePath ?: ""
                sourceDir.walkTopDown().forEach { file ->
                    if (file.isFile) {
                        val relativePath = file.absolutePath.removePrefix(rootPath).removePrefix(java.io.File.separator)
                        val entry = java.util.zip.ZipEntry(relativePath)
                        zos.putNextEntry(entry)
                        file.inputStream().use { it.copyTo(zos) }
                        zos.closeEntry()
                    }
                }
            }
        }
    }

    private fun shareZipFile(zipFile: java.io.File, title: String) {
        val uri = androidx.core.content.FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            zipFile
        )
        val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(android.content.Intent.EXTRA_STREAM, uri)
            addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(android.content.Intent.createChooser(intent, title))
    }

    override fun onPause() { super.onPause(); engine.stop() }   // libera o microfone ao sair de primeiro plano
    override fun onDestroy() { engine.stop(); super.onDestroy() }
}
