package com.genotv.platform_services

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

internal class PlatformServicesPluginTest {
    @Test
    fun onMethodCall_version_returnsStructuredPayload() {
        val plugin = PlatformServicesPlugin()

        val call = MethodCall("capabilities.version", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(
            mapOf("os" to "Android ${android.os.Build.VERSION.RELEASE}", "plugin" to "0.0.1"),
        )
    }
}
