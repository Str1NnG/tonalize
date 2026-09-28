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
                    val config = KeyConfig(harmonics, peakThreshold, minTonalness)
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
    }

    override fun onPause() { super.onPause(); engine.stop() }   // libera o microfone ao sair de primeiro plano
    override fun onDestroy() { engine.stop(); super.onDestroy() }
}
