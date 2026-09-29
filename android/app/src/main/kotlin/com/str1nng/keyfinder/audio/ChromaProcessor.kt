package com.str1nng.keyfinder.audio

import be.tarsos.dsp.AudioEvent
import be.tarsos.dsp.AudioProcessor

class ChromaProcessor(
    private val mapper: ChromaMapper,
    private val bassTracker: BassTracker? = null,
    private val onFrame: (
        tAudioMs: Long,
        chroma: FloatArray?,
        rawChroma: FloatArray?,
        legacyChroma: FloatArray?,
        levelDb: Double,
        tonalness: Float,
        bassPc: Int,
        bassProb: Double,
        bassHz: Double,
        bassProbRaw: Double,
        bassPitched: Boolean
    ) -> Unit
) : AudioProcessor {
    override fun process(audioEvent: AudioEvent): Boolean {
        val tAudioMs = (audioEvent.timeStamp * 1000.0).toLong()
        val bassRes = bassTracker?.trackFull(audioEvent.floatBuffer, audioEvent.bufferSize - audioEvent.overlap)
        val frameRes = mapper.process(audioEvent.floatBuffer)

        val bassPc = bassRes?.pitchClass ?: -1
        val bassProb = bassRes?.probability?.toDouble() ?: 0.0
        val bassHz = bassRes?.hz?.toDouble() ?: 0.0
        val bassProbRaw = bassRes?.rawProbability?.toDouble() ?: 0.0
        val bassPitched = bassRes?.isPitched ?: false

        val levelDb = audioEvent.getdBSPL()
        val tonalness = frameRes?.tonalness ?: 0f

        onFrame(
            tAudioMs,
            frameRes?.chroma,
            frameRes?.rawChroma,
            frameRes?.legacyChroma,
            levelDb,
            tonalness,
            bassPc,
            bassProb,
            bassHz,
            bassProbRaw,
            bassPitched
        )
        return true
    }
    override fun processingFinished() {}
}

