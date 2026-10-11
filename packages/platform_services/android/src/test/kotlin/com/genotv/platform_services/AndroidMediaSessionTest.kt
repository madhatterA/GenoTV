package com.genotv.platform_services

import android.media.AudioManager
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.view.KeyEvent
import io.flutter.plugin.common.EventChannel
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class AndroidMediaSessionTest {
    @Test fun fastForwardAndRewindCallbacksReachTheDartStream() {
        val plugin = PlatformServicesPlugin()
        val sink = Mockito.mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, sink)
        val field = PlatformServicesPlugin::class.java.getDeclaredField("mediaCallback")
        field.isAccessible = true
        val callback = field.get(plugin) as MediaSession.Callback
        callback.onFastForward()
        callback.onRewind()
        callback.onSeekTo(12500)
        Mockito.verify(sink).success(mapOf("event" to "mediaCommand", "command" to "skipForward"))
        Mockito.verify(sink).success(mapOf("event" to "mediaCommand", "command" to "skipBackward"))
        Mockito.verify(sink).success(mapOf("event" to "mediaCommand", "command" to "seekTo", "positionSeconds" to 12.5))
    }
    @Test fun frameworkFocusCallbackOnlyEmitsOnPermanentLoss() {
        val plugin = PlatformServicesPlugin()
        val sink = Mockito.mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, sink)
        val playing = PlatformServicesPlugin::class.java.getDeclaredField("mediaPlaying")
        playing.isAccessible = true
        playing.set(plugin, true)
        val field = PlatformServicesPlugin::class.java.getDeclaredField("audioFocusListener")
        field.isAccessible = true
        val listener = field.get(plugin) as AudioManager.OnAudioFocusChangeListener
        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK)
        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_GAIN)
        Mockito.verifyNoInteractions(sink)
        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS)
        Mockito.verify(sink).success(mapOf("event" to "mediaCommand", "command" to "pause"))
    }

    @Test fun supportedActionsIncludeEveryTransportCommand() {
        for (action in listOf(PlaybackState.ACTION_PLAY, PlaybackState.ACTION_PAUSE,
            PlaybackState.ACTION_PLAY_PAUSE, PlaybackState.ACTION_SEEK_TO,
            PlaybackState.ACTION_SKIP_TO_NEXT, PlaybackState.ACTION_SKIP_TO_PREVIOUS,
            PlaybackState.ACTION_FAST_FORWARD, PlaybackState.ACTION_REWIND, PlaybackState.ACTION_STOP)) {
            assertTrue(mediaSessionActions and action != 0L)
        }
    }
    @Test fun frameworkMediaKeysMapToTheExistingCommandVocabulary() {
        assertEquals("togglePlay", mediaKeyCommand(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
        assertEquals("skipForward", mediaKeyCommand(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD))
        assertEquals("skipBackward", mediaKeyCommand(KeyEvent.KEYCODE_MEDIA_REWIND))
        assertEquals("skipForward", mediaKeyCommand(KeyEvent.KEYCODE_MEDIA_NEXT))
        assertEquals("skipBackward", mediaKeyCommand(KeyEvent.KEYCODE_MEDIA_PREVIOUS))
        assertEquals("play", mediaKeyCommand(KeyEvent.KEYCODE_MEDIA_PLAY))
        assertEquals("pause", mediaKeyCommand(KeyEvent.KEYCODE_MEDIA_PAUSE))
        assertEquals("stop", mediaKeyCommand(KeyEvent.KEYCODE_MEDIA_STOP))
        assertEquals(null, mediaKeyCommand(KeyEvent.KEYCODE_DPAD_CENTER))
    }
    @Test fun kodiOnlyPausesPlayingMediaOnPermanentFocusLoss() {
        assertEquals("pause", audioFocusCommand(AudioManager.AUDIOFOCUS_LOSS, true))
        for (change in listOf(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK, AudioManager.AUDIOFOCUS_GAIN)) {
            assertEquals(null, audioFocusCommand(change, true))
        }
        assertEquals(null, audioFocusCommand(AudioManager.AUDIOFOCUS_LOSS, false))
    }
}
