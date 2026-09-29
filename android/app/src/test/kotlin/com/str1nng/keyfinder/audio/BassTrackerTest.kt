package com.str1nng.keyfinder.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin
import kotlin.random.Random

class BassTrackerTest {
    @Test
    fun `senoide de 55 Hz com 880 Hz detecta pitchClass 9 com probabilidade alta`() {
        val tracker = BassTracker()
        val bufferSize = 8192
        val newSamples = 4096

        var offset = 0
        var result: BassTracker.Bass? = null

        for (b in 0 until 4) {
            val block = FloatArray(bufferSize) { i ->
                val n = offset + i
                (0.3f * sin(2.0 * PI * 55.0 * n / 44100.0) +
                 1.0f * sin(2.0 * PI * 880.0 * n / 44100.0)).toFloat()
            }
            result = tracker.track(block, newSamples)
            offset += newSamples
        }

        assertNotNull("Deveria detectar o baixo de 55 Hz", result)
        assertEquals(9, result!!.pitchClass) // Lá (A)
        assertTrue(result.probability >= 0.85f)
        assertTrue(result.hz in 50f..60f)
    }

    @Test
    fun `ruido branco retorna null`() {
        val tracker = BassTracker()
        val random = Random(42)
        var result: BassTracker.Bass? = null
        for (b in 0 until 4) {
            val block = FloatArray(8192) { random.nextFloat() * 2f - 1f }
            result = tracker.track(block, 4096)
        }
        assertNull("Ruído branco não deve ser detectado como nota", result)
    }

    @Test
    fun `senoide de 330 Hz sozinha retorna null por estar fora da faixa`() {
        val tracker = BassTracker()
        var offset = 0
        var result: BassTracker.Bass? = null
        for (b in 0 until 4) {
            val block = FloatArray(8192) { i ->
                val n = offset + i
                sin(2.0 * PI * 330.0 * n / 44100.0).toFloat()
            }
            result = tracker.track(block, 4096)
            offset += 4096
        }
        assertNull("330 Hz (> 200 Hz) deve retornar null", result)
    }
}
