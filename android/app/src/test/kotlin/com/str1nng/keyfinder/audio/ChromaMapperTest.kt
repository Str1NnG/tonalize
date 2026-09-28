package com.str1nng.keyfinder.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

class ChromaMapperTest {
    private val mapper = ChromaMapper()

    private fun tone(vararg hz: Double): FloatArray = FloatArray(8192) { n ->
        hz.sumOf { f -> sin(2 * PI * f * n / 44100.0) }.toFloat() / hz.size
    }

    @Test fun `la 440 Hz cai na nota A`() {
        val c = mapper.chroma(tone(440.0))!!
        assertEquals(9, c.indices.maxByOrNull { c[it] })
    }

    @Test fun `acorde de Do maior acende C, E e G`() {
        val c = mapper.chroma(tone(261.63, 329.63, 392.0))!!
        val top3 = c.indices.sortedByDescending { c[it] }.take(3).toSet()
        assertEquals(setOf(0, 4, 7), top3)
    }

    @Test fun `perfil e normalizado`() {
        val c = mapper.chroma(tone(440.0))!!
        assertTrue(kotlin.math.abs(c.sum() - 1f) < 1e-4f)
    }

    @Test fun `silencio retorna null`() {
        assertNull(mapper.chroma(FloatArray(8192)))
    }

    @Test fun `acorde de Re maior acende D, Fsharp e A`() {
        val c = mapper.chroma(tone(293.66, 369.99, 440.0))!!
        assertEquals(setOf(2, 6, 9), c.indices.sortedByDescending { c[it] }.take(3).toSet())
    }

    @Test fun `la puro credita o D como subarmonico`() {           // 440/3 = 146,7 Hz = D3
        val c = mapper.chroma(tone(440.0))!!
        assertEquals(9, c.indices.maxByOrNull { c[it] })
        assertTrue(c[2] > 0f)
    }

    @Test fun `modo legado nao credita subarmonicos`() {
        val legacy = ChromaMapper(harmonics = 1, peakThreshold = 0f, minTonalness = 0f)
        val c = legacy.chroma(tone(440.0))!!
        assertEquals(0f, c[2], 1e-6f)
    }
}
