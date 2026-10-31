package com.genotv.video_player

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.genotv.video_player/log")
            .setMethodCallHandler { call, result ->
                if (call.method == "debugInfo") {
                    result.success(
                        mapOf(
                            "logDir" to getExternalFilesDir(null)?.absolutePath,
                            "device" to "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL} " +
                                "abi=${android.os.Build.SUPPORTED_ABIS.joinToString(",")} " +
                                "android=${android.os.Build.VERSION.RELEASE} sdk=${android.os.Build.VERSION.SDK_INT}",
                        ),
                    )
                    return@setMethodCallHandler
                }
                if (call.method != "write") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val args = call.arguments as? Map<*, *>
                val priority = (args?.get("priority") as? Number)?.toInt()
                val message = args?.get("message") as? String
                if (priority == null || priority !in Log.DEBUG..Log.ERROR || message == null) {
                    result.error("invalid_argument", "Log priority and message are required", null)
                    return@setMethodCallHandler
                }
                Log.println(priority, "GenoTV", message)
                result.success(null)
            }
    }
}
