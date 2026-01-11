Pod::Spec.new do |s|
  s.name             = 'Vigil'
  s.version          = '1.0.0'
  s.summary          = 'Hardware-backed runtime integrity validation for iOS and macOS'
  s.description      = <<-DESC
    Vigil is an open-source framework that provides cryptographically-verified
    runtime integrity checking using a two-process architecture. It detects
    binary tampering, code injection, and runtime manipulation attacks—all
    without requiring an internet connection or external server.

    Key features:
    - Offline-first design (no server required)
    - Two-process architecture (validator runs separately)
    - Secure Enclave integration (hardware-backed keys)
    - Mutual attestation (both sides verify each other)
    - Fail-closed security model
  DESC

  s.homepage         = 'https://github.com/nkhmelni/Vigil'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Vigil Contributors' => '@temprecipient' }
  s.source           = { :git => 'https://github.com/nkhmelni/Vigil.git', :tag => s.version.to_s }

  s.ios.deployment_target = '14.0'
  s.osx.deployment_target = '11.0'

  s.swift_versions = ['5.0', '5.5', '5.7', '5.9']

  s.source_files = 'Sources/Vigil/**/*.{h,m,mm,swift}'
  s.public_header_files = 'Sources/Vigil/include/**/*.h'

  s.frameworks = 'Security', 'Foundation'
  s.ios.frameworks = 'NetworkExtension'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++14',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'VIGIL_COCOAPODS=1'
  }

  s.subspec 'Core' do |core|
    core.source_files = 'Sources/Vigil/**/*.{h,m,mm,swift}'
    core.public_header_files = 'Sources/Vigil/include/**/*.h'
  end

  s.subspec 'Validator' do |validator|
    validator.dependency 'Vigil/Core'
    validator.source_files = 'Sources/VigilValidator/**/*.{h,m,mm,swift}'
  end

  s.default_subspecs = 'Core'

  s.test_spec 'Tests' do |test|
    test.source_files = 'Tests/VigilTests/**/*.{swift,m}'
    test.requires_app_host = true
  end
end
