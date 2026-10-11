import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/cross_device_test.dart' as proof;

void main() {
  testWidgets('blank-frame proof accepts content without a Scaffold', (
    tester,
  ) async {
    final count = await tester.runAsync(
      () => proof.countCrossDeviceBlankFrames(
        tester,
        () => tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('content'),
          ),
        ),
        window: const Duration(milliseconds: 32),
      ),
    );
    expect(count, 0);
  });
  testWidgets('blank-frame proof catches a route with no Scaffold', (
    tester,
  ) async {
    final count = await tester.runAsync(
      () => proof.countCrossDeviceBlankFrames(
        tester,
        () => tester.pumpWidget(const SizedBox()),
        window: const Duration(milliseconds: 32),
      ),
    );
    expect(count, greaterThan(0));
  });
  testWidgets('blank-frame proof catches an empty Scaffold', (tester) async {
    final count = await tester.runAsync(
      () => proof.countCrossDeviceBlankFrames(
        tester,
        () => tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
        window: const Duration(milliseconds: 32),
      ),
    );
    expect(count, greaterThan(0));
  });
  testWidgets('blank-frame proof accepts visible route content', (
    tester,
  ) async {
    final count = await tester.runAsync(
      () => proof.countCrossDeviceBlankFrames(
        tester,
        () => tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('content'))),
        ),
        window: const Duration(milliseconds: 32),
      ),
    );
    expect(count, 0);
  });
}
