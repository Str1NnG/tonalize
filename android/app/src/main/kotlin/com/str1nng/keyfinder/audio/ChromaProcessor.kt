package com.str1nng.keyfinder.audio

import be.tarsos.dsp.AudioEvent
import be.tarsos.dsp.AudioProcessor

class ChromaProcessor(
    private val mapper: ChromaMapper,
    private val bassTracker: BassTracker? = null,
    private val onFrame: (chroma: FloatArray, dbSpl: Double, bassPc: Int, bassProb: Double) -> Unit
) : AudioProcessor {
    override fun process(audioEvent: AudioEvent): Boolean {
        val bass = bassTracker?.track(audioEvent.floatBuffer, audioEvent.bufferSize - audioEvent.overlap)
        mapper.chroma(audioEvent.floatBuffer)?.let { chroma ->
            val bassPc = bass?.pitchClass ?: -1
            val bassProb = bass?.probability?.toDouble() ?: 0.0
            onFrame(chroma, audioEvent.getdBSPL(), bassPc, bassProb)
        }
        return true
    }
    override fun processingFinished() {}
}
