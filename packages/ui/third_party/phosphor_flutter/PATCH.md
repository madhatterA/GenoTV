# Vendored phosphor_flutter

Upstream: phosphor_flutter 2.1.0 (pub.dev), copied from the pub-cache. LICENSE and fonts are unchanged
(Phosphor-Duotone.ttf removed, see below). `example/` and `meta/` screenshots dropped.

Why: upstream does not compile on Flutter 3.47 (`class PhosphorIconData extends IconData`:
"IconData can't be extended outside of its library because it's a final class").

Exact change:
- In `lib/src/phosphor_icons_{regular,thin,light,bold,fill}.dart` every
  `PhosphorFlatIconData(0xNNNN, 'Style')` became
  `IconData(0xNNNN, fontFamily: 'PhosphorStyle', fontPackage: 'phosphor_flutter', matchTextDirection: true)`
  (identical values to upstream's `PhosphorIconData` super call).
- Deleted `phosphor_icon_data.dart` (the IconData subclasses), `phosphor_icon.dart` (`PhosphorIcon` widget,
  only needed for duotone; use `Icon`), `phosphor_icons_base.dart` (style-switch helper) and the Duotone
  style (`phosphor_icons_duotone.dart`, `Phosphor-Duotone.ttf`, its pubspec font entry). Exports updated.
- Removed the pubspec `screenshots:` block (dropped meta/ images).
