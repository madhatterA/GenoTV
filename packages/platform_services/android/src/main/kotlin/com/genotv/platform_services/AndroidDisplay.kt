package com.genotv.platform_services

import android.view.Display

/** Kodi offers the mode list even when the panel has only its current mode. */
internal fun hasDisplayModes(apiLevel: Int, modeCount: Int): Boolean = apiLevel >= 23 && modeCount > 0

/** One entry of Display.getSupportedModes(). Kodi AndroidUtils.cpp fetchDisplayModes. */
internal data class DisplayModeInfo(val id: Int, val physicalWidth: Int, val physicalHeight: Int, val refreshHz: Double) {
    // Kodi 4.3 step 1: width and height are swapped when the panel is portrait.
    val width: Int get() = if (physicalHeight > physicalWidth) physicalHeight else physicalWidth
    val height: Int get() = if (physicalHeight > physicalWidth) physicalWidth else physicalHeight
}

/**
 * Kodi 4.3 step 2: only a mode that is enumerated and differs from the current one
 * (same width, height and exact refresh, FLT_EPSILON) is ever requested.
 */
internal fun findDisplayMode(modes: List<DisplayModeInfo>, width: Int, height: Int, refreshHz: Double): DisplayModeInfo? =
    modes.firstOrNull { it.id >= 1 && it.width == width && it.height == height && kotlin.math.abs(it.refreshHz - refreshHz) < 1.1920928955078125e-7 }

/** Kodi 4.3 step 3 and androidtv 4.3: wait for onDisplayChanged (max 5 s); a TV waits at least 2 s. */
internal const val DISPLAY_CHANGE_TIMEOUT_MS = 5000L
internal const val TV_MODE_CHANGE_MIN_MS = 2000L

internal fun displayChangeWaitMs(isTelevision: Boolean, elapsedMs: Long): Long =
    if (isTelevision) maxOf(0L, TV_MODE_CHANGE_MIN_MS - elapsedMs) else 0L

/** Kodi 4.7 GetDisplayHDRCapabilities: named Display.HdrCapabilities constants, never raw numbers. */
internal fun hdrFormatNames(types: IntArray): List<String> = types.toList().mapNotNull { type: Int ->
    when (type) {
        Display.HdrCapabilities.HDR_TYPE_HDR10 -> "hdr10"
        Display.HdrCapabilities.HDR_TYPE_HLG -> "hlg"
        Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> "dolbyvision"
        Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS -> "hdr10plus"
        else -> null
    }
}
