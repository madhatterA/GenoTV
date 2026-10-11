import 'package:flutter/widgets.dart';

export '../l10n_gen/app_strings.dart';

/// The [Locale] for an `app.language` value; null (system) lets the platform
/// locale list pick `fa` or the `en` fallback.
Locale? localeForLanguage(String code) => switch (code) {
  'en' => const Locale('en'),
  'fa' => const Locale('fa'),
  _ => null,
};

/// Wraps the app below the localizations in an LTR [Directionality]: the
/// layout never mirrors, only text shapes right-to-left (DESIGN_SPEC §10.3).
Widget keepLayoutLtr(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);
