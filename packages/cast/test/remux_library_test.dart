import 'package:cast/src/remux/remux_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS loads the embedded remux framework beside the app executable', () {
    expect(
      remuxLibraryPath(
        operatingSystem: 'ios',
        executable: '/Applications/Video Player.app/Runner',
      ),
      '/Applications/Video Player.app/Frameworks/cast_remux.framework/cast_remux',
    );
  });

  test('macOS preserves its Contents/Frameworks location', () {
    expect(
      remuxLibraryPath(
        operatingSystem: 'macos',
        executable:
            '/Applications/Video Player.app/Contents/MacOS/video_player',
      ),
      '/Applications/Video Player.app/Contents/Frameworks/libcast_remux.dylib',
    );
  });

  test('Windows and Android preserve their library names', () {
    expect(remuxLibraryPath(operatingSystem: 'windows'), 'cast_remux.dll');
    expect(remuxLibraryPath(operatingSystem: 'android'), 'libcast_remux.so');
  });

  test('unsupported platforms fail explicitly', () {
    expect(
      () => remuxLibraryPath(operatingSystem: 'unknown'),
      throwsUnsupportedError,
    );
  });
}
