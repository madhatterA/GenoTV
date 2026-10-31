# `app`

The runner application and composition root. **Owned by Part 07**; created and minimally
populated by Part 01, and the platform runner projects (`android/`, `ios/`, `macos/`,
`windows/`) are owned by Part 09 from packaging onward.

`app/lib/composition.dart` is the only place in the repository where implementations from
different Parts meet. See `planning/part-07-integration/PART.md`.

## Pending cleanup: test video in the shipped app

`app/assets/Butterfly-209.mp4` (2.4 MB) is a test clip that still ships inside every
release build. It is kept only because `app/lib/fixture_provider.dart` (the built-in
test source) loads it and `app/pubspec.yaml` lists it under `assets:`.

To remove it safely, in this order:
1. Remove `fixture_provider.dart` and every place that registers it as a source
   (search `app/lib` for `fixture_provider` / `FixtureProvider`).
2. Remove `- assets/Butterfly-209.mp4` from `app/pubspec.yaml`.
3. Delete `app/assets/Butterfly-209.mp4`, then `flutter build` each platform to confirm.

Tests and the GenoTV Test app live in the separate `genotv-test` worktree, not here.
