package com.genotv.video_surface

import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo
import android.hardware.display.DisplayManager
import android.graphics.PixelFormat
import android.os.Build
import android.util.Log
import android.view.Display
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Android video and subtitle surfaces: a paired SurfaceView per player. mpv draws video through
 * `wid` (set from Dart, which owns the player), so the video is its own compositor layer and
 * never goes through Flutter's texture. HDR is requested through the window colour mode.
 */
class VideoSurfacePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private val instances = HashMap<Int, SurfaceInstance>()
    private var nextId = 1

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "video_surface")
        channel.setMethodCallHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            "video_surface/view",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                    val id = (args as? Map<*, *>)?.get("id") as? Int
                    val instance = id?.let { instances[it] }
                    if (instance == null) {
                        Log.e("VideoSurface", "platform view has no surface instance: $id")
                        throw IllegalStateException("known surface instance required: $id")
                    }
                    return instance.newView(context)
                }
            },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        instances.values.toList().forEach { it.dispose() }
        instances.clear()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> {
                val id = nextId++
                try {
                    val info = screen(id)
                    instances[id] = SurfaceInstance(id, channel)
                    result.success(info)
                } catch (e: Exception) {
                    Log.e("VideoSurface", "surface creation failed", e)
                    result.error("surface_creation_failed", e.toString(), null)
                }
            }
            "dispose" -> {
                val id = call.argument<Int>("id")
                val instance = instances.remove(id)
                if (instance == null) {
                    result.error("unknown_surface", "no such surface", null)
                    return
                }
                instance.dispose()
                if (instances.isEmpty()) setColorMode(false)
                result.success(null)
            }
            "source" -> {
                val id = call.argument<Int>("id")
                val hdr = call.argument<Boolean>("hdr")
                if (id == null || hdr == null || instances[id] == null) {
                    result.error("bad_args", "known id and hdr required", null)
                    return
                }
                setColorMode(hdr && headroom() > 1.0)
                result.success(null)
            }
            "probe" -> {
                val id = call.argument<Int>("id")
                val instance = instances[id]
                if (id == null || instance == null) {
                    result.error("unknown_surface", "no such surface", null)
                    return
                }
                val s = screen(id)
                s["wid"] = instance.wid
                s["overlayWid"] = instance.overlayWid
                s.putAll(instance.frameRects())
                s["colorMode"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) activity?.window?.colorMode ?: -1 else -1
                result.success(s)
            }
            "releaseRetired" -> {
                val id = call.argument<Int>("id")
                val instance = instances[id]
                val attachedWid = call.argument<Number>("wid")?.toLong()
                val attachedOverlayWid = call.argument<Number>("overlayWid")?.toLong()
                if (instance == null || attachedWid == null || attachedOverlayWid == null) {
                    result.error("bad_args", "known id, wid and overlayWid required", null)
                    return
                }
                try {
                    instance.releaseRetired(attachedWid, attachedOverlayWid)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("surface_reference_release_failed", e.toString(), null)
                }
            }
            "screenEdr" -> result.success(mapOf("edr" to headroom(), "potential" to headroom()))
            "counters" -> result.success(SurfaceInstance.counters())
            else -> result.notImplemented()
        }
    }

    private fun screen(id: Int): HashMap<String, Any> {
        val h = headroom()
        return hashMapOf("id" to id, "edr" to h, "potential" to h, "headroom" to h, "fontsDir" to fontsDir(), "overlaySupported" to true)
    }

    /** libass has no system fonts on Android: copy the bundled font where mpv can read it. */
    private fun fontsDir(): String {
        val dir = java.io.File(context.filesDir, "subfonts").apply { mkdirs() }
        val out = java.io.File(dir, "Vazirmatn-Regular.ttf")
        if (!out.exists()) {
            context.assets.open("fonts/Vazirmatn-Regular.ttf").use { i -> out.outputStream().use { i.copyTo(it) } }
        }
        return dir.path
    }

    /** Peak luminance of the display over SDR white (100 nits); 1.0 when it has no HDR type. */
    private fun headroom(): Double {
        val display = (context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager)
            .getDisplay(Display.DEFAULT_DISPLAY)
        val caps = display?.hdrCapabilities
        if (display == null || caps == null || caps.supportedHdrTypes.isEmpty()) return 1.0
        val nits = caps.desiredMaxLuminance.toDouble()
        return if (nits > 100.0) nits / 100.0 else 10.0
    }

    private fun setColorMode(hdr: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val window = activity?.window ?: return
        val wanted = if (hdr) ActivityInfo.COLOR_MODE_HDR else ActivityInfo.COLOR_MODE_DEFAULT
        if (window.colorMode != wanted) window.colorMode = wanted
    }
}

/** Per-player native state. The Surface handle goes to Dart as a JNI global reference (`wid`). */
private class SurfaceInstance(private val id: Int, private val channel: MethodChannel) {
    var wid = 0L
        private set
    var overlayWid = 0L
        private set
    private val refs = ArrayList<Long>()
    private var disposed = false
    private var videoView: SurfaceView? = null
    private var overlayView: SurfaceView? = null

    init { synchronized(Companion) { instances++ } }

