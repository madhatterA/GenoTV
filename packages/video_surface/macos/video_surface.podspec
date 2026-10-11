#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint video_surface.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'video_surface'
  s.version          = '0.0.1'
  s.summary          = 'Native HDR-capable (EDR) video surface for media_kit players.'
  s.description      = <<-DESC
Hosts a CAMetalLayer that mpv renders into, for HDR output on macOS.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'video_surface/Sources/video_surface/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'video_surface_privacy' => ['video_surface/Sources/video_surface/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
