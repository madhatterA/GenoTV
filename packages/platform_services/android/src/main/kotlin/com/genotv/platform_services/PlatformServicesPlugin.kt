package com.genotv.platform_services

import android.app.Activity
import android.app.UiModeManager
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.Manifest
import android.content.pm.ApplicationInfo
import android.graphics.BitmapFactory
import android.media.AudioFocusRequest
import android.media.session.MediaController
import android.view.KeyEvent
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaMetadata
import android.media.MediaMetadataRetriever
import android.media.MediaExtractor
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.graphics.drawable.Icon
import android.hardware.display.DisplayManager
import android.os.SystemClock
import android.view.Display
import android.view.WindowManager
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel

class PlatformServicesPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {
    // The MethodChannel that will the communication between Flutter and native Android
    //
    // This local reference serves to register the plugin with the Flutter Engine and unregister it
    // when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var appContext: Context
    private var activity: Activity? = null
    private var previousDisplayModeId: Int? = null
    private var isTelevision = false
    private var eventSink: EventChannel.EventSink? = null
    @Volatile private var audioCapabilities: AndroidAudioCapabilities? = null
    private var audioDeviceCallback: android.media.AudioDeviceCallback? = null
    private var mediaSession: MediaSession? = null
    private var mediaReceiver: BroadcastReceiver? = null
    private var mediaNotificationManager: NotificationManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var hasAudioFocus = false
    private var mediaPlaying = false
    private var notificationPermissionRequested = false
    private var proofAudioFocusRequest: AudioFocusRequest? = null
    private val proofAudioFocusListener = AudioManager.OnAudioFocusChangeListener { }
    private var lastAudioFocusChange = 0
    private var audioFocusChangeCount = 0
    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { change ->
        lastAudioFocusChange = change
        audioFocusChangeCount += 1
        if (change == AudioManager.AUDIOFOCUS_LOSS) hasAudioFocus = false
        audioFocusCommand(change, mediaPlaying)?.let { emitMediaCommand(it) }
    }
    private val capabilityProbeExecutor: ExecutorService = Executors.newSingleThreadExecutor {
        Thread(it, "platform-capability-probe")
    }
    private lateinit var mainHandler: Handler

