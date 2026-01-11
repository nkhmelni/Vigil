# Vigil

**Hardware-backed runtime integrity validation for iOS and macOS.**

Vigil is an open-source framework that provides cryptographically-verified runtime integrity checking using a two-process architecture. It detects binary tampering, code injection, and runtime manipulation attacks—all without requiring an internet connection or external server.

## Key Features

- **Offline-First**: All validation happens locally on-device. No server infrastructure required.
- **Two-Process Architecture**: Validator runs as a separate process, making single-binary attacks ineffective.
- **Secure Enclave Integration**: Cryptographic operations use hardware-backed keys bound to your code signing identity.
- **Mutual Attestation**: Both app and validator verify each other—compromise of either is detected.
- **Fail-Closed Security**: If the validator doesn't respond, assume compromise.
- **Cross-Platform**: Unified API for iOS and macOS with platform-optimized implementations.

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                         YOUR APP                                │
│                                                                 │
│   1. Compute __TEXT hash ──────────────────────┐                │
│   2. Sign hash with SE key                     │                │
│   3. Send to validator ─────────────────────►  │                │
│                                                ▼                │
│                                    ┌───────────────────┐        │
│                                    │    VALIDATOR      │        │
│                                    │                   │        │
│   6. Verify validator response ◄── │ 4. Verify hash    │        │
│   7. Continue or terminate         │ 5. Sign response  │        │
│                                    └───────────────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Installation

**Swift Package Manager:**
```swift
dependencies: [
    .package(url: "https://github.com/user/vigil.git", from: "1.0.0")
]
```

### Basic Usage

```objc
#import <Vigil/Vigil.h>

// Validate integrity with 5-second timeout
[Vigil validateWithTimeout:5.0 completion:^(VigilResult result) {
    switch (result) {
        case VigilResultValid:
            // App integrity verified
            break;
        case VigilResultTampered:
            // Tampering detected - take action
            break;
        case VigilResultTimeout:
            // Validator unresponsive - assume compromised
            break;
    }
}];
```

```swift
// Swift
Vigil.validate(timeout: 5.0) { result in
    switch result {
    case .valid:
        // App integrity verified
    case .tampered:
        // Tampering detected
    case .timeout:
        // Validator unresponsive
    }
}
```

## Platform Requirements

| Platform | Minimum Version | Validator Type |
|----------|-----------------|----------------|
| iOS      | 14.0+           | Network Extension (Content Filter) |
| macOS    | 11.0+           | XPC Service |

## Why Vigil?

### vs. Apple App Attest
| Feature | Vigil | App Attest |
|---------|-------|------------|
| Offline operation | Yes | No (requires Apple servers) |
| Server infrastructure | Not needed | Required for validation |
| Runtime verification | Yes | Initial attestation only |
| Open source | Yes | No |

### vs. In-App Integrity Checks
| Feature | Vigil | In-App Only |
|---------|-------|-------------|
| Process isolation | Yes (two processes) | No |
| Single-binary bypass | Protected | Vulnerable |
| Hardware-backed keys | Secure Enclave | Optional |
| Mutual attestation | Yes | N/A |

### vs. Commercial RASP Solutions
| Feature | Vigil | Commercial RASP |
|---------|-------|-----------------|
| Open source | Yes | Typically no |
| Audit-able security | Yes | Black box |
| Cost | Free | Licensed |
| Process isolation | Yes | Usually no |

## Documentation

- [Architecture](./ARCHITECTURE.md) - Deep dive into design decisions
- [Security Model](./SECURITY.md) - Threat model and mitigations
- [Integration Guide](./INTEGRATION.md) - Step-by-step setup
- [API Reference](./API.md) - Complete API documentation

## Security Considerations

Vigil significantly raises the bar for attackers but is not impenetrable. It protects against:
- Binary patching
- DYLD injection
- Common hooking frameworks (Frida, Substrate, fishhook)
- Runtime memory modification
- App re-signing attacks

It does **not** protect against:
- Kernel-level attacks on jailbroken devices
- Hardware-based attacks
- Sophisticated attackers with physical device access and unlimited time

See [SECURITY.md](./SECURITY.md) for the complete threat model.

## License

MIT License. See [LICENSE](./LICENSE) for details.

## Contributing

Contributions welcome. Please read [CONTRIBUTING.md](./CONTRIBUTING.md) before submitting PRs.
