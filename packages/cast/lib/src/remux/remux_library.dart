import 'dart:io';

/// Platform-specific library location stays outside the shared remux lifecycle.
String remuxLibraryPath({
  String? operatingSystem,
  String? executable,
}) => switch (operatingSystem ?? Platform.operatingSystem) {
  'macos' => File(
    executable ?? Platform.resolvedExecutable,
  ).parent.parent.uri.resolve('Frameworks/libcast_remux.dylib').toFilePath(),
  'ios' =>
    File(executable ?? Platform.resolvedExecutable).parent.uri
        .resolve('Frameworks/cast_remux.framework/cast_remux')
        .toFilePath(),
  'windows' => 'cast_remux.dll',
  'linux' || 'android' => 'libcast_remux.so',
  _ => throw UnsupportedError(
    'No remux library packaged for ${operatingSystem ?? Platform.operatingSystem}',
  ),
};
