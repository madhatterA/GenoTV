import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

void main() {
  const desktop = DisplayMode(
    width: 3840,
    height: 2160,
    refreshHz: 60,
    isCurrent: true,
  );
  const cadence = DisplayMode(
    width: 3840,
    height: 2160,
    refreshHz: 24,
    isCurrent: false,
  );
  test('Kodi resolution matching falls back to desktop and never shrinks by default', () {
    final match = ModeMatcher.match(
      contentFps: 24,
      width: 1920,
      height: 1080,
      current: desktop,
      modes: [
        desktop,
        cadence,
        const DisplayMode(
          width: 1920,
          height: 1080,
          refreshHz: 24,
          isCurrent: false,
        ),
      ],
    );
    expect(match?.mode, cadence);
  });
  test(
    'Kodi default cadence allows pulldown but rejects arbitrary multiples',
    () {
      expect(
        ModeMatcher.match(
          contentFps: 24,
          modes: const [
            DisplayMode(
              width: 1920,
              height: 1080,
              refreshHz: 60,
              isCurrent: false,
            ),
          ],
        ),
        isNotNull,
      );
      expect(
        ModeMatcher.match(
          contentFps: 24,
          modes: const [
            DisplayMode(
              width: 1920,
              height: 1080,
              refreshHz: 120,
              isCurrent: false,
            ),
          ],
        ),
        isNull,
      );
    },
  );
}
