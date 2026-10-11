package com.genotv.platform_services

import android.media.AudioFormat

internal data class AudioTrackProbe(val name: String, val rate: Int, val mask: Int, val encoding: Int, val buffer: Int) {
    val accepted: Boolean get() = buffer > 0
    fun diagnostic() = "rate=$rate mask=$mask encoding=$encoding minBuffer=$buffer supported=$accepted"
}

internal data class AndroidAudioCapabilities(
    val rates: List<Int>, val rawFormats: Set<String>, val formats: Set<String>,
    val probes: List<AudioTrackProbe>, val pcmFloat: Boolean,
) {
    fun diagnostics(): Map<String, String> = mapOf(
        "os" to "android", "audioProbe.method" to "AudioTrack.getMinBufferSize",
        "audioProbe.packing" to "IEC61937 (mpv audiotrack)",
        "audioProbe.rawFormats" to rawFormats.sorted().joinToString(","),
        "audioProbe.formats" to formats.sorted().joinToString(","),
        "audioProbe.sampleRates" to rates.joinToString(","),
        "audioProbe.pcmChannels" to "8 (Kodi KnownChannels; retry at open)",
    ) + probes.associate { "audioProbe.${it.name}" to it.diagnostic() }
}

// Kodi Android/AndroidTV1.4/1.5.8: trial exactly these rates, masks and encodings.
// mpv's AudioTrack AO packs IEC, so RAW findings are reported separately, never
// mistaken for a working IEC route. No physical HDMI topology is inferred.
internal fun probeAndroidAudio(api: Int, nativeRate: Int, minBuffer: (Int, Int, Int) -> Int): AndroidAudioCapabilities {
    val probes = mutableListOf<AudioTrackProbe>()
    fun check(name: String, rate: Int, mask: Int, encoding: Int): Boolean {
        val result = AudioTrackProbe(name, rate, mask, encoding, minBuffer(rate, mask, encoding))
        probes.add(result)
        return result.accepted
    }
    val stereo = AudioFormat.CHANNEL_OUT_STEREO
    val surround = AudioFormat.CHANNEL_OUT_7POINT1_SURROUND
    val float = check("pcm.float", nativeRate, stereo, AudioFormat.ENCODING_PCM_FLOAT)
    val pcm = if (float) AudioFormat.ENCODING_PCM_FLOAT else AudioFormat.ENCODING_PCM_16BIT
    val rates = (listOf(nativeRate) + listOf(32000, 44100, 48000, 88200, 96000, 176400, 192000).filter {
        check("pcm.$it", it, stereo, pcm)
    }).distinct().sorted()
    val raw = setOfNotNull(
        "ac3".takeIf { check("raw.ac3", 48000, stereo, AudioFormat.ENCODING_AC3) },
        "eac3".takeIf { check("raw.eac3", 48000, stereo, AudioFormat.ENCODING_E_AC3) },
        "dts".takeIf { api >= 23 && check("raw.dts", 48000, stereo, AudioFormat.ENCODING_DTS) },
        "dtsHd".takeIf { api >= 23 && check("raw.dtsHd", 48000, surround, AudioFormat.ENCODING_DTS_HD) },
        "trueHd".takeIf { api >= 23 && 192000 in rates && check("raw.trueHd", 192000, surround, AudioFormat.ENCODING_DOLBY_TRUEHD) },
    )
    val iec = api >= 24 && check("iec.core", 48000, stereo, AudioFormat.ENCODING_IEC61937)
    val high = iec && 192000 in rates && check("iec.high", 192000, stereo, AudioFormat.ENCODING_IEC61937)
    val hd = iec && 192000 in rates && check("iec.hd", 192000, surround, AudioFormat.ENCODING_IEC61937)
    val formats = setOfNotNull("ac3".takeIf { iec }, "dts".takeIf { iec },
        "eac3".takeIf { high }, "dtsHd".takeIf { hd }, "trueHd".takeIf { hd })
    return AndroidAudioCapabilities(rates, raw, formats, probes.toList(), float)
}
