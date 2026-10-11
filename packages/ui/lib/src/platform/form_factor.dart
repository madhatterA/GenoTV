import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The three chrome/layout families: TV rail, desktop (also tablets), phone.
enum FormFactor { tv, desktop, phone }

/// `tv` for the host's TV flag; `phone` on Android/iOS below a 600 shortest
/// side; `desktop` otherwise.
FormFactor resolveFormFactor({
  required bool isTv,
  required TargetPlatform platform,
  required Size size,
}) {
  if (isTv) return FormFactor.tv;
  final mobile =
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  return mobile && size.shortestSide < 600
      ? FormFactor.phone
      : FormFactor.desktop;
}
