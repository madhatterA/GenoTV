# media_kit 1.2.6 portable debug reference-cache fix

Pinned source: pub.dev media_kit 1.2.6 (MIT); runtime source, assets and metadata copied unchanged except `lib/src/player/native/utils/native_reference_holder.dart`.

The upstream debug holder persists a raw native buffer address in a PID-only file. Windows reuses PIDs; a later process dereferences a dead allocation before mpv opens any media. The app and playback package select this local copy, as they already do for media_kit_video. No dependency/version change.

The cache now includes the Dart VM birth time, read from the local VM service getVM response. VM birth time stays stable across hot-restart, including unauthenticated/fixed-port services. A debug process without an available VM service uses a fresh UUID and never recovers disk pointers. Release/profile behavior remains upstream (holder disabled). This is shared Dart code on every native platform; no engine, libass or fixture change.

Regression: app/test/native_reference_holder_test.dart starts direct Dart VM child processes (--disable-dart-dev, without the CLI/DDS lifecycle) with an invalid legacy PID cache, both with and without a VM service. Before the patch the child segfaults at NativeReferenceHolder._ensureInitialized; after the patch it allocates a new buffer. The probe also checks recovery across isolates in the same VM when a service is present.

Docs: https://api.dart.dev/dart-developer/Service/getInfo.html — “Get information about the service protocol (version number and Uri to access the service).” Context7 connector unavailable in this session; official Dart API used. No native rebuild required. getVM response pid/startTime are validated, requests are bounded and client is closed. A failed identity lookup logs its error and allocates a fresh buffer, preserving playback safety; pointer allocation/cache failures are not swallowed.
