package com.str1nng.keyfinder.audio

import android.os.Handler
import android.os.Looper
import be.tarsos.dsp.AudioDispatcher
import be.tarsos.dsp.SilenceDetector
import be.tarsos.dsp.io.android.AudioDispatcherFactory
import be.tarsos.dsp.pitch.PitchProcessor
import io.flutter.plugin.common.EventChannel

class AudioEngine {
    enum class Mode { KEY, TUNER }

    @Volatile var chromaSink: EventChannel.EventSink? = null
    @Volatile var pitchSink: EventChannel.EventSink? = null

    private val main = Handler(Looper.getMainLooper())
    private var dispatcher: AudioDispatcher? = null

    /** sensitivity: 0 = baixa, 1 = média, 2 = alta (mais sensível = limiar mais baixo). */
    fun start(mode: Mode, sensitivity: Int) {
        stop()
        val d = when (mode) {
            Mode.KEY -> AudioDispatcherFactory.fromDefaultMicrophone(44100, 8192, 4096).apply {
                // breakProcessingQueueOnSilence = true: blocos abaixo do limiar não chegam ao ChromaProcessor
                addAudioProcessor(SilenceDetector(thresholdFor(sensitivity), true))
                addAudioProcessor(ChromaProcessor { chroma, spl ->
                    val payload = mapOf(
                        "chroma" to chroma.map { it.toDouble() },
                        "spl" to spl,
                    )
                    main.post { chromaSink?.success(payload) }   // EventSink só pode ser chamado na thread principal
                })
            }
            Mode.TUNER -> AudioDispatcherFactory.fromDefaultMicrophone(44100, 2048, 0).apply {
                addAudioProcessor(PitchProcessor(
                    PitchProcessor.PitchEstimationAlgorithm.YIN, 44100f, 2048
                ) { result, _ ->
                    if (result.pitch != -1f && result.probability > 0.9f) {
                        val payload = mapOf("hz" to result.pitch.toDouble(), "probability" to result.probability.toDouble())
                        main.post { pitchSink?.success(payload) }
                    }
                })
            }
        }
        dispatcher = d
        Thread(d, "Audio Dispatcher").start()
    }

    fun stop() {
        dispatcher?.let { if (!it.isStopped) it.stop() }
        dispatcher = null
    }

    /**
     * O SilenceDetector da TarsosDSP calcula 20*log10(sqrt(soma(x²)) / N); para N = 8192 isso fica
     * ~39 dB abaixo do dBFS convencional. Os valores abaixo são iniciais e devem ser calibrados
     * na etapa 1 da avaliação (o projeto prevê isso).
     */
    private fun thresholdFor(sensitivity: Int): Double = when (sensitivity) {
        0 -> -60.0   // baixa: ignora mais ruído de sala
        2 -> -80.0   // alta: capta sons mais fracos
        else -> -70.0
    }
}
