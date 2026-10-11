# cast

Chromecast and DLNA casting for the app. Vendored fork of `dart_cast`.

- Upstream: https://github.com/abdelaziz-mahdy/dart_cast
- Pinned commit: `fc53c72cd84af8b4b7253e506741a7efd87ecbf5` (pubspec 0.7.5)
- Licence: MIT, see `LICENSE`.

Kept: `lib/src/core/` (device, session, discovery, media proxy, HLS, subtitle converter),
`lib/src/protocols/chromecast/`, `lib/src/protocols/dlna/`, `lib/src/utils/`, and their tests.
Removed: everything AirPlay (protocol, auth, plist, `CastProtocol.airplay`, tests) and the
`cryptography` dependency. AirPlay is built natively in Part 09 Chapter 06.

Edits against upstream, all to satisfy the repo's `analysis_options.yaml`: unawaited futures
wrapped in `unawaited(...)`, two `ignore: prefer_initializing_formals` comments, package name
`cast` (entry file stays `lib/dart_cast.dart` so upstream diffs stay readable), and AirPlay mentions in comments removed.
