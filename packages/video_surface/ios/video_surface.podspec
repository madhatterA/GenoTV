Pod::Spec.new do |s|
  s.name             = 'video_surface'
  s.version          = '0.0.1'
  s.summary          = 'Native video surface for media_kit players (iOS: mpv renders into an EDR CAMetalLayer).'
  s.description      = 'Hosts a CAMetalLayer view; mpv gpu-next renders through MoltenVK directly into it, VideoToolbox frames imported zero-copy.'
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'Metal', 'QuartzCore', 'UIKit'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
