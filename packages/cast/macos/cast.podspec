require 'rbconfig'
remux_arch = RbConfig::CONFIG['host_cpu']
remux_arch = 'arm64' if remux_arch == 'aarch64'
Pod::Spec.new do |s|
  s.name             = 'cast'
  s.version          = '0.0.1'
  s.summary          = 'AirPlay session (AVPlayer) and system route picker for casting.'
  s.description      = 'AVPlayer is used only for AirPlay sessions; mpv stays the local engine.'
  s.homepage         = 'https://example.invalid/video-player'
  s.author           = { 'video player' => 'noreply@example.invalid' }
  s.license          = { :type => 'MIT' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
  s.vendored_libraries = 'libs/libcast_remux.dylib'
  s.preserve_paths = 'libs/libcast_remux.dylib'
  s.script_phases = [{
    :name => 'Build stream-copy remux library from pinned FFmpeg',
    :script => "bash \"${PODS_TARGET_SRCROOT}/../tool/build_remux.sh\" #{remux_arch}",
    :execution_position => :before_compile,
    :input_files => ['${PODS_TARGET_SRCROOT}/../native/remux/remux.c',
                     '${PODS_TARGET_SRCROOT}/../native/remux/remux.h',
                     '${PODS_TARGET_SRCROOT}/../tool/build_remux.sh',
                     '${PODS_TARGET_SRCROOT}/../tool/build_ffmpeg.sh'],
    :output_files => ['${PODS_TARGET_SRCROOT}/libs/libcast_remux.dylib']
  }]
end