    fun newView(context: Context): PlatformView {
        check(!disposed) { "surface instance is disposed" }
        val container: FrameLayout
        val video: SurfaceView
        val overlay: SurfaceView
        try {
            container = FrameLayout(context)
            video = SurfaceView(context)
            overlay = SurfaceView(context)
            overlay.setZOrderMediaOverlay(true)
            overlay.holder.setFormat(PixelFormat.TRANSLUCENT)
            // Both children fill the same platform view: Dart's aspect/zoom rect applies to both.
            container.addView(video, FrameLayout.LayoutParams(-1, -1))
            container.addView(overlay, FrameLayout.LayoutParams(-1, -1))
            videoView = video
            overlayView = overlay
        } catch (e: Exception) {
            fail("overlay surface creation failed: $e", e)
            throw e
        }
        synchronized(Companion) { views++ }
        var viewDisposed = false
        fun callback(isOverlay: Boolean) = object : SurfaceHolder.Callback {
            var created = false
            override fun surfaceCreated(holder: SurfaceHolder) {
                if (disposed || viewDisposed || created) return
                created = true
                synchronized(Companion) { if (isOverlay) overlaySurfaces++ else surfaces++ }
                try {
                    check(holder.surface.isValid) { "created Surface is invalid" }
                    val ref = newRef(holder.surface)
                    check(ref != 0L) { "JNI returned a null global reference" }
                    refs.add(ref)
                    synchronized(Companion) { refCount++ }
                    if (isOverlay) overlayWid = ref else wid = ref
                    emitSurface(video.holder)
                } catch (e: Exception) {
                    fail("${if (isOverlay) "overlay" else "video"} Surface reference failed: $e", e)
                }
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                if (!disposed && !viewDisposed) emitSurface(video.holder)
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                if (!created) return
                created = false
                synchronized(Companion) { if (isOverlay) overlaySurfaces-- else surfaces-- }
                if (isOverlay) overlayWid = 0L else wid = 0L
                if (!disposed) emitSurface(video.holder)
            }
        }
        val videoCallback = callback(false)
        val overlayCallback = callback(true)
        video.holder.addCallback(videoCallback)
        overlay.holder.addCallback(overlayCallback)
        return object : PlatformView {
            override fun getView(): View = container
            override fun dispose() {
                if (viewDisposed) return
                viewDisposed = true
                videoCallback.surfaceDestroyed(video.holder)
                overlayCallback.surfaceDestroyed(overlay.holder)
                video.holder.removeCallback(videoCallback)
                overlay.holder.removeCallback(overlayCallback)
                if (videoView === video) videoView = null
                if (overlayView === overlay) overlayView = null
                synchronized(Companion) { views-- }
            }
        }
    }

    private fun emitSurface(holder: SurfaceHolder) {
        val frame = holder.surfaceFrame
        val ready = wid != 0L && overlayWid != 0L
        channel.invokeMethod(
            "surface",
            mapOf("id" to id, "wid" to wid, "overlayWid" to overlayWid,
                "width" to if (ready) frame.width() else 0, "height" to if (ready) frame.height() else 0),
        )
    }

    private fun fail(message: String, error: Exception) {
        Log.e("VideoSurface", message, error)
        channel.invokeMethod("failed", mapOf("id" to id, "message" to message, "fatal" to true))
    }

    fun frameRects(): Map<String, Map<String, Int>> {
        fun rect(view: SurfaceView?): Map<String, Int> {
            val location = IntArray(2)
            view?.getLocationOnScreen(location)
            return mapOf("left" to location[0], "top" to location[1],
                "width" to (view?.width ?: 0), "height" to (view?.height ?: 0))
        }
        return mapOf("videoRect" to rect(videoView), "overlayRect" to rect(overlayView))
    }

    /** Dart acknowledges completion of mpv detach/rebind; keep any concurrently recreated Surface. */
    fun releaseRetired(attachedWid: Long, attachedOverlayWid: Long) {
        val keep = setOf(wid, overlayWid, attachedWid, attachedOverlayWid)
        try {
            refs.filter { it !in keep }.forEach {
                deleteRef(it)
                refs.remove(it)
                synchronized(Companion) { refCount-- }
            }
        } catch (e: Exception) {
            fail("retired Surface global reference release failed: $e", e)
            throw e
        }
    }

    /** Dart has already pointed mpv away from the Surface; free the references. */
    fun dispose() {
        if (disposed) return
        disposed = true
        wid = 0L
        overlayWid = 0L
        refs.forEach {
            deleteRef(it)
            synchronized(Companion) { refCount-- }
        }
        refs.clear()
        synchronized(Companion) { instances-- }
    }

    companion object {
        private var instances = 0
        private var views = 0
        private var surfaces = 0
        private var overlaySurfaces = 0
        private var refCount = 0

        fun counters(): Map<String, Int> =
            synchronized(this) { mapOf("instances" to instances, "views" to views, "surfaces" to surfaces,
                "overlaySurfaces" to overlaySurfaces, "globalRefs" to refCount) }

        // media_kit's helper library already owns the JNI global-reference calls mpv's `wid` needs.
        private val helper by lazy { Class.forName("com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper") }

        private fun newRef(surface: Surface): Long =
            helper.getMethod("newGlobalObjectRef", Any::class.java).invoke(null, surface) as Long

        private fun deleteRef(ref: Long) {
            helper.getMethod("deleteGlobalObjectRef", Long::class.javaPrimitiveType).invoke(null, ref)
        }
    }
}
