# Local Android library plugin

MIT copy of media_kit_libs_android_video **1.3.8**. Java and Dart plugin APIs
remain upstream's. Only arm64 native packaging changes: this package ships
our pinned-source libmpv and helper; the other ABIs retain upstream jars.

Build instructions: `../playback/tool/ANDROID_LIBMPV_BUILD.md`.
The orchestrator authorized this replacement in decisions.md, 2026-10-06
“p00c shipping mechanism ruling”.
