# tvOS handoff (Part 02 -> Part 08)

Part 02 builds one adaptive Flutter UI. It does **not** compile tvOS: Flutter has no official
tvOS target (`https://docs.flutter.dev/deployment/ios`). Part 08 implements the native tvOS host
and any Top Shelf extension, and reuses the interaction rules below. Nothing here is a copy of a
value: each row names the symbol or test that owns it, so the value cannot drift. Read the symbol.

## Tokens
- Colors, geometry, motion, focus metrics, type styles: `RivuletTokens` and its parts
  (`RivuletColors`, `RivuletGeometry`, `RivuletMotion`, `RivuletFocusMetrics`,
  `RivuletTypeStyles`) in `lib/src/theme/rivulet_tokens.dart`; proof `test/theme_test.dart`.
- Viewport scaling: `RivuletLayout.scaleFor` in `lib/src/layout/rivulet_layout.dart`.

## Commands and timing
- Command vocabulary, dedupe classes and windows: `UiCommandType`, `DedupeClass` in
  `lib/src/focus/ui_command.dart`; hold/tap/coalescing in `lib/src/focus/input_router.dart`.
  Proof `test/focus_input_test.dart` (Enter and D-pad Select emit identical commands;
  also `test/platform_adaptation_test.dart`).
- Activation, press scale, disabled-skips-traversal: `FocusableAction`, `FocusableCard`.

## Focus order
- Row focus and memory: `RowFocusPolicy`, `FocusMemory`, `DirectionalFocusGuide`
  (`lib/src/focus/`). TV rows move item to item (no free scroll). Proof `test/focus_test.dart`,
  `test/browse_shelves_test.dart`, `test/states_accessibility_test.dart` (no focus trap).

## Geometry: sidebar, home, detail, player
- Sidebar and shell: `lib/src/navigation/app_shell.dart`, `sidebar.dart`; proof
  `test/navigation_shell_test.dart` ("sidebar geometry matches the locked Rivulet constants").
- Home, detail, search, library: `lib/src/browse/`, `lib/src/detail/`, `lib/src/search/`.
- Player rail/panels per form factor: `PlayerFormFactor.tv` (`lib/src/player/player_form_factor.dart`,
  opt-in only; the host passes it). Proof `test/player_rail_test.dart`,
  `test/player_panels_test.dart`, `test/player_box_options_test.dart`.

## Back priority
Focused popup/panel -> player chrome or transient mode -> page-local stack -> tab stack ->
sidebar collapse -> app exit. Owner: `BackDispatcher` (`lib/src/navigation/back_dispatcher.dart`);
proof `test/navigation_shell_test.dart` and the `exit` step of
`test/part04_rivulet_acceptance_test.dart`.

## Thumbnail behavior
Scrub thumbnails: `BifThumbnailIndex`, `ThumbnailPreviewController`
(`lib/src/player/`); stale results ignored by request token. Proof `test/bif_thumbnail_test.dart`,
`test/player_scrubber_test.dart`.

## Accessibility
`UiAccessibility`, `StateSkeleton` (`lib/src/accessibility/`, `lib/src/states/`); capability
queries live only in `AdaptiveBehavior` / `PlatformCapabilities`
(`lib/src/platform/adaptive_behavior.dart`). Proof `test/shared_accessibility_test.dart`,
`test/states_accessibility_test.dart`.

## Golden references (already tested here)
`test/goldens/`: `player_rail_tv*`, `player_box_tv_*`, `browse_*`, `a11y_<Screen>_<W>x<H>.png`
(11 screens x 400x800, 844x390, 1280x800, 1920x1080), `acceptance_player_<W>x<H>.png`.

## Part 08 owns
The native tvOS host, focus-engine bridging, Top Shelf extension, and any tvOS-only capability.
Part 02 changes no native code.
