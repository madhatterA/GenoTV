package com.genotv.platform_services

internal object NativeCrash {
    init { System.loadLibrary("vp_crash_capture") }
    external fun install(path: String): Int
    external fun uninstall()
    external fun abort()
}
