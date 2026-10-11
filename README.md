# GenoTV

A fast, lightweight movie and TV streaming player for Windows, macOS, Android and iOS (tvOS later).

**Goal:** an Infuse-grade interface with near-Kodi playback, without Kodi's size and complexity.
Browse titles, pick a source, and play: direct HTTP files, HLS, magnet links and torrents
(streamed while downloading), with casting to Chromecast, DLNA and AirPlay. English and Farsi.

> Work in progress. Details coming soon.

## Building

Flutter app in `app/`, with the shared code split into packages under `packages/`.

```bash
cd app
flutter pub get
flutter run
```

## Credits

GenoTV is built on these open-source projects:

**App and UI**
- [Flutter](https://flutter.dev) and Dart
- [phosphor_flutter](https://github.com/phosphor-icons/phosphor-flutter): icons (bundled, patched)
- [flutter_thinking_orbs](https://pub.dev/packages/flutter_thinking_orbs): loading animation
- [flutter_animate](https://pub.dev/packages/flutter_animate), [animations](https://pub.dev/packages/animations), [skeletonizer](https://pub.dev/packages/skeletonizer)
- [drift](https://drift.simonbinder.eu): local database
- [shamsi_date](https://pub.dev/packages/shamsi_date) and [intl](https://pub.dev/packages/intl): Persian calendar and localisation
- [qr_flutter](https://pub.dev/packages/qr_flutter), [file_selector](https://pub.dev/packages/file_selector), [url_launcher](https://pub.dev/packages/url_launcher), [wakelock_plus](https://pub.dev/packages/wakelock_plus), [path_provider](https://pub.dev/packages/path_provider)

**Playback**
- [media_kit](https://github.com/media-kit/media-kit): Flutter player API (bundled, patched)
- [mpv / libmpv](https://github.com/mpv-player/mpv): playback engine
- [FFmpeg](https://github.com/FFmpeg/FFmpeg): decoding, and remuxing for casting
- [libass](https://github.com/libass/libass), [HarfBuzz](https://github.com/harfbuzz/harfbuzz), [FriBidi](https://github.com/fribidi/fribidi): subtitle rendering
- [Mbed TLS](https://github.com/Mbed-TLS/mbedtls)
- media-kit native builds: [libmpv-darwin-build](https://github.com/media-kit/libmpv-darwin-build), [libmpv-android-video-build](https://github.com/media-kit/libmpv-android-video-build), [media-kit-android-helper](https://github.com/media-kit/media-kit-android-helper)
- [fftools-ffi](https://github.com/moffatman/fftools-ffi)

**Downloading and torrents**
- [aria2](https://github.com/aria2/aria2): multi-connection HTTP downloading
- [libtorrent](https://github.com/arvidn/libtorrent) (rasterbar), with [Boost](https://www.boost.org) and [OpenSSL](https://www.openssl.org)

**Sources and casting**
- [PlayTorrio V3](https://github.com/ayman708-UX/PlayTorrioV3): torrent search, title parsing and relevance scoring, and direct-source extractors (ported, GPL-3.0)
- Flyx: several direct-source extractors (ported)
- [dart_cast](https://github.com/abdelaziz-mahdy/dart_cast): Chromecast and DLNA casting (bundled fork)
- [TMDb](https://www.themoviedb.org) and [OMDb](https://www.omdbapi.com): titles, artwork and ratings

**Reference**
- [Kodi](https://kodi.tv): playback settings and behaviour

## License

GNU GPL v3.0. See [LICENSE](LICENSE). Bundled third-party code keeps its own licence.
