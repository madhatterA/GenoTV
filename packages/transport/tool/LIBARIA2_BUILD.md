# libaria2 iOS build

`build_libaria2_ios.sh` is the reproducible entrypoint and requires
`ARIA2_SOURCE` (aria2 ref `9e7273583f83`, override only with explicit
`ARIA2_REF`) and Xcode. With no `ARIA2_PREFIX`, it writes device and simulator
archives plus `ios/libs/libaria2/libaria2.xcframework` and its public header;
the podspec links that static archive and exposes the header to the C++ shim.
It enables static libaria2 and disables BitTorrent, Metalink, SFTP, XML-RPC,
and WebSocket; BitTorrent remains libtorrent-owned.

## libaria2 macOS build

`build_libaria2_macos.sh` (no arguments, arm64, minos 12.0) copies the pinned
aria2 source (`research/technical/downloading/aria2`, ref `9e7273583f83`;
override with `ARIA2_SOURCE`/`ARIA2_REF`) to a scratch directory, builds static
libaria2 with the same flags as the iOS build (AppleTLS, no OpenSSL, no
libxml2/expat/libssh2, BitTorrent/Metalink/SFTP/XML-RPC/WebSocket off), and links
it with `ios/Classes/aria2_shim.mm` (shared with iOS) into
`macos/libs/libtransport_aria2_shim.dylib`. Runtime dependencies are system
frameworks/libs only. Homebrew supplies build tools only. The macOS pod runs the
script before compile and vendors the dylib into the app's Frameworks.
aria2.h has no byte-offset priority (only queue-position `changePosition`), so
seek is the loopback slice window in `lib/src/http/aria2_window.dart`.
The shim worker sleeps while aria2 has no active/waiting download and yields the
lock to callers that lost `try_lock`, otherwise every API call waited on a 1 s poll.
