Pod::Spec.new do |s|
  s.name = 'cast'
  s.version = '0.0.1'
  s.summary = 'In-process stream-copy remux framework.'
  s.description = 'Pinned FFmpeg remuxing; local playback remains libmpv.'
  s.homepage = 'https://github.com/madhatterA/GenoTV'
  s.author = { 'video player' => 'noreply@example.invalid' }
  s.license = { :type => 'MIT' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64'
  }
  s.vendored_frameworks = 'libs/cast_remux.xcframework'
  raise 'cast: run tool/build_remux_ios.sh before pod install' unless
    File.directory?(File.join(__dir__, 'libs/cast_remux.xcframework'))
end
