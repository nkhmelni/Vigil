# Changelog

All notable changes to Vigil will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Continuous monitoring mode with configurable intervals
- SwiftUI property wrappers for declarative validation
- Behavioral attestation module
- Remote attestation mode (optional server validation)

---

## [1.0.0] - 2025-01-11

### Added
- Initial release of Vigil framework
- Core integrity validation with __TEXT segment hashing
- Two-process architecture for enhanced security
  - macOS: XPC Service validator
  - iOS: Network Extension (Content Filter) validator
- Secure Enclave integration
  - Hardware-backed ECDSA P-256 key pairs
  - Keys bound to code signing identity (Team ID)
  - Non-exportable private keys
- Mutual attestation protocol
  - Challenge-response with cryptographic nonces
  - Both app and validator verify each other
  - Fail-closed security model
- Offline-first design (no server required)
- Comprehensive attack detection
  - Binary patching detection via hash verification
  - DYLD injection detection
  - Re-signing attack prevention via SE key binding
  - Hooking framework detection (Frida, Substrate, fishhook, Dobby)
- Platform support
  - iOS 14.0+
  - macOS 11.0+
  - Apple Silicon and Intel support
- Integration options
  - Swift Package Manager
  - CocoaPods
  - Manual framework integration
- Swift and Objective-C APIs
- Async/await support for Swift
- Comprehensive documentation
  - Architecture deep-dive
  - Security model and threat analysis
  - Integration guides for both platforms
  - Complete API reference

### Security
- All cryptographic operations use Apple Security framework
- Secure Enclave operations never expose private keys
- Constant-time signature verification
- Nonce-based replay attack prevention
- Timeout-based fail-closed validation

### Known Limitations
- Secure Enclave not available on simulators (use physical devices for testing)
- iOS Network Extension requires user to enable Content Filter in Settings
- Build-time hash computation requires two-pass build process
- Does not protect against kernel-level attacks on jailbroken devices

---

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 1.0.0 | 2025-01-11 | Initial release |

---

## Upgrade Guide

### From Pre-release to 1.0.0

If you were using a pre-release version:

1. Remove old framework references
2. Add Vigil via Swift Package Manager or CocoaPods
3. Update import statements to `import Vigil`
4. Replace deprecated API calls (see migration guide below)

### API Migration

```diff
- #import <VigilCore/VigilCore.h>
+ #import <Vigil/Vigil.h>

- [VigilCore validateIntegrity:completion]
+ [Vigil validateWithCompletion:completion]

- VigilStatusValid
+ VigilResultValid
```

---

[Unreleased]: https://github.com/nkhmelni/Vigil/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/nkhmelni/Vigil/releases/tag/v1.0.0
