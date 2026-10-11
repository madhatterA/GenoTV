package com.genotv.platform_services

import android.media.AudioManager
import android.media.session.PlaybackState
import android.view.KeyEvent

internal val mediaSessionActions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
    PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SEEK_TO or
    PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS or
    PlaybackState.ACTION_FAST_FORWARD or PlaybackState.ACTION_REWIND or PlaybackState.ACTION_STOP

internal fun mediaKeyCommand(keyCode: Int): String? = when (keyCode) {
    KeyEvent.KEYCODE_MEDIA_PLAY -> "play"
    KeyEvent.KEYCODE_MEDIA_PAUSE -> "pause"
    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_HEADSETHOOK -> "togglePlay"
    KeyEvent.KEYCODE_MEDIA_NEXT, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> "skipForward"
    KeyEvent.KEYCODE_MEDIA_PREVIOUS, KeyEvent.KEYCODE_MEDIA_REWIND -> "skipBackward"
    KeyEvent.KEYCODE_MEDIA_STOP -> "stop"
    else -> null
}

// Kodi ignores transient loss and duck; only permanent loss pauses a pausable player.
internal fun audioFocusCommand(change: Int, playing: Boolean): String? =
    if (change == AudioManager.AUDIOFOCUS_LOSS && playing) "pause" else null
