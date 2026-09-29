package com.str1nng.keyfinder.audio

import be.tarsos.dsp.pitch.Yin
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Nota do baixo de cada bloco: passa-baixas de 2ª ordem (Butterworth, 250 Hz) sobre uma cópia do sinal,
 * janela deslizante filtrada de [windowSize] amostras, YIN sobre a janela.
 * Não toca no buffer do dispatcher (o TarsosDSP reaproveita a sobreposição do buffer entre blocos;
 * filtrar nele corromperia o espectro do bloco seguinte).
 */
class BassTracker(
    private val sampleRate: Float = 44100f,
    private val windowSize: Int = 8192,
    cutoffHz: Float = 250f,
    private val minHz: Float = 35f,      // abaixo de Ré♯1 é ruído
    private val maxHz: Float = 200f,     // acima disso é voz ou guitarra, não baixo
    private val minProbability: Float = 0.85f,
) {
    data class Bass(val pitchClass: Int, val probability: Float, val hz: Float)

    private val yin = Yin(sampleRate, windowSize, 0.05)
    private val window = FloatArray(windowSize)
    private var filled = 0
    // Butterworth passa-baixas de 2ª ordem (RBJ cookbook), estado persistente entre blocos
    private val b0: Float
    private val b1: Float
    private val b2: Float
    private val a1: Float
    private val a2: Float
    private var x1 = 0f
    private var x2 = 0f
    private var y1 = 0f
    private var y2 = 0f

    init {
        val w0 = 2.0 * PI * cutoffHz / sampleRate
        val alpha = sin(w0) / (2.0 * sqrt(2.0) / 2.0)   // Q = 1/sqrt(2)
        val cosw0 = cos(w0)
        val a0 = 1.0 + alpha
        b0 = ((1.0 - cosw0) / 2.0 / a0).toFloat()
        b1 = ((1.0 - cosw0) / a0).toFloat()
        b2 = b0
        a1 = (-2.0 * cosw0 / a0).toFloat()
        a2 = ((1.0 - alpha) / a0).toFloat()
    }

    /** [buffer] é o bloco completo do dispatcher; [newSamples] é quantas amostras dele são novas (tamanho − sobreposição). */
    fun track(buffer: FloatArray, newSamples: Int): Bass? {
        val start = buffer.size - newSamples
        // desloca a janela filtrada e filtra só as amostras novas
        System.arraycopy(window, newSamples, window, 0, windowSize - newSamples)
        var w = windowSize - newSamples
        for (i in start until buffer.size) {
            val x0 = buffer[i]
            val y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
            window[w++] = y0
        }
        filled = minOf(windowSize, filled + newSamples)
        if (filled < windowSize) return null
        val r = yin.getPitch(window)
        if (!r.isPitched || r.pitch < minHz || r.pitch > maxHz || r.probability < minProbability) return null
        val midi = 69.0 + 12.0 * (ln(r.pitch / 440.0) / ln(2.0))
        return Bass(((midi.roundToInt() % 12) + 12) % 12, r.probability, r.pitch)
    }

    fun reset() {
        window.fill(0f)
        filled = 0
        x1 = 0f
        x2 = 0f
        y1 = 0f
        y2 = 0f
    }
}
