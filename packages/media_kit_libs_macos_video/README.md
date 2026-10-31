# Local macOS engine package

MIT plugin copied from `media_kit_libs_macos_video` 1.1.4. Its arm64 frameworks are
replaced by the source-built gpu-next (libplacebo + MoltenVK) engine from
`packages/playback/tool/build_libmpv_macos_metal.py`; the x86_64 slices keep the
upstream bytes (no native surface there, the texture path is used).

```sh
python3 packages/playback/tool/build_libmpv_macos_metal.py
python3 packages/playback/tool/package_macos_engine.py
```

Generated frameworks are ignored; CocoaPods fails with the command above if absent.
