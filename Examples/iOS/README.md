# iOS Example

This directory contains a sample iOS application demonstrating Vigil integration.

## Structure

```
iOS/
├── VigilDemo/
│   ├── VigilDemo.xcodeproj
│   ├── VigilDemo/
│   │   ├── AppDelegate.m
│   │   ├── SceneDelegate.m
│   │   ├── ViewController.m
│   │   └── Info.plist
│   └── VigilFilter/              # Network Extension
│       ├── FilterDataProvider.m
│       └── Info.plist
└── README.md
```

## Building

1. Open `VigilDemo.xcodeproj` in Xcode
2. Select a physical device (Secure Enclave not available on simulator)
3. Configure code signing for both app and extension targets
4. Build and run (Cmd+R)

## Setup Requirements

### Network Extension Entitlement

You must request the Network Extension entitlement from Apple:

1. Go to developer.apple.com
2. Navigate to Certificates, Identifiers & Profiles
3. Edit your App ID and enable Network Extensions
4. Request Content Filter Provider capability

### First Launch

On first launch, the user must enable the Content Filter:

1. Go to Settings > General > VPN & Device Management
2. Tap on the Vigil content filter
3. Enable the filter

The example app includes UI to guide users through this process.

## Integration Points

The example demonstrates:

- Vigil initialization with Network Extension setup
- User guidance for enabling Content Filter
- Validation with proper timeout handling
- Handling validation failures gracefully

## Requirements

- iOS 14.0+
- Physical iOS device (not simulator)
- Xcode 14.0+
- Apple Developer Program membership
- Network Extension entitlement approval

See the [Integration Guide](../../Documentation/INTEGRATION.md) for detailed setup instructions.
