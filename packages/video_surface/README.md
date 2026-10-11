# video_surface

Native HDR-capable video surface for media_kit players (macOS now; other platforms keep the texture path).

mpv (libmpv render API, from media_kit's `Mpv.framework`) draws into an IOSurface-backed half-float texture that is presented on a `CAMetalLayer` with EDR on (`rgba16Float`, `extendedLinearDisplayP3`). The view is hosted with `AppKitView`, so ordinary Flutter widgets stack above it.

```dart
final surface = await NativeVideoSurface.attach(player); // before player.open
surface.state.addListener(() => print(surface.state.value)); // hdrNative | sdrNative | texture + reason
// in build(): Stack([surface.build(), controls...])  (only when state.mode != texture)
await surface.dispose(); // before player.dispose()
```

`example/` is the proof harness (see `example/lib/main.dart` for the environment variables).
