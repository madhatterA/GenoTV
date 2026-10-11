package com.genotv.platform_services

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class AndroidDisplayTest {
    @Test fun oneDisplayModeStillOffersKodiSettings() {
        assertEquals(true, hasDisplayModes(23, 1))
        assertEquals(true, hasDisplayModes(36, 2))
        assertEquals(false, hasDisplayModes(22, 1))
        assertEquals(false, hasDisplayModes(36, 0))
    }

    // Display.HdrCapabilities: DOLBY_VISION=1, HDR10=2, HLG=3, HDR10_PLUS=4 (Android SDK constants).
    @Test fun hdrTypesUseTheAndroidConstants() {
        assertEquals(listOf("dolbyvision", "hdr10", "hlg", "hdr10plus"), hdrFormatNames(intArrayOf(1, 2, 3, 4)))
        assertEquals(emptyList(), hdrFormatNames(intArrayOf()))
        assertEquals(emptyList(), hdrFormatNames(intArrayOf(5, -1)))
    }

    @Test fun portraitPanelsReportLandscapeSize() {
        val mode = DisplayModeInfo(1, 1080, 2424, 60.0)
        assertEquals(2424, mode.width)
        assertEquals(1080, mode.height)
        assertEquals(3840, DisplayModeInfo(1, 3840, 2160, 60.0).width)
    }

    @Test fun onlyEnumeratedModesAreRequested() {
        val modes = listOf(DisplayModeInfo(1, 3840, 2160, 60.0), DisplayModeInfo(2, 3840, 2160, 23.976), DisplayModeInfo(3, 1920, 1080, 24.0))
        assertEquals(2, findDisplayMode(modes, 3840, 2160, 23.976)?.id)
        assertEquals(3, findDisplayMode(modes, 1920, 1080, 24.0)?.id)
        assertNull(findDisplayMode(modes, 3840, 2160, 24.0))
        assertNull(findDisplayMode(modes, 3840, 2160, 60.001))
        assertNull(findDisplayMode(listOf(DisplayModeInfo(0, 100, 100, 60.0)), 100, 100, 60.0))
    }

    @Test fun televisionWaitsAtLeastTwoSecondsForTheHdmiLink() {
        assertEquals(2000L, displayChangeWaitMs(true, 0))
        assertEquals(500L, displayChangeWaitMs(true, 1500))
        assertEquals(0L, displayChangeWaitMs(true, 4000))
        assertEquals(0L, displayChangeWaitMs(false, 0))
    }
}
