package com.str1nng.keyfinder.audio

import be.tarsos.dsp.AudioEvent
import be.tarsos.dsp.AudioProcessor

class ChromaProcessor(
    private val mapper: ChromaMapper,
    private val onChroma: (chroma: FloatArray, dbSpl: Double) -> Unit
) : AudioProcessor {
    override fun process(audioEvent: AudioEvent): Boolean {
        mapper.chroma(audioEvent.floatBuffer)?.let { onChroma(it, audioEvent.getdBSPL()) }
        return true
    }
    override fun processingFinished() {}
}
