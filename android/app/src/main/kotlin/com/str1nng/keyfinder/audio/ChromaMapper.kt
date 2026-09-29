package com.str1nng.keyfinder.audio

import be.tarsos.dsp.util.fft.FFT
import be.tarsos.dsp.util.fft.HannWindow
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Bloco de áudio -> perfil de 12 notas. Mudanças em relação ao plano 1:
 *  - só picos locais do espectro entram (reduz ruído de fundo e bateria);
 *  - cada pico em f credita também as notas de f/2, f/3, f/4 com pesos 0,6^h (HPCP, Gómez 2006):
 *    um pico em A pode ser o 3º harmônico de um D, e parte da energia volta para o D;
 *  - blocos sem tonalidade (perfil quase plano) são descartados.
 * Com harmonics = 1, peakThreshold = 0 e minTonalness = 0 o comportamento é o do plano 1 (modo legado).
 */
class ChromaMapper(
    val sampleRate: Float = 44100f,
    val fftSize: Int = 8192,
    val fMin: Float = 130f,
    val fMax: Float = 2000f,
    val harmonics: Int = 4,          // 1 = sem crédito de subarmônicos
    val harmonicDecay: Float = 0.6f, // peso do h-ésimo subarmônico = harmonicDecay^h
    val peakThreshold: Float = 0.01f,// pico só conta se amplitude >= 1% da máxima do bloco (-40 dB); 0 = usa todas as raias
    val minTonalness: Float = 1.5f,  // max/média do perfil; abaixo disso o bloco é descartado; 0 = nunca descarta
) {
    private val fft = FFT(fftSize, HannWindow())
    private val amplitudes = FloatArray(fftSize / 2)
    private val kMin = ceil(fMin * fftSize / sampleRate).toInt().coerceAtLeast(1)
    private val kMax = floor(fMax * fftSize / sampleRate).toInt().coerceAtMost(fftSize / 2 - 2)
    private val weights = FloatArray(harmonics) { h -> harmonicDecay.pow(h) }
    private val targets: Array<IntArray> = Array(fftSize / 2) { k ->
        val hz = k * sampleRate / fftSize
        IntArray(harmonics) { h -> pitchClassOf(hz / (h + 1)) }
    }

    private fun pitchClassOf(hz: Float): Int {
        if (hz <= 0f) return -1
        val midi = 69.0 + 12.0 * (ln(hz / 440.0) / ln(2.0))
        return ((midi.roundToInt() % 12) + 12) % 12
    }

    data class FrameResult(
        val chroma: FloatArray?,       // normalizado com subarmônicos se passou no filtro, senão null
        val rawChroma: FloatArray?,    // normalizado com subarmônicos mesmo se tonalness < minTonalness
        val legacyChroma: FloatArray?, // normalizado sem subarmônicos (harmonics=1)
        val tonalness: Float           // razão max/média
    )

    /** Processa o bloco calculando perfil com subarmônicos, legado e tonalidade. */
    fun process(buffer: FloatArray): FrameResult? {
        require(buffer.size == fftSize) { "buffer deve ter $fftSize amostras" }
        val data = buffer.copyOf()
        fft.forwardTransform(data)
        fft.modulus(data, amplitudes)

        var maxAmp = 0f
        for (k in kMin..kMax) if (amplitudes[k] > maxAmp) maxAmp = amplitudes[k]
        if (maxAmp <= 0f) return null
        val threshold = maxAmp * peakThreshold

        val out = FloatArray(12)
        val legacy = FloatArray(12)
        for (k in kMin..kMax) {
            val a = amplitudes[k]
            if (a < threshold) continue
            if (peakThreshold > 0f && (a <= amplitudes[k - 1] || a < amplitudes[k + 1])) continue // só máximos locais
            val energy = a * a
            val t = targets[k]
            for (h in 0 until harmonics) {
                val pc = t[h]
                if (pc >= 0) out[pc] += weights[h] * energy
            }
            val pc0 = t[0]
            if (pc0 >= 0) legacy[pc0] += energy
        }
        val sum = out.sum()
        if (sum <= 0f) return null

        var maxPc = 0f
        for (v in out) if (v > maxPc) maxPc = v
        val meanPc = sum / 12f
        val tonalness = if (meanPc > 0f) maxPc / meanPc else 0f

        val normOut = FloatArray(12) { i -> out[i] / sum }
        val sumLegacy = legacy.sum()
        val normLegacy = if (sumLegacy > 0f) FloatArray(12) { i -> legacy[i] / sumLegacy } else null

        val accepted = if (minTonalness <= 0f || tonalness >= minTonalness) normOut else null

        return FrameResult(
            chroma = accepted,
            rawChroma = normOut,
            legacyChroma = normLegacy,
            tonalness = tonalness
        )
    }

    /** Perfil de 12 notas normalizado (soma 1) ou null se o bloco não tiver energia ou tonalidade. */
    fun chroma(buffer: FloatArray): FloatArray? = process(buffer)?.chroma
}

