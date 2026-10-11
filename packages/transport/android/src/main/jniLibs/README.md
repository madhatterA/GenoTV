# Android native bundle

The `arm64-v8a` directory contains the release slice built by
`tool/build_libtorrent_android.sh` with Android NDK 28.2.13676358, Android API
24, libtorrent `v2.1.1` (`56ae8caba38bf154ffc21033cb23f91d0ecaa49`), and its
`try_signal` submodule (`105cce59972f925a33aa6b1c3109e4cd3caf583d`). WebTorrent
and OpenSSL are disabled; DHT, protocol extensions, piece deadlines, and the
transport C ABI remain enabled.

The checked artifact hashes are:

```text
libtorrent-rasterbar.so  382221eba35476b433b30de2fefe62e4d6082d24ceffa8460e56884f91dac1b0
libtransport_lt_shim.so  59c24b3ab1eab7bf1a6e35bdeba766756fc6002dc9d6fd64ac021433bf3413eb
```

Licenses: libtorrent and `try_signal` BSD-3-Clause; Boost headers Boost
Software License 1.0. Source license texts are retained in the pinned
source trees under `research/technical/`.

The rebuilt slice is ELF64 AArch64 and has only `libtorrent-rasterbar.so`,
`libc++_shared.so`, libc, libm, and libdl dependencies. On the Android
arm64 emulator (`emulator-5554`), the packaged pair plus NDK
`libc++_shared.so` passed 100 create/destroy cycles and duplicate session
destroy calls through `tool/native_lifecycle_smoke.cpp`.
