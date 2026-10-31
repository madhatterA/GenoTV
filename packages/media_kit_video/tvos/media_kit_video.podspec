Pod::Spec.new do |s|
  s.name             = 'media_kit_video'
  s.version          = '0.0.1'
  s.summary          = 'package:media_kit video plugin entry for tvOS (registration only).'
  s.description      = 'Video renders through video_surface on tvOS; no texture path.'
  s.homepage         = 'https://github.com/media-kit/media-kit.git'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Hitesh Kumar Saini' => 'saini123hitesh@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift'
  # No Flutter CocoaPod on tvOS (it does not declare tvOS); Flutter.framework comes from the host Podfile's search path.
  s.xcconfig = { 'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/../Flutter"' }
  s.platform         = :tvos, '15.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
