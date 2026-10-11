#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint transport.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'transport'
  s.version          = '0.0.1'
  s.summary          = 'Native transport engine bindings.'
  s.description      = 'Native transport engine bindings for macOS.'
  s.homepage         = 'https://github.com/madhatterA/GenoTV'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Transport maintainers' => 'maintainers@example.invalid' }

  s.source           = { :path => '.' }
  s.source_files = 'transport/Sources/transport/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'transport_privacy' => ['transport/Sources/transport/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'ARCHS' => 'arm64' }
  s.user_target_xcconfig = { 'ARCHS' => 'arm64' }
  s.vendored_libraries = 'libs/libtransport_lt_shim.dylib', 'libs/libtransport_aria2_shim.dylib'
  s.preserve_paths = '../src/lt_shim/*', '../tool/build_libtorrent_macos.sh', '../tool/macos_deps/*',
                        '../tool/build_libaria2_macos.sh', '../tool/aria2_resume_wakeup.patch',
                        '../ios/Classes/aria2_shim.*'
  s.script_phases = [{
    :name => 'Build libtorrent shim from source',
    :script => 'bash "${PODS_TARGET_SRCROOT}/../tool/build_libtorrent_macos.sh" "${DERIVED_FILE_DIR}/lt-shim"',
    :execution_position => :before_compile,
    :input_files => ['${PODS_TARGET_SRCROOT}/../src/lt_shim/lt_shim.cpp',
                     '${PODS_TARGET_SRCROOT}/../src/lt_shim/lt_shim.h',
                     '${PODS_TARGET_SRCROOT}/../src/lt_shim/fs_shim.c',
                     '${PODS_TARGET_SRCROOT}/../src/lt_shim/CMakeLists.txt',
                     '${PODS_TARGET_SRCROOT}/../tool/build_libtorrent_macos.sh',
                     '${PODS_TARGET_SRCROOT}/../tool/macos_deps/CMakeLists.txt'],
    :output_files => ['${PODS_TARGET_SRCROOT}/libs/libtransport_lt_shim.dylib']
  },
  {
    :name => 'Build libaria2 shim from source',
    :script => 'bash "${PODS_TARGET_SRCROOT}/../tool/build_libaria2_macos.sh"',
    :execution_position => :before_compile,
    :input_files => ['${PODS_TARGET_SRCROOT}/../tool/aria2_resume_wakeup.patch',
                     '${PODS_TARGET_SRCROOT}/../ios/Classes/aria2_shim.mm',
                     '${PODS_TARGET_SRCROOT}/../ios/Classes/aria2_shim.h',
                     '${PODS_TARGET_SRCROOT}/../tool/build_libaria2_macos.sh'],
    :output_files => ['${PODS_TARGET_SRCROOT}/libs/libtransport_aria2_shim.dylib']
  }]
  s.swift_version = '5.0'
end
