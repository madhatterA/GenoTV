#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint transport.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'transport'
  s.version          = '0.0.1'
  s.summary          = 'Native transport engine bindings.'
  s.description      = 'libtorrent and libaria2 transport bindings for Flutter.'
  s.static_framework = true
  s.homepage         = 'https://github.com/madhatterA/GenoTV'
  s.license          = { :type => 'BSD-3-Clause' }
  s.author           = { 'Transport maintainers' => 'maintainers@example.invalid' }
  s.source           = { :path => '.' }
  # lt_shim.cpp is the same shared C++ libtorrent shim Android compiles into
  # libtransport_lt_shim.so (packages/transport/android/CMakeLists.txt) and
  # macOS links as a standalone dylib (packages/transport/tool/LT_BUILD.md).
  # On iOS it is compiled directly into this pod, alongside the aria2 .mm
  # glue, and force-linked into the app the same way aria2 already is below.
  s.source_files = 'transport/Sources/transport/**/*', 'Classes/**/*.{h,mm}', 'lt_shim.{h,cpp}', 'fs_shim.c'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  # aria2's AppleTLS backend and the static archive's zlib/sqlite users are
  # resolved by the application link. Keep these explicit so simulator and
  # device links cannot accidentally rely on transitive host settings.
  s.frameworks = 'Security', 'CoreFoundation', 'SystemConfiguration'
  s.libraries = 'z', 'sqlite3', 'c++'

  # The build script publishes checksum-pinned Boost headers with the slices.
  boost_include = '$(PODS_TARGET_SRCROOT)/libs/libtorrent/boost/include'
  raise 'transport: run tool/build_libtorrent_ios.sh for pinned Boost headers' unless
    File.exist?(File.join(__dir__, 'libs/libtorrent/boost/include/boost/version.hpp'))

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) TORRENT_USE_RTC=0 TORRENT_ABI_VERSION=2 TORRENT_DISABLE_ENCRYPTION BOOST_ASIO_NO_DEPRECATED BOOST_ASIO_HAS_STD_CHRONO BOOST_ASIO_ENABLE_CANCELIO BOOST_EXCEPTION_DISABLE BOOST_SYSTEM_USE_UTF8',
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/libs/libaria2/include',
    'HEADER_SEARCH_PATHS[sdk=iphoneos*]' => '$(inherited) "$(PODS_TARGET_SRCROOT)/libs/libtorrent/libtorrent.xcframework/ios-arm64/Headers" "' + boost_include + '"',
    'HEADER_SEARCH_PATHS[sdk=iphonesimulator*]' => '$(inherited) "$(PODS_TARGET_SRCROOT)/libs/libtorrent/libtorrent.xcframework/ios-arm64-simulator/Headers" "' + boost_include + '"',
    'LIBRARY_SEARCH_PATHS[sdk=iphoneos*]' => '$(inherited) "$(PODS_TARGET_SRCROOT)/libs/libaria2/libaria2.xcframework/ios-arm64"',
    'LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]' => '$(inherited) "$(PODS_TARGET_SRCROOT)/libs/libaria2/libaria2.xcframework/ios-arm64-simulator"',
    'OTHER_LDFLAGS[sdk=iphoneos*]' => '$(inherited) "$(PODS_TARGET_SRCROOT)/libs/libtorrent/libtorrent.xcframework/ios-arm64/libtorrent-rasterbar.a"',
    'OTHER_LDFLAGS[sdk=iphonesimulator*]' => '$(inherited) "$(PODS_TARGET_SRCROOT)/libs/libtorrent/libtorrent.xcframework/ios-arm64-simulator/libtorrent-rasterbar.a"'
  }
  # Flutter links this plugin as a static pod. Propagate aria2's simulator and
  # device slices to the final application link as well as the pod target.
  # The libtorrent shim's transport_lt_* symbols are force-retained here the
  # same way aria2's transport_aria2_* symbols already are: this is a static
  # archive with no Objective-C class/category referencing it, so nothing
  # else keeps the linker from dead-stripping the whole libtorrent-rasterbar.a
  # archive (this was the original defect -- see bug_history.md).
  aria2_user_root = '$(PODS_ROOT)/../.symlinks/plugins/transport/ios/libs/libaria2'
  lt_symbols = %w[
    transport_lt_session_create transport_lt_session_destroy transport_lt_session_last_error
    transport_lt_add_magnet transport_lt_add_torrent transport_lt_load_resume
    transport_lt_torrent_remove transport_lt_torrent_close transport_lt_torrent_close_complete
    transport_lt_torrent_metadata_ready transport_lt_torrent_file_count
    transport_lt_torrent_piece_length transport_lt_torrent_piece_count
    transport_lt_torrent_info_hash transport_lt_torrent_file_info
    transport_lt_torrent_piece_available transport_lt_torrent_copy_piece_bitfield
    transport_lt_torrent_read transport_lt_torrent_prioritize_files
    transport_lt_torrent_file_priority transport_lt_torrent_set_piece_priority
    transport_lt_torrent_set_piece_deadline transport_lt_torrent_clear_piece_deadlines
    transport_lt_torrent_status transport_lt_pop_alerts transport_lt_torrent_save_resume
    transport_lt_torrent_load_resume
  ]
  lt_retain_flags = lt_symbols.map { |sym| '-Wl,-u,_' + sym }.join(' ')
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'LIBRARY_SEARCH_PATHS[sdk=iphoneos*]' => '$(inherited) "' + aria2_user_root + '/libaria2.xcframework/ios-arm64"',
    'LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]' => '$(inherited) "' + aria2_user_root + '/libaria2.xcframework/ios-arm64-simulator"',
    'OTHER_LDFLAGS' => '$(inherited) -l"aria2" -Wl,-u,_transport_aria2_create -Wl,-u,_transport_aria2_destroy -Wl,-u,_transport_aria2_last_error -Wl,-u,_transport_aria2_add_uri -Wl,-u,_transport_aria2_poll -Wl,-u,_transport_aria2_status -Wl,-u,_transport_aria2_change_option -Wl,-u,_transport_aria2_remove -Wl,-u,_transport_aria2_set_paused ' + lt_retain_flags
  }
  s.swift_version = '5.0'

  # Run tool/build_libaria2_ios.sh before an iOS archive. The conditional keeps
  # package-local analyzer runs usable before the generated native artifact is
  # built, while linking the real static libaria2 whenever it is present.
  aria2_prefix = File.join(__dir__, 'libs/libaria2')
  aria2_xcframework = File.join(aria2_prefix, 'libaria2.xcframework')
  raise 'transport: missing pinned libaria2.xcframework; run tool/build_libaria2_ios.sh' unless File.exist?(aria2_xcframework)
  libtorrent_framework = File.join(__dir__, 'libs/libtorrent/libtorrent.xcframework')
  raise 'transport: missing pinned libtorrent.xcframework' unless File.exist?(libtorrent_framework)
  s.vendored_frameworks = 'libs/libaria2/libaria2.xcframework', 'libs/libtorrent/libtorrent.xcframework'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'transport_privacy' => ['transport/Sources/transport/PrivacyInfo.xcprivacy']}
end
