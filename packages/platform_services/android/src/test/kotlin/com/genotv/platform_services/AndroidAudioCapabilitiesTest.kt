package com.genotv.platform_services

import android.media.AudioFormat
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class AndroidAudioCapabilitiesTest {
    @Test fun rejectedSinkNeverAdvertisesEncodedFormats() {
        val result = probeAndroidAudio(36, 48000) { _, _, encoding ->
            if (encoding == AudioFormat.ENCODING_PCM_FLOAT || encoding == AudioFormat.ENCODING_PCM_16BIT) 1024 else -2
        }
        assertTrue(result.formats.isEmpty())
        assertTrue(result.probes.any { it.name == "raw.ac3" && it.rate == 48000 && it.mask == AudioFormat.CHANNEL_OUT_STEREO })
        assertTrue(result.probes.any { it.name == "raw.dtsHd" && it.rate == 48000 && it.mask == AudioFormat.CHANNEL_OUT_7POINT1_SURROUND })
        assertTrue(result.probes.any { it.name == "raw.trueHd" && it.rate == 192000 && it.mask == AudioFormat.CHANNEL_OUT_7POINT1_SURROUND })
    }
    @Test fun trueHdRequires192kPcmBeforeEitherProbe() {
        val result = probeAndroidAudio(36, 48000) { rate, _, encoding ->
            if (rate == 192000 && (encoding == AudioFormat.ENCODING_PCM_FLOAT || encoding == AudioFormat.ENCODING_PCM_16BIT)) -2 else 1024
        }
        assertFalse(result.probes.any { it.name == "raw.trueHd" || it.name == "iec.hd" })
        assertFalse(result.formats.contains("trueHd"))
        assertEquals(setOf("ac3", "dts"), result.formats)
    }
    @Test fun iecCapabilityGatesActualMpvPathDespiteRawAcceptance() {
        val result = probeAndroidAudio(36, 48000) { _, _, encoding -> if (encoding == AudioFormat.ENCODING_IEC61937) -2 else 1024 }
        assertTrue(result.rawFormats.contains("ac3"))
        assertTrue(result.formats.isEmpty())
    }
    @Test fun iecHighRateStereoAndSurroundAreIndependent() {
        val result = probeAndroidAudio(36, 48000) { _, mask, encoding ->
            if (encoding == AudioFormat.ENCODING_IEC61937 && mask == AudioFormat.CHANNEL_OUT_7POINT1_SURROUND) -2 else 1024
        }
        assertEquals(setOf("ac3", "dts", "eac3"), result.formats)
        assertFalse(result.formats.contains("trueHd"))
    }
    @Test fun nativeRateIsRetainedAndIecRequiresApi24() {
        val result = probeAndroidAudio(23, 44100) { _, _, _ -> -2 }
        assertEquals(listOf(44100), result.rates)
        assertFalse(result.probes.any { it.name.startsWith("iec.") })
    }
}
