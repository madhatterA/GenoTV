Pod::Spec.new do |s|
  s.name             = 'media_kit_libs_tvos_video'
  s.version          = '1.0.0'
  s.summary          = 'tvOS libmpv (Metal) for package:media_kit'
  s.description      = 'tvOS libmpv/FFmpeg xcframeworks built by packages/playback/tool/build_libmpv_ios_metal.sh (LIBMPV_PLATFORM=tvos).'
  s.homepage         = 'https://github.com/media-kit/media-kit.git'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'media-kit' => 'noreply@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.xcconfig = { 'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/../Flutter"' }
  s.vendored_frameworks = 'Frameworks/*.xcframework'
  s.tvos.deployment_target = '15.0'
  s.swift_version = '5.0'
end