    private companion object {
        const val mediaChannelId = "platform_services_media"
        const val mediaNotificationId = 0x505
        const val mediaCommandAction = "com.genotv.platform_services.MEDIA_COMMAND"
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        mainHandler = Handler(Looper.getMainLooper())
        appContext = flutterPluginBinding.applicationContext
        // decisions.md Android TV detection ruling: detect once, at the platform boundary.
        val uiMode = appContext.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        isTelevision = uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "platform_services")
        channel.setMethodCallHandler(this)
        events = EventChannel(flutterPluginBinding.binaryMessenger, "platform_services/events")
        events.setStreamHandler(this)
        mediaNotificationManager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        mediaSession = MediaSession(appContext, "platform_services").apply {
            setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
            setCallback(mediaCallback)
        }
        mediaReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.getStringExtra("command")) {
                    "play", "pause", "togglePlay", "skipForward", "skipBackward", "stop" ->
                        emitMediaCommand(intent.getStringExtra("command")!!)
                }
            }
        }
        val filter = IntentFilter(mediaCommandAction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(mediaReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            appContext.registerReceiver(mediaReceiver, filter)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val manager = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            audioDeviceCallback = object : android.media.AudioDeviceCallback() {
                override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) = emitRouteChanged()
                override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) = emitRouteChanged()
            }
            manager?.registerAudioDeviceCallback(audioDeviceCallback, null)
        }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "capabilities.version" -> result.success(mapOf("os" to "Android ${android.os.Build.VERSION.RELEASE}", "plugin" to "0.0.1"))
            "capabilities.probe" -> capabilityProbeExecutor.execute {
                val report = capabilityProbe()
                mainHandler.post { result.success(report) }
            }
            "audio.devices" -> result.success(audioDevices())
            "display.modes" -> result.success(displayModes())
            "display.apply" -> applyDisplayMode(call.arguments, result)
            "display.restore" -> restoreDisplayMode(result)
            "lifecycle.keepAwake" -> result.success(setKeepAwake(true))
            "lifecycle.releaseKeepAwake" -> result.success(setKeepAwake(false))
            "audio.negotiate" -> result.success(negotiateAudio(call.arguments))
            "media.probe" -> result.success(probeMedia(call.arguments))
            "lifecycle.mediaSession.update" -> result.success(updateMediaSession(call.arguments))
            "lifecycle.mediaSession.clear" -> result.success(clearMediaSession())
            "lifecycle.mediaSession.proof.seekTo", "lifecycle.mediaSession.proof.audioFocus",
            "lifecycle.mediaSession.proof.snapshot" -> result.success(mediaSessionProof(call))
            else -> result.error("platform.unsupported", "platform.unsupported: ${call.method}", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val manager = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            audioDeviceCallback?.let { manager?.unregisterAudioDeviceCallback(it) }
        }
        clearMediaSession()
        mediaReceiver?.let {
            runCatching { appContext.unregisterReceiver(it) }
        }
        mediaReceiver = null
        mediaSession?.release()
        mediaSession = null
        mediaNotificationManager = null
        audioDeviceCallback = null
        eventSink = null
        capabilityProbeExecutor.shutdownNow()
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emitRouteChanged() {
        audioCapabilities = null
        capabilityProbeExecutor.execute {
            audioSnapshot()
            mainHandler.post { eventSink?.success(mapOf("event" to "audioRouteChanged")) }
        }
    }

    @Synchronized private fun audioSnapshot(): AndroidAudioCapabilities {
        return audioCapabilities ?: probeAndroidAudio(
            Build.VERSION.SDK_INT, AudioTrack.getNativeOutputSampleRate(AudioManager.STREAM_MUSIC),
            AudioTrack::getMinBufferSize,
        ).also { audioCapabilities = it }
    }

    private fun unsupported(method: String) = mapOf("supported" to false, "reason" to "platform.unsupported: $method")

    private val mediaCallback = object : MediaSession.Callback() {
        override fun onPlay() = emitMediaCommand("play")
        override fun onPause() = emitMediaCommand("pause")
        override fun onStop() = emitMediaCommand("stop")
        override fun onSkipToNext() = emitMediaCommand("skipForward")
        override fun onSkipToPrevious() = emitMediaCommand("skipBackward")
        override fun onFastForward() = emitMediaCommand("skipForward")
        override fun onRewind() = emitMediaCommand("skipBackward")
        override fun onMediaButtonEvent(intent: Intent): Boolean {
            @Suppress("DEPRECATION")
            val key = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT)
                ?: return super.onMediaButtonEvent(intent)
            val command = mediaKeyCommand(key.keyCode) ?: return super.onMediaButtonEvent(intent)
            if (key.action == KeyEvent.ACTION_DOWN && key.repeatCount == 0) emitMediaCommand(command)
            return true
        }
        override fun onSeekTo(pos: Long) {
            emitMediaCommand("seekTo", pos / 1000.0)
        }
    }

    private fun emitMediaCommand(command: String, positionSeconds: Double? = null) {
        val payload = mutableMapOf<String, Any>("event" to "mediaCommand", "command" to command)
        if (positionSeconds != null) payload["positionSeconds"] = positionSeconds
        eventSink?.success(payload)
    }

    private fun updateMediaSession(arguments: Any?): Map<String, Any> {
        val values = arguments as? Map<*, *> ?: return unsupported("lifecycle.mediaSession.update")
        val title = values["title"] as? String ?: return unsupported("lifecycle.mediaSession.update")
        val subtitle = values["subtitle"] as? String
        val playing = values["playing"] as? Boolean ?: false
        val positionMs = ((values["positionSeconds"] as? Number)?.toDouble()?.times(1000.0))?.toLong() ?: 0L
        val durationMs = ((values["durationSeconds"] as? Number)?.toDouble()?.times(1000.0))?.toLong() ?: 0L
        val session = mediaSession ?: return unsupported("lifecycle.mediaSession.update")
        val artworkBytes = values["artworkBytes"] as? ByteArray
        val artwork = artworkBytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        val artworkUri = values["artworkUri"] as? String
        val metadata = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE, title)
            .apply {
                if (artwork != null) putBitmap(MediaMetadata.METADATA_KEY_ART, artwork)
                if (artworkUri != null) putString(MediaMetadata.METADATA_KEY_ART_URI, artworkUri)
            }
            .apply { if (subtitle != null) putString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE, subtitle) }
            .apply { if (durationMs > 0) putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs) }
            .build()
        val actions = mediaSessionActions
        val state = PlaybackState.Builder()
            .setActions(actions)
            .setState(if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED, positionMs, if (playing) 1f else 0f)
            .build()
        if (playing && !mediaPlaying) acquireAudioFocus()
        if (!playing && mediaPlaying) releaseAudioFocus()
        mediaPlaying = playing
        session.setMetadata(metadata)
        session.setPlaybackState(state)
        session.isActive = true
        requestNotificationPermission()
        val notification = postMediaNotification(title, subtitle, playing, session)
        return mapOf("supported" to true, "notification" to notification)
    }

    private fun clearMediaSession(): Map<String, Any> {
        mediaPlaying = false
        releaseAudioFocus()
        releaseProofAudioFocus()
        mediaSession?.isActive = false
        mediaSession?.setMetadata(null)
        mediaSession?.setPlaybackState(null)
        mediaNotificationManager?.cancel(mediaNotificationId)
        return mapOf("supported" to true, "cleared" to true)
    }

    private fun postMediaNotification(title: String, subtitle: String?, playing: Boolean, session: MediaSession): Boolean {
        val manager = mediaNotificationManager ?: return false
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(mediaChannelId, "Playback", NotificationManager.IMPORTANCE_LOW))
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(appContext, mediaChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(appContext)
        }
        builder.setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(playing)
            .setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1, 2))
            .addAction(mediaAction("Previous", "skipBackward", android.R.drawable.ic_media_previous, 1))
            .addAction(mediaAction(if (playing) "Pause" else "Play", if (playing) "pause" else "play", if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play, 2))
            .addAction(mediaAction("Next", "skipForward", android.R.drawable.ic_media_next, 3))
        session.controller.metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART)?.let { builder.setLargeIcon(it) }
        appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)?.let { intent ->
            builder.setContentIntent(PendingIntent.getActivity(appContext, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
        manager.notify(mediaNotificationId, builder.build())
        return true
    }

    private fun requestNotificationPermission() {
        val host = activity ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || notificationPermissionRequested ||
            host.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        notificationPermissionRequested = true
        host.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), mediaNotificationId)
    }

    private fun acquireAudioFocus() {
        val manager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setAcceptsDelayedFocusGain(true)
                .setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener(audioFocusListener, mainHandler).build()
            audioFocusRequest = request
            manager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(audioFocusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        hasAudioFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (!hasAudioFocus) android.util.Log.w("platform_services", "Audio focus request not granted: $result")
    }

    private fun releaseAudioFocus() {
        val manager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { manager.abandonAudioFocusRequest(it) }
        } else if (hasAudioFocus) {
            @Suppress("DEPRECATION")
            manager.abandonAudioFocus(audioFocusListener)
        }
        audioFocusRequest = null
        hasAudioFocus = false
    }

    private fun releaseProofAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            proofAudioFocusRequest?.let { manager.abandonAudioFocusRequest(it) }
            proofAudioFocusRequest = null
        }
    }

    // Proof setup traverses Android's framework controller/focus paths, never the event emitter.
    private fun mediaSessionProof(call: MethodCall): Map<String, Any> {
        if (appContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return unsupported(call.method)
        val session = mediaSession ?: return unsupported(call.method)
        val controller = MediaController(appContext, session.sessionToken)
        val values = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        return when (call.method) {
            "lifecycle.mediaSession.proof.snapshot" -> mapOf(
                "supported" to true, "isActive" to session.isActive,
                "state" to (controller.playbackState?.state ?: PlaybackState.STATE_NONE),
                "title" to (controller.metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""),
                "lastFocusChange" to lastAudioFocusChange, "focusChangeCount" to audioFocusChangeCount,
                "durationMs" to (controller.metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L),
                "positionMs" to (controller.playbackState?.position ?: 0L),
            )
            "lifecycle.mediaSession.proof.seekTo" -> {
                val position = (values["positionMs"] as? Number)?.toLong()
                    ?: return mapOf("supported" to false, "reason" to "positionMs required")
                controller.transportControls.seekTo(position.coerceAtLeast(0))
                mapOf("supported" to true)
            }
            else -> {
                releaseProofAudioFocus()
                if (values["gain"] == "release") return mapOf("supported" to true, "granted" to true)
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return unsupported(call.method)
                val gain = when (values["gain"]) {
                    "transient" -> AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                    "permanent" -> AudioManager.AUDIOFOCUS_GAIN
                    else -> return mapOf("supported" to false, "reason" to "invalid focus gain")
                }
                val request = AudioFocusRequest.Builder(gain)
                    .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                    .setOnAudioFocusChangeListener(proofAudioFocusListener, mainHandler).build()
                proofAudioFocusRequest = request
                val manager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val result = manager.requestAudioFocus(request)
                mapOf("supported" to true, "granted" to (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED),
                    "focusResult" to result)
            }
        }
    }

    private fun mediaAction(label: String, command: String, iconResource: Int, requestCode: Int): Notification.Action {
        val intent = Intent(mediaCommandAction).setPackage(appContext.packageName).putExtra("command", command)
        val pending = PendingIntent.getBroadcast(
            appContext,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(Icon.createWithResource(appContext, iconResource), label, pending).build()
    }

    private fun display(): Display? {
        val manager = appContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        return manager?.defaultDisplay
    }

    private fun displayModeInfos(display: Display): List<DisplayModeInfo> =
        display.supportedModes.map { DisplayModeInfo(it.modeId, it.physicalWidth, it.physicalHeight, it.refreshRate.toDouble()) }

    private fun displayModes(): Map<String, Any> {
        val display = display() ?: return mapOf("supported" to false, "modes" to emptyList<Any>(), "reason" to "display unavailable")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return mapOf("supported" to false, "modes" to emptyList<Any>(), "reason" to "Display.Mode requires API 23")
        val current = display.mode
        val modes = displayModeInfos(display).map { mode ->
            mapOf("width" to mode.width, "height" to mode.height, "refreshHz" to mode.refreshHz, "isCurrent" to (mode.id == current.modeId))
        }
        return mapOf("supported" to true, "modes" to modes)
    }

    // Kodi android_reference 4.3 SetDisplayMode: set WindowManager.LayoutParams.preferredDisplayModeId and
    // wait for onDisplayChanged (max 5 s). androidtv 4.3: a TV waits at least 2 s for the HDMI link to retrain.
    private fun requestDisplayMode(window: android.view.Window, display: Display, modeId: Int, result: Result, onApplied: () -> Unit = {}) {
        val params = window.attributes
        if (display.mode.modeId == modeId) {
            // Cancel a previous request even when the hardware never switched.
            params.preferredDisplayModeId = modeId
            window.attributes = params
            onApplied()
            result.success(mapOf("supported" to true, "switched" to false, "reason" to "mode already active"))
            return
        }
        val manager = appContext.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
            ?: return result.success(unsupported("display.apply"))
        val started = SystemClock.elapsedRealtime()
        var finished = false
        lateinit var listener: DisplayManager.DisplayListener
        lateinit var timeout: Runnable
        fun finish(switched: Boolean) {
            if (finished) return
            finished = true
            manager.unregisterDisplayListener(listener)
            mainHandler.removeCallbacks(timeout)
            val elapsed = SystemClock.elapsedRealtime() - started
            mainHandler.postDelayed({
                if (switched) onApplied()
                result.success(mapOf("supported" to switched, "switched" to switched, "waitedMs" to SystemClock.elapsedRealtime() - started, "reason" to if (switched) "requested mode observed" else "requested mode was not observed before timeout"))
            }, displayChangeWaitMs(isTelevision, elapsed))
        }
        listener = object : DisplayManager.DisplayListener {
            override fun onDisplayAdded(displayId: Int) {}
            override fun onDisplayRemoved(displayId: Int) {}
            override fun onDisplayChanged(displayId: Int) {
                if (displayId == display.displayId && display.mode.modeId == modeId) finish(true)
            }
        }
        timeout = Runnable { finish(false) }
        manager.registerDisplayListener(listener, mainHandler)
        mainHandler.postDelayed(timeout, DISPLAY_CHANGE_TIMEOUT_MS)
        params.preferredDisplayModeId = modeId
        window.attributes = params
    }

    private fun applyDisplayMode(arguments: Any?, result: Result) {
        val window = activity?.window ?: return result.success(unsupported("display.apply"))
        val display = display() ?: return result.success(unsupported("display.apply"))
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return result.success(unsupported("display.apply"))
        val values = arguments as? Map<*, *> ?: return result.success(unsupported("display.apply"))
        val width = (values["width"] as? Number)?.toInt() ?: return result.success(unsupported("display.apply"))
        val height = (values["height"] as? Number)?.toInt() ?: return result.success(unsupported("display.apply"))
        val refresh = (values["refreshHz"] as? Number)?.toDouble() ?: return result.success(unsupported("display.apply"))
        val target = findDisplayMode(displayModeInfos(display), width, height, refresh)
            ?: return result.success(mapOf("supported" to false, "reason" to "requested display mode was not enumerated"))
        // Only the first lease records what to restore; a re-match must not capture an already switched mode.
        if (previousDisplayModeId == null && target.id != display.mode.modeId) previousDisplayModeId = display.mode.modeId
        requestDisplayMode(window, display, target.id, result)
    }

    private fun restoreDisplayMode(result: Result) {
        val window = activity?.window ?: return result.success(unsupported("display.restore"))
        val display = display() ?: return result.success(unsupported("display.restore"))
        val previous = previousDisplayModeId ?: return result.success(mapOf("supported" to true))
        requestDisplayMode(window, display, previous, result) { previousDisplayModeId = null }
    }

    private fun capabilityProbe(): Map<String, Any> {
        val display = display()
        // Kodi 4.7: IsHDRDisplay is Display.isHdr(); the formats come from getHdrCapabilities().
        val isHdr = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && display?.isHdr == true
        val hdrTypes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && display != null) {
            display.hdrCapabilities?.supportedHdrTypes ?: intArrayOf()
        } else intArrayOf()
        val hdrFormats = hdrFormatNames(hdrTypes)
        val decoders = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            android.media.MediaCodecList(android.media.MediaCodecList.ALL_CODECS).codecInfos.filter { !it.isEncoder && it.isHardwareAccelerated }.map { it.name }
        } else emptyList()
        return mapOf(
            "hardwareDecode" to decoders.isNotEmpty(),
            "decoders" to decoders,
            "hdrOutput" to isHdr,
            "hdrFormats" to hdrFormats,
            "displayModeSwitching" to hasDisplayModes(Build.VERSION.SDK_INT, display?.supportedModes?.size ?: 0),
            "audioPassthrough" to audioSnapshot().formats.isNotEmpty(),
            "passthroughFormats" to audioSnapshot().formats.toList(),
            "diagnostics" to mapOf(
                "isTv" to isTelevision.toString(),
                "apiLevel" to Build.VERSION.SDK_INT.toString(),
                "decoderSource" to "MediaCodecList.isHardwareAccelerated",
                "display.isHdr" to isHdr.toString(),
                "display.hdrTypes" to hdrTypes.joinToString(","),
                "display.modeCount" to (display?.supportedModes?.size ?: 0).toString(),
                "display.refreshRates" to (display?.supportedModes?.map { it.refreshRate.toDouble() }?.distinct()?.sorted()?.joinToString(",") ?: ""),
                "audioPassthrough" to "Kodi trial probes; rejected formats decode to PCM",
            ) + audioSnapshot().diagnostics()
        )
    }

    private fun audioDevices(): Map<String, Any> {
        val caps = audioSnapshot()
        // AudioTrack routes automatically. Physical AudioDeviceInfo IDs are not
        // mpv output-device names and cannot be used to select its output.
        return mapOf("supported" to true, "os" to "android", "devices" to listOf(
            mapOf("id" to "auto", "name" to "AudioTrack", "kind" to "unknown",
                "isCurrent" to true, "supportedSampleRates" to caps.rates),
        ), "diagnostic" to "Android AudioTrack automatic route; Kodi trial probes")
    }

    private fun negotiateAudio(arguments: Any?): Map<String, Any?> {
        val values = arguments as? Map<*, *> ?: return mapOf("passthrough" to false, "fallbackReason" to "invalid audio stream specification", "deviceId" to "auto")
        val codec = when (values["codec"]?.toString()?.lowercase()) {
            "ac3" -> "ac3"
            "eac3", "eac3-joc", "eac3_joc" -> "eac3"
            "dts" -> "dts"
            "dtshd", "dts-hd" -> "dtsHd"
            "truehd" -> "trueHd"
            else -> null
        }
        val requested = values["requestedPassthrough"] == true
        val supported = requested && codec != null && codec in audioSnapshot().formats
        return mapOf("passthrough" to supported, "fallbackReason" to
            if (requested && !supported) "AudioTrack getMinBufferSize rejects ${values["codec"]} IEC output; decode to PCM" else null,
            "deviceId" to "auto")
    }

    private fun setKeepAwake(enabled: Boolean): Map<String, Any> {
        val window = activity?.window ?: return unsupported("lifecycle.keepAwake")
        if (enabled) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        return mapOf("supported" to true)
    }

    private fun probeMedia(arguments: Any?): Map<String, Any> {
        val path = arguments as? String
            ?: return mapOf("supported" to false, "reason" to "media path is required")
        val retriever = MediaMetadataRetriever()
        val extractor = MediaExtractor()
        return try {
            retriever.setDataSource(path)
            extractor.setDataSource(path)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val frameRate = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toDoubleOrNull() ?: 0.0
            } else 0.0
            val extractorFrameRate = (0 until extractor.trackCount).asSequence()
                .map { extractor.getTrackFormat(it) }
                .firstOrNull { it.getString(android.media.MediaFormat.KEY_MIME)?.startsWith("video/") == true }
                ?.let { format ->
                    if (format.containsKey(android.media.MediaFormat.KEY_FRAME_RATE)) {
                        format.getInteger(android.media.MediaFormat.KEY_FRAME_RATE).toDouble()
                    } else 0.0
                } ?: 0.0
            val audioFormats = (0 until extractor.trackCount).mapNotNull { index ->
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(android.media.MediaFormat.KEY_MIME) ?: return@mapNotNull null
                if (!mime.startsWith("audio/")) return@mapNotNull null
                mapOf(
                    "mime" to mime,
                    "channels" to (if (format.containsKey(android.media.MediaFormat.KEY_CHANNEL_COUNT)) format.getInteger(android.media.MediaFormat.KEY_CHANNEL_COUNT) else 0),
                    "sampleRate" to (if (format.containsKey(android.media.MediaFormat.KEY_SAMPLE_RATE)) format.getInteger(android.media.MediaFormat.KEY_SAMPLE_RATE) else 0),
                )
            }
            val codecs = (0 until extractor.trackCount).mapNotNull { index ->
                val mime = extractor.getTrackFormat(index).getString(android.media.MediaFormat.KEY_MIME)
                    ?: return@mapNotNull null
                if (!mime.startsWith("video/")) return@mapNotNull null
                when (mime) {
                    "video/avc" -> "h264"
                    "video/hevc" -> "hevc"
                    "video/x-vnd.on2.vp8" -> "vp8"
                    "video/x-vnd.on2.vp9" -> "vp9"
                    "video/av01" -> "av1"
                    else -> mime
                }
            }.distinct()
            mapOf(
                "supported" to true,
                "durationMs" to duration,
                "videoWidth" to width,
                "videoHeight" to height,
                "videoFrameRate" to if (frameRate > 0) frameRate else extractorFrameRate,
                "audioChannels" to (audioFormats.firstOrNull()?.get("channels") ?: 0),
                "audioSampleRate" to (audioFormats.firstOrNull()?.get("sampleRate") ?: 0),
                "audioFormats" to audioFormats,
                "codecs" to codecs,
            )
        } catch (error: RuntimeException) {
            mapOf("supported" to false, "reason" to "media probe failed: ${error::class.simpleName}")
        } finally {
            extractor.release()
            retriever.release()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null; previousDisplayModeId = null }
}
