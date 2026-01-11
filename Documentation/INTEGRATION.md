# Vigil Integration Guide

This guide walks through integrating Vigil into your iOS and macOS applications.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [macOS Integration](#macos-integration)
4. [iOS Integration](#ios-integration)
5. [Common Setup](#common-setup)
6. [Build Configuration](#build-configuration)
7. [Testing](#testing)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Development Environment

- Xcode 14.0 or later
- macOS 13.0 or later (for development)
- Physical iOS device for testing (Secure Enclave not available on simulators)

### Entitlements and Capabilities

#### macOS
- App Groups (for shared Keychain access)
- Hardened Runtime (recommended)

#### iOS
- App Groups
- Network Extension (Content Filter Provider)

### Apple Developer Program

- Active Apple Developer Program membership
- Network Extension entitlement (request from Apple for iOS)

---

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/user/vigil.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Packages → Enter repository URL.

### CocoaPods

```ruby
pod 'Vigil', '~> 1.0'
```

### Manual Integration

1. Clone the repository
2. Drag `Vigil.xcframework` into your project
3. Add to "Frameworks, Libraries, and Embedded Content"
4. Set "Embed" to "Embed & Sign"

---

## macOS Integration

### Step 1: Add the XPC Service Target

1. In Xcode, File → New → Target
2. Select "XPC Service"
3. Name it `VigilValidator`
4. Language: Objective-C or Swift

### Step 2: Configure the XPC Service

**Info.plist** for XPC Service:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleName</key>
    <string>VigilValidator</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>XPCService</key>
    <dict>
        <key>ServiceType</key>
        <string>Application</string>
    </dict>
</dict>
</plist>
```

### Step 3: Implement the Validator

**VigilValidatorProtocol.h:**

```objc
#import <Foundation/Foundation.h>

@protocol VigilValidatorProtocol <NSObject>

- (void)validateHash:(NSData *)hash
           signature:(NSData *)signature
           publicKey:(NSData *)publicKey
               nonce:(NSData *)nonce
           withReply:(void (^)(BOOL valid,
                               NSData *validatorHash,
                               NSData *responseSignature,
                               NSData *validatorPublicKey))reply;

- (void)exchangePublicKey:(NSData *)appPublicKey
                withReply:(void (^)(NSData *validatorPublicKey))reply;

@end
```

**VigilValidatorService.m:**

```objc
#import "VigilValidatorService.h"
#import <Vigil/HashEngine.h>
#import <Vigil/SEKeyManager.h>
#import <Vigil/AttestationStore.h>

@implementation VigilValidatorService

- (void)validateHash:(NSData *)hash
           signature:(NSData *)signature
           publicKey:(NSData *)publicKey
               nonce:(NSData *)nonce
           withReply:(void (^)(BOOL, NSData *, NSData *, NSData *))reply {

    SEKeyManager *keyManager = [SEKeyManager sharedManager];
    AttestationStore *store = [AttestationStore sharedStore];

    // Verify the app's signature
    NSMutableData *signedData = [hash mutableCopy];
    [signedData appendData:nonce];

    NSError *error;
    BOOL signatureValid = [keyManager verifySignature:signature
                                              forData:signedData
                                        withPublicKey:publicKey
                                                error:&error];
    if (!signatureValid) {
        reply(NO, nil, nil, nil);
        return;
    }

    // Verify the app's public key matches stored key
    NSData *storedAppKey = [store appPublicKey];
    if (storedAppKey && ![storedAppKey isEqualToData:publicKey]) {
        reply(NO, nil, nil, nil);
        return;
    }

    // Verify hash matches expected value
    NSData *expectedHash = [self loadExpectedAppHash];
    BOOL hashValid = [hash isEqualToData:expectedHash];

    // Compute our own hash
    NSData *validatorHash = [HashEngine computeTextHash];

    // Sign the response
    NSMutableData *responseData = [NSMutableData data];
    [responseData appendBytes:&hashValid length:sizeof(BOOL)];
    [responseData appendData:validatorHash];
    [responseData appendData:nonce];

    NSData *responseSignature = [keyManager signData:responseData
                                          withKeyTag:@"com.vigil.validator"
                                               error:&error];

    NSData *validatorPublicKey = [keyManager publicKeyDataForTag:@"com.vigil.validator"];

    reply(hashValid, validatorHash, responseSignature, validatorPublicKey);
}

- (void)exchangePublicKey:(NSData *)appPublicKey
                withReply:(void (^)(NSData *))reply {

    AttestationStore *store = [AttestationStore sharedStore];
    [store storeAppPublicKey:appPublicKey error:nil];

    SEKeyManager *keyManager = [SEKeyManager sharedManager];
    NSData *validatorPublicKey = [keyManager publicKeyDataForTag:@"com.vigil.validator"];

    reply(validatorPublicKey);
}

- (NSData *)loadExpectedAppHash {
    // Load from embedded plist (generated at build time)
    NSString *path = [[NSBundle mainBundle]
        pathForResource:@"ExpectedHashes" ofType:@"plist"];
    NSDictionary *hashes = [NSDictionary dictionaryWithContentsOfFile:path];
    NSString *hexHash = hashes[@"app_text_hash"];
    return [self dataFromHexString:hexHash];
}

@end
```

**main.m for XPC Service:**

```objc
#import <Foundation/Foundation.h>
#import "VigilValidatorService.h"
#import "VigilValidatorProtocol.h"

@interface ServiceDelegate : NSObject <NSXPCListenerDelegate>
@end

@implementation ServiceDelegate

- (BOOL)listener:(NSXPCListener *)listener
    shouldAcceptNewConnection:(NSXPCConnection *)connection {

    connection.exportedInterface = [NSXPCInterface
        interfaceWithProtocol:@protocol(VigilValidatorProtocol)];
    connection.exportedObject = [[VigilValidatorService alloc] init];
    [connection resume];
    return YES;
}

@end

int main(int argc, const char *argv[]) {
    ServiceDelegate *delegate = [[ServiceDelegate alloc] init];
    NSXPCListener *listener = [NSXPCListener serviceListener];
    listener.delegate = delegate;
    [listener resume];
    return 0;
}
```

### Step 4: Configure App Groups

Both the app and XPC service must share an App Group for Keychain access:

1. In Xcode, select your app target
2. Signing & Capabilities → + Capability → App Groups
3. Add a group: `group.com.yourteam.vigil`
4. Repeat for the XPC Service target

### Step 5: Integrate in Your App

```objc
#import <Vigil/Vigil.h>

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Initialize Vigil on launch
    [Vigil initializeWithCompletion:^(BOOL success, NSError *error) {
        if (!success) {
            NSLog(@"Vigil initialization failed: %@", error);
            // Handle initialization failure
            return;
        }

        // Perform initial validation
        [self validateIntegrity];
    }];
}

- (void)validateIntegrity {
    [Vigil validateWithTimeout:5.0 completion:^(VigilResult result) {
        switch (result) {
            case VigilResultValid:
                NSLog(@"Integrity verified");
                break;

            case VigilResultTampered:
                NSLog(@"Tampering detected!");
                [self handleTampering];
                break;

            case VigilResultTimeout:
                NSLog(@"Validator unresponsive - assuming compromise");
                [self handleTampering];
                break;

            case VigilResultError:
                NSLog(@"Validation error");
                // Retry or handle gracefully
                break;
        }
    }];
}

- (void)handleTampering {
    // Options:
    // 1. Terminate the app
    // 2. Disable sensitive features
    // 3. Log to analytics
    // 4. Show warning to user
    exit(1);
}
```

---

## iOS Integration

### Step 1: Request Network Extension Entitlement

Network Extension requires approval from Apple:

1. Go to developer.apple.com
2. Account → Certificates, Identifiers & Profiles
3. Identifiers → Your App ID → Edit
4. Enable "Network Extensions"
5. Request the Content Filter Provider capability

This may take several days for Apple to approve.

### Step 2: Add the Network Extension Target

1. In Xcode, File → New → Target
2. Select "Content Filter Extension" (under Network Extension)
3. Name it `VigilFilter`
4. Language: Objective-C or Swift

### Step 3: Configure the Extension

**Info.plist** for Extension:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.networkextension.filter-data</string>
    <key>NSExtensionPrincipalClass</key>
    <string>FilterDataProvider</string>
</dict>

<key>NEProviderClasses</key>
<dict>
    <key>com.apple.networkextension.filter-data</key>
    <string>$(PRODUCT_MODULE_NAME).FilterDataProvider</string>
</dict>
```

**Entitlements** for Extension:

```xml
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>content-filter-provider</string>
</array>
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.yourteam.vigil</string>
</array>
```

### Step 4: Implement the Filter Provider

**FilterDataProvider.m:**

```objc
#import "FilterDataProvider.h"
#import <Vigil/HashEngine.h>
#import <Vigil/SEKeyManager.h>
#import <Vigil/AttestationStore.h>

@implementation FilterDataProvider

- (void)startFilterWithCompletionHandler:(void (^)(NSError *))completionHandler {
    // Initialize SE key if needed
    SEKeyManager *keyManager = [SEKeyManager sharedManager];
    if (![keyManager publicKeyDataForTag:@"com.vigil.filter"]) {
        [keyManager generateKeyPairWithTag:@"com.vigil.filter" error:nil];
    }

    // Allow all traffic - we're only using this for the IPC channel
    NEFilterSettings *settings = [[NEFilterSettings alloc]
        initWithRules:@[]
        defaultAction:[NEFilterRule ruleWithNetworkRule:
            [[NENetworkRule alloc] initWithRemoteNetwork:nil
                                           remotePrefix:0
                                            localNetwork:nil
                                             localPrefix:0
                                                protocol:NENetworkRuleProtocolAny
                                               direction:NETrafficDirectionAny]]];

    [self applySettings:settings completionHandler:^(NSError *error) {
        completionHandler(error);
    }];
}

- (void)handleNewFlow:(NEFilterFlow *)flow {
    // Allow all flows - we're not actually filtering
    [flow setValue:@(NEFilterDataVerdictAllow)
            forKey:@"verdict"];
}

#pragma mark - Vigil IPC

- (void)handleAppMessage:(NSData *)messageData
       completionHandler:(void (^)(NSData *))completionHandler {

    // Decode the validation request
    NSError *error;
    NSDictionary *request = [NSJSONSerialization JSONObjectWithData:messageData
                                                            options:0
                                                              error:&error];
    if (error) {
        completionHandler(nil);
        return;
    }

    NSString *action = request[@"action"];

    if ([action isEqualToString:@"validate"]) {
        [self handleValidation:request completion:completionHandler];
    } else if ([action isEqualToString:@"exchangeKey"]) {
        [self handleKeyExchange:request completion:completionHandler];
    } else {
        completionHandler(nil);
    }
}

- (void)handleValidation:(NSDictionary *)request
              completion:(void (^)(NSData *))completion {

    NSData *hash = [[NSData alloc] initWithBase64EncodedString:request[@"hash"]
                                                       options:0];
    NSData *signature = [[NSData alloc] initWithBase64EncodedString:request[@"signature"]
                                                            options:0];
    NSData *publicKey = [[NSData alloc] initWithBase64EncodedString:request[@"publicKey"]
                                                            options:0];
    NSData *nonce = [[NSData alloc] initWithBase64EncodedString:request[@"nonce"]
                                                        options:0];

    SEKeyManager *keyManager = [SEKeyManager sharedManager];
    AttestationStore *store = [AttestationStore sharedStore];

    // Verify signature
    NSMutableData *signedData = [hash mutableCopy];
    [signedData appendData:nonce];

    BOOL signatureValid = [keyManager verifySignature:signature
                                              forData:signedData
                                        withPublicKey:publicKey
                                                error:nil];
    if (!signatureValid) {
        NSDictionary *response = @{@"valid": @NO};
        completion([NSJSONSerialization dataWithJSONObject:response
                                                   options:0 error:nil]);
        return;
    }

    // Verify stored key
    NSData *storedKey = [store appPublicKey];
    if (storedKey && ![storedKey isEqualToData:publicKey]) {
        NSDictionary *response = @{@"valid": @NO};
        completion([NSJSONSerialization dataWithJSONObject:response
                                                   options:0 error:nil]);
        return;
    }

    // Verify hash
    NSData *expectedHash = [self loadExpectedAppHash];
    BOOL hashValid = [hash isEqualToData:expectedHash];

    // Compute our hash
    NSData *filterHash = [HashEngine computeTextHash];

    // Sign response
    NSMutableData *responseData = [NSMutableData data];
    uint8_t validByte = hashValid ? 1 : 0;
    [responseData appendBytes:&validByte length:1];
    [responseData appendData:filterHash];
    [responseData appendData:nonce];

    NSData *responseSignature = [keyManager signData:responseData
                                          withKeyTag:@"com.vigil.filter"
                                               error:nil];
    NSData *filterPublicKey = [keyManager publicKeyDataForTag:@"com.vigil.filter"];

    NSDictionary *response = @{
        @"valid": @(hashValid),
        @"filterHash": [filterHash base64EncodedStringWithOptions:0],
        @"signature": [responseSignature base64EncodedStringWithOptions:0],
        @"publicKey": [filterPublicKey base64EncodedStringWithOptions:0]
    };

    completion([NSJSONSerialization dataWithJSONObject:response
                                               options:0 error:nil]);
}

@end
```

### Step 5: Configure App for Network Extension

**App's Entitlements:**

```xml
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>content-filter-provider</string>
</array>
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.yourteam.vigil</string>
</array>
```

### Step 6: Enable the Filter (First Launch)

The user must enable the Content Filter in Settings. Provide UI to guide them:

```objc
#import <NetworkExtension/NetworkExtension.h>

- (void)setupContentFilter {
    [[NEFilterManager sharedManager] loadFromPreferencesWithCompletionHandler:
        ^(NSError *error) {
        if (error) {
            NSLog(@"Failed to load filter preferences: %@", error);
            return;
        }

        NEFilterManager *manager = [NEFilterManager sharedManager];

        if (!manager.enabled) {
            // Guide user to Settings
            [self showFilterSetupInstructions];
            return;
        }

        // Filter is enabled, proceed with validation
        [self validateIntegrity];
    }];
}

- (void)showFilterSetupInstructions {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Setup Required"
        message:@"To protect this app, please enable the content filter in "
                @"Settings > General > VPN & Device Management > Content Filter"
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"Open Settings"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            [[UIApplication sharedApplication] openURL:url
                                               options:@{}
                                     completionHandler:nil];
        }]];

    [self presentViewController:alert animated:YES completion:nil];
}
```

### Step 7: Validate in Your App

```objc
- (void)validateIntegrity {
    NEFilterManager *manager = [NEFilterManager sharedManager];

    // Prepare validation request
    NSData *hash = [HashEngine computeTextHash];
    NSData *nonce = [self generateNonce];

    SEKeyManager *keyManager = [SEKeyManager sharedManager];
    NSMutableData *signedData = [hash mutableCopy];
    [signedData appendData:nonce];
    NSData *signature = [keyManager signData:signedData
                                  withKeyTag:@"com.vigil.app"
                                       error:nil];
    NSData *publicKey = [keyManager publicKeyDataForTag:@"com.vigil.app"];

    NSDictionary *request = @{
        @"action": @"validate",
        @"hash": [hash base64EncodedStringWithOptions:0],
        @"signature": [signature base64EncodedStringWithOptions:0],
        @"publicKey": [publicKey base64EncodedStringWithOptions:0],
        @"nonce": [nonce base64EncodedStringWithOptions:0]
    };

    NSData *messageData = [NSJSONSerialization dataWithJSONObject:request
                                                          options:0
                                                            error:nil];

    // Set timeout
    __block BOOL responseReceived = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        if (!responseReceived) {
            [self handleValidationResult:VigilResultTimeout response:nil];
        }
    });

    // Send to filter extension
    NETunnelProviderSession *session =
        (NETunnelProviderSession *)manager.connection;

    [session sendProviderMessage:messageData
                 responseHandler:^(NSData *response) {
        responseReceived = YES;
        [self handleValidationResponse:response nonce:nonce];
    }];
}
```

---

## Common Setup

### Initialize Secure Enclave Keys

On first launch, generate SE key pairs for both app and validator:

```objc
// In app initialization
- (void)initializeVigilKeys {
    SEKeyManager *keyManager = [SEKeyManager sharedManager];

    // Check if keys exist
    if (![keyManager publicKeyDataForTag:@"com.vigil.app"]) {
        NSError *error;
        BOOL success = [keyManager generateKeyPairWithTag:@"com.vigil.app"
                                                    error:&error];
        if (!success) {
            NSLog(@"Failed to generate app SE key: %@", error);
            // Handle error - SE might not be available
        }
    }
}
```

### Key Exchange (First Launch)

```objc
- (void)performInitialKeyExchange {
    AttestationStore *store = [AttestationStore sharedStore];

    if ([store isAttestationConfigured]) {
        // Already configured
        return;
    }

    SEKeyManager *keyManager = [SEKeyManager sharedManager];
    NSData *appPublicKey = [keyManager publicKeyDataForTag:@"com.vigil.app"];

    // Send to validator and receive validator's public key
    // (Implementation depends on platform - XPC or NE)
    [self exchangeKeyWithValidator:appPublicKey
                        completion:^(NSData *validatorPublicKey) {
        [store storeValidatorPublicKey:validatorPublicKey error:nil];
    }];
}
```

---

## Build Configuration

### Build Phase Script

Add a Run Script phase to compute expected hashes:

```bash
#!/bin/bash

# Compute hash after linking, before signing
APP_BINARY="${BUILT_PRODUCTS_DIR}/${EXECUTABLE_PATH}"
OUTPUT_PLIST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/ExpectedHashes.plist"

if [ -f "$APP_BINARY" ]; then
    # Use vigil-hash-tool to compute __TEXT hash
    HASH=$("${SRCROOT}/Tools/vigil-hash-tool" --binary "$APP_BINARY")

    # Write to plist
    /usr/libexec/PlistBuddy -c "Add :app_text_hash string $HASH" "$OUTPUT_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :app_text_hash $HASH" "$OUTPUT_PLIST"

    echo "Computed app hash: $HASH"
fi
```

### Release vs Debug

In Debug builds, you may want to disable strict validation:

```objc
#ifdef DEBUG
#define VIGIL_STRICT_MODE 0
#else
#define VIGIL_STRICT_MODE 1
#endif

- (void)handleValidationResult:(VigilResult)result {
#if VIGIL_STRICT_MODE
    if (result != VigilResultValid) {
        [self handleTampering];
    }
#else
    // Log but don't enforce in debug builds
    if (result != VigilResultValid) {
        NSLog(@"[Vigil Debug] Validation failed: %ld", (long)result);
    }
#endif
}
```

---

## Testing

### Physical Device Testing

Secure Enclave requires a physical device:

```objc
// Check SE availability
if (![SEKeyManager isSecureEnclaveAvailable]) {
    // Running on simulator - use mock implementation
    return;
}
```

### Validation Testing

```objc
// Test valid state
[Vigil validateWithTimeout:5.0 completion:^(VigilResult result) {
    XCTAssertEqual(result, VigilResultValid);
}];

// Test timeout (stop validator before calling)
[Vigil validateWithTimeout:1.0 completion:^(VigilResult result) {
    XCTAssertEqual(result, VigilResultTimeout);
}];
```

---

## Troubleshooting

### Common Issues

#### "Secure Enclave not available"

- **Cause**: Running on simulator or unsupported device
- **Solution**: Test on physical device with Secure Enclave (iPhone 5s or later)

#### "XPC connection interrupted"

- **Cause**: XPC service crashed or bundle ID mismatch
- **Solution**: Verify bundle identifiers match, check Console.app for crash logs

#### "Network Extension not enabled"

- **Cause**: User hasn't enabled the Content Filter
- **Solution**: Guide user to Settings, check `NEFilterManager.enabled`

#### "Key not found"

- **Cause**: SE key generation failed or app was re-installed
- **Solution**: Regenerate keys and perform key exchange

#### "Hash mismatch"

- **Cause**: Binary was modified or ExpectedHashes.plist is stale
- **Solution**: Rebuild with correct hash computation phase

### Debug Logging

Enable verbose logging:

```objc
[Vigil setLogLevel:VigilLogLevelDebug];
```

Check Console.app for logs with subsystem `com.vigil`.
