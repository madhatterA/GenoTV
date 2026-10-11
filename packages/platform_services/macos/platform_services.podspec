Pod::Spec.new do |s|
  s.name             = 'platform_services'
  s.version          = '0.0.1'
  s.summary          = 'Cross-platform display, audio, HDR, and lifecycle services.'
  s.description      = 'Native capability and lifecycle services for the video player.'
  s.license          = { :type => 'MIT' }

  s.source           = { :path => '.' }
  s.source_files = 'platform_services/Sources/platform_services/**/*'

  s.resource_bundles = {'platform_services_privacy' => ['platform_services/Sources/platform_services/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
