package com.str1nng.keyfinder.audio

import be.tarsos.dsp.util.fft.FFT
import be.tarsos.dsp.util.fft.HannWindow
import kotlin.math.ln
import kotlin.math.roundToInt

/**
 * Converte um bloco de áudio (FFT_SIZE amostras, mono, 44.100 Hz) em um perfil de 12 notas
 * (chroma): a energia de cada raia da FFT entre F_MIN e F_MAX é somada na nota mais próxima,
 * ignorando a oitava. O resultado é normalizado para somar 1 (cada bloco pesa o mesmo,
 * o que aproxima a ponderação por duração usada nos perfis de Krumhansl-Kessler).
 * Sem dependência de Android: testável na JVM.
 */
class ChromaMapper(
    val sampleRate: Float = 44100f,
    val fftSize: Int = 8192,
    val fMin: Float = 130f,
    val fMax: Float = 2000f,
) {
    private val fft = FFT(fftSize, HannWindow())
    private val amplitudes = FloatArray(fftSize / 2)
    private val binToPitchClass = IntArray(fftSize / 2) { k ->
        val hz = k * sampleRate / fftSize
        if (hz < fMin || hz > fMax) -1
        else {
            val midi = 69.0 + 12.0 * (ln(hz / 440.0) / ln(2.0))
            ((midi.roundToInt() % 12) + 12) % 12
        }
    }

    /** Retorna o perfil de 12 notas normalizado (soma 1) ou null se o bloco não tiver energia. */
    fun chroma(buffer: FloatArray): FloatArray? {
        require(buffer.size == fftSize) { "buffer deve ter $fftSize amostras" }
        val data = buffer.copyOf()          // forwardTransform é in-place e aplica a janela de Hann
        fft.forwardTransform(data)
        fft.modulus(data, amplitudes)        // amplitudes[k] = magnitude da raia k
        val out = FloatArray(12)
        for (k in amplitudes.indices) {
            val pc = binToPitchClass[k]
            if (pc >= 0) out[pc] += amplitudes[k] * amplitudes[k]   // energia
        }
        val sum = out.sum()
        if (sum <= 0f) return null
        for (i in 0 until 12) out[i] /= sum
        return out
    }
}
