# macOS Example

This directory contains a sample macOS application demonstrating Vigil integration.

> **Note:** A complete working test application is available at `TestApp/` in the repository root. It includes a Makefile-based build system that demonstrates the full integration including XPC service bundling, code signing, and entitlements.

## Structure

```
macOS/
├── VigilDemo/
│   ├── VigilDemo.xcodeproj
│   ├── VigilDemo/
│   │   ├── AppDelegate.m
│   │   ├── ViewController.m
│   │   └── Info.plist
│   └── VigilDemoValidator/       # XPC Service
│       ├── main.m
│       ├── ValidatorService.m
│       └── Info.plist
└── README.md
```

## Building

1. Open `VigilDemo.xcodeproj` in Xcode
2. Select the `VigilDemo` scheme
3. Build and run (Cmd+R)

## Integration Points

The example demonstrates:

- Vigil initialization on app launch
- Periodic validation during runtime
- Handling validation failures
- XPC Service validator setup

## Requirements

- macOS 11.0+
- Xcode 14.0+
- Valid code signing identity (for Secure Enclave access)

## Notes

For testing on development machines, you may need to:

1. Enable "Hardened Runtime" capability
2. Add "Keychain Access Groups" entitlement
3. Configure App Groups for shared Keychain access

See the [Integration Guide](../../Documentation/INTEGRATION.md) for detailed setup instructions.
