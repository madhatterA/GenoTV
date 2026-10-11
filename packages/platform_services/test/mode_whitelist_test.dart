import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

const _p60 = DisplayMode(
  width: 1920,
  height: 1080,
  refreshHz: 60,
  isCurrent: true,
);
const _p24 = DisplayMode(
  width: 1920,
  height: 1080,
  refreshHz: 24,
  isCurrent: false,
);
const _p23976 = DisplayMode(
  width: 1920,
  height: 1080,
  refreshHz: 23.976,
  isCurrent: false,
);
const _uhd24 = DisplayMode(
  width: 3840,
  height: 2160,
  refreshHz: 24,
  isCurrent: false,
);
const _all = [_p60, _p24, _p23976, _uhd24];

void main() {
  test('empty allows every mode', () {
    expect(DisplayModeWhitelist.parse('  ').filter(_all), _all);
    expect(
      identical(DisplayModeWhitelist.parse(''), DisplayModeWhitelist.all),
      isTrue,
    );
  });

  test('resolution, refresh and both restrict as written', () {
    expect(DisplayModeWhitelist.parse('3840x2160').filter(_all), [_uhd24]);
    expect(DisplayModeWhitelist.parse('@24').filter(_all), [_p24, _uhd24]);
    expect(DisplayModeWhitelist.parse('1920x1080@23.976').filter(_all), [
      _p23976,
    ]);
    expect(
      DisplayModeWhitelist.parse('1920x1080@60, 3840x2160@24').filter(_all),
      [_p60, _uhd24],
    );
  });

  test('an invalid entry allows nothing and is reported', () {
    final list = DisplayModeWhitelist.parse('1080p, @24');
    expect(list.invalid, ['1080p']);
    expect(list.filter(_all), [_p24, _uhd24]);
    final bad = DisplayModeWhitelist.parse('nonsense');
    expect(bad.filter(_all), isEmpty);
    expect(bad.invalid, ['nonsense']);
  });
}
