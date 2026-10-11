# Local iOS engine package

MIT plugin copied from `media_kit_libs_ios_video` 1.1.4. Its v0.6.0 release archive
is SHA256-checked by `packages/playback/tool/build_libmpv_ios_sim.sh`. All device
and dependency frameworks retain their original bytes. Only Mpv's simulator
variant is replaced with a source-built arm64 framework (the app's existing
simulator architecture boundary).

Run from the repository root:

```sh
timeout 1200 packages/playback/tool/build_libmpv_ios_sim.sh
```

The recipe is pinned to `4286f5557bdccc0747030e3c376ce5cd160a96a0` in
media-kit/libmpv-darwin-build. Its checksummed source register is retained under
`packages/playback/native/ios-simulator/downloads.lock`. Builds cache in `/tmp`,
serialize dependencies and cap compiler batches at four jobs. Current Meson and
CMake require host-tool compatibility adjustments; engine feature options match
the pinned simulator video/default recipe except `audiounit=enabled`.

Generated frameworks are ignored. CocoaPods fails with the build command if they
are absent; it never downloads a silent simulator replacement. The existing
`create_framework_symlinks.sh` publishes media_kit's header lookup layout.

Source: assigned Part07 ch01 p03 Decisions and Android shipping ruling in
`decisions.md` (2026-10-06). Real AudioUnit is required for simulator proofs;
there is no audio/video test override.
