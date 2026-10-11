import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sets the test surface to an exact logical [size], pinning
/// `devicePixelRatio` to 1.0 so `physicalSize / devicePixelRatio` equals
/// [size] regardless of the host's ambient devicePixelRatio.
///
/// `tester.binding.setSurfaceSize` only sets the physical size; on a host
/// whose ambient devicePixelRatio isn't 1.0 (e.g. a Retina display, ratio
/// 3.0), the resulting logical size (what `MediaQuery.sizeOf` reports) does
/// not equal the requested size. See bug_history.md,
/// "binding.setSurfaceSize alone doesn't control logical width...".
Future<void> setLogicalSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}
