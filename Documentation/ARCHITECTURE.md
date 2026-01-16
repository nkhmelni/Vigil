# Vigil Architecture

This document describes Vigil's internal architecture, design decisions, and the reasoning behind platform-specific implementations.

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [Core Components](#core-components)
3. [Platform Implementations](#platform-implementations)
4. [IPC Mechanism Analysis](#ipc-mechanism-analysis)
5. [Cryptographic Design](#cryptographic-design)
6. [Validation Protocol](#validation-protocol)
7. [Build-Time Integration](#build-time-integration)

---

## Design Philosophy

### Why Two Processes?

Single-process integrity checks have a fundamental weakness: an attacker who can modify one part of the binary can modify the integrity check itself. The check and the checked code share the same fate.

Vigil uses two separate processes:

```
┌────────────────────┐         ┌────────────────────┐
│     HOST APP       │   IPC   │     VALIDATOR      │
│                    │◄───────►│                    │
│  Can be attacked   │         │  Must ALSO be      │
│  independently     │         │  attacked          │
└────────────────────┘         └────────────────────┘
```

**Security Property**: An attacker must compromise BOTH binaries to bypass validation. If either process is untampered, it will detect tampering in the other.

### Why Offline?

Apple's App Attest requires server-side validation, creating several problems:

1. **Infrastructure Cost**: Developers must run validation servers
2. **Availability Dependency**: Network issues cause false positives
3. **Latency**: Network round-trips add delay to security checks
4. **Privacy**: Validation events are observable to network adversaries

Vigil's offline design eliminates all of these concerns.

### Why Secure Enclave?

Software-only cryptographic keys can be extracted through memory inspection or binary analysis. Secure Enclave keys:

- Never leave the hardware security module
- Cannot be exported, even by the app that created them
- Are bound to the device and code signing identity
- Require the original team ID to access—re-signed apps lose access

---

## Core Components

### Component Overview

```
vigil/
├── Shared/
│   ├── VigilProtocol.h          # IPC message format
│   ├── HashEngine.h/.m          # __TEXT segment hashing
│   ├── SEKeyManager.h/.m        # Secure Enclave operations
│   └── AttestationStore.h/.m    # Public key storage
├── Client/
│   ├── Vigil.h/.m               # Public API
│   ├── VigilClient.h/.m         # IPC client logic
│   └── Platform/
│       ├── VigilClient+XPC.m    # macOS XPC implementation
│       └── VigilClient+NE.m     # iOS Network Extension implementation
└── Validator/
    ├── macOS/
    │   └── VigilXPCService/     # XPC Service bundle
    └── iOS/
        └── VigilFilterExtension/ # NEFilterDataProvider
```

### HashEngine

Computes SHA-256 hash of the `__TEXT` segment of all in-bundle Mach-O binaries.

```objc
@interface HashEngine : NSObject

/// Compute hash of current process's __TEXT segments
+ (NSData *)computeTextHash;

/// Compute hash of specific binary at path
+ (NSData *)computeTextHashForPath:(NSString *)path;

/// Combine multiple hashes into single digest
+ (NSData *)combineHashes:(NSArray<NSData *> *)hashes;

@end
```

**Why __TEXT?**

The `__TEXT` segment contains executable code and is:
- Read-only at runtime (enforced by the kernel)
- Not modified by ASLR (slide is applied to addresses, not content)
- The primary target of binary patching attacks

Other segments (`__DATA`, `__LINKEDIT`) are mutable and cannot be reliably hashed.

**Hash Determinism:**

The __TEXT hash exhibits these properties:
- **Same binary = Same hash**: Running the same binary produces identical hashes across multiple executions
- **Code change = Different hash**: Modifying even a single line of code produces a completely different hash
- **Rebuild = Different hash**: Rebuilding the same source code typically produces a different hash due to build non-determinism (timestamps, UUIDs, etc.)

This means expected hashes must be computed from the actual built binary, not from source code.

**Implementation Notes:**

```objc
// Iterate all images in the bundle
for (DynamicImage image : bundleImages) {
    const struct mach_header_64 *header = image.header;

    // Find __TEXT segment
    struct load_command *lc = firstLoadCommand(header);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)lc;
            if (strcmp(seg->segname, SEG_TEXT) == 0) {
                // Hash the segment content
                CC_SHA256_Update(&ctx, segmentData, segmentSize);
            }
        }
        lc = nextLoadCommand(lc);
    }
}
```

### SEKeyManager

Manages Secure Enclave key pairs for signing and verification.

```objc
@interface SEKeyManager : NSObject

/// Generate a new SE key pair with the given tag
/// Returns NO if key already exists or SE unavailable
- (BOOL)generateKeyPairWithTag:(NSString *)tag error:(NSError **)error;

/// Get public key data for a tag (for sharing with validator)
- (NSData *)publicKeyDataForTag:(NSString *)tag;

/// Sign data using the SE private key
- (NSData *)signData:(NSData *)data
          withKeyTag:(NSString *)tag
               error:(NSError **)error;

/// Verify signature using a public key
- (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
          withPublicKey:(NSData *)publicKey
                  error:(NSError **)error;

/// Check if Secure Enclave is available
+ (BOOL)isSecureEnclaveAvailable;

@end
```

**Key Generation:**

```objc
NSDictionary *attributes = @{
    (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
    (id)kSecAttrKeySizeInBits: @256,
    (id)kSecAttrTokenID: (id)kSecAttrTokenIDSecureEnclave,
    (id)kSecPrivateKeyAttrs: @{
        (id)kSecAttrIsPermanent: @YES,
        (id)kSecAttrApplicationTag: tagData,
        (id)kSecAttrAccessControl: accessControl
    }
};

SecKeyRef privateKey = SecKeyCreateRandomKey(
    (__bridge CFDictionaryRef)attributes, &error);
```

**Access Control:**

Keys are created with `kSecAccessControlPrivateKeyUsage`, which means:
- Signing operations happen inside the Secure Enclave
- Private key material never enters main memory
- Operations may require biometric authentication (configurable)

**Secure Enclave Availability:**

On devices with Secure Enclave (most modern Apple devices), keys are generated in hardware. On devices without Secure Enclave (simulators, older Macs), the key manager automatically falls back to software-based keys. This allows development and testing while maintaining hardware security in production.

Logs indicate key storage location:
- `"Key generated in SECURE ENCLAVE"` - Hardware-backed key
- `"Using SOFTWARE key"` - Software fallback (less secure)

### AttestationStore

Stores exchanged public keys for mutual verification.

```objc
@interface AttestationStore : NSObject

/// Store the validator's public key (called during initial setup)
- (BOOL)storeValidatorPublicKey:(NSData *)publicKey error:(NSError **)error;

/// Store the app's public key (called by validator during setup)
- (BOOL)storeAppPublicKey:(NSData *)publicKey error:(NSError **)error;

/// Retrieve stored keys
- (NSData *)validatorPublicKey;
- (NSData *)appPublicKey;

/// Check if initial key exchange has occurred
- (BOOL)isAttestationConfigured;

@end
```

Keys are stored in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, ensuring:
- Keys persist across app launches
- Keys are device-specific (not backed up to iCloud)
- Keys require device unlock at least once after boot

---

## Platform Implementations

### Why Different IPC Mechanisms?

After extensive research, we determined that **no single IPC mechanism works identically on both iOS and macOS** while also supporting a persistent separate process.

| Mechanism | macOS | iOS | Persistent Process? |
|-----------|-------|-----|---------------------|
| XPC Services | Yes | Private API | Yes (macOS only) |
| Network Extension | Yes | Yes | Yes |
| CFMessagePort | Yes | Broken (iOS 16+) | Requires existing process |
| Unix Domain Sockets | Yes | Yes | Requires existing process |
| Darwin Notifications | Yes | Yes (no payload) | Requires existing process |
| Mach Ports + App Groups | Yes | Limited | Requires existing process |

The critical constraint on iOS is: **How do you run a second process?**

On macOS, XPC Services are bundled with the app and launched on-demand by launchd. On iOS, the only supported mechanism for a persistent separate process in App Store apps is **Network Extension**.

### macOS: XPC Service

```
YourApp.app/
└── Contents/
    └── XPCServices/
        └── VigilValidator.xpc/
            └── Contents/
                ├── Info.plist
                └── MacOS/
                    └── VigilValidator
```

**Communication Flow:**

```objc
// App side
NSXPCConnection *connection = [[NSXPCConnection alloc]
    initWithServiceName:@"com.yourteam.VigilValidator"];
connection.remoteObjectInterface = [NSXPCInterface
    interfaceWithProtocol:@protocol(VigilValidatorProtocol)];
[connection resume];

id<VigilValidatorProtocol> validator = connection.remoteObjectProxy;
[validator validateHash:hash
              signature:signature
              publicKey:publicKey
                  nonce:nonce
              withReply:^(BOOL valid, NSData *response, NSData *validatorKey) {
    // Handle response
}];
```

**Advantages:**
- Native Apple technology
- Automatic lifecycle management
- Strong sandboxing
- Synchronous-style async API

### iOS: Network Extension (Content Filter)

```
YourApp.app/
└── PlugIns/
    └── VigilFilter.appex/
        └── VigilFilter  (NEFilterDataProvider)
```

**Why Content Filter?**

iOS offers several Network Extension types:

| Extension Type | Persistence | IPC Support | Sandbox |
|---------------|-------------|-------------|---------|
| Packet Tunnel | When VPN active | sendProviderMessage | Liberal |
| Content Filter | Always (when enabled) | sendProviderMessage | Restrictive |
| DNS Proxy | When enabled | Limited | Moderate |

Content Filter (NEFilterDataProvider) is optimal because:
- Runs persistently when enabled
- Supports bidirectional IPC via `sendProviderMessage`/`handleAppMessage`
- Doesn't require actual VPN configuration

**Important**: The filter can be configured to allow all traffic while still providing process isolation for Vigil.

**Communication Flow:**

```objc
// App side
NEFilterManager *manager = [NEFilterManager sharedManager];
[manager loadFromPreferencesWithCompletionHandler:^(NSError *error) {
    NETunnelProviderSession *session =
        (NETunnelProviderSession *)manager.connection;

    NSData *message = [self encodeValidationRequest:hash
                                          signature:signature
                                          publicKey:publicKey
                                              nonce:nonce];

    [session sendProviderMessage:message
                 responseHandler:^(NSData *response) {
        // Handle response
    }];
}];

// Validator side (in NEFilterDataProvider)
- (void)handleAppMessage:(NSData *)messageData
       completionHandler:(void (^)(NSData *))completionHandler {
    VigilRequest *request = [self decodeRequest:messageData];

    // Validate and respond
    VigilResponse *response = [self processValidation:request];
    completionHandler([self encodeResponse:response]);
}
```

**Setup Requirement:**

Users must enable the Content Filter in Settings > General > VPN & Device Management. This is a one-time setup, and Vigil provides UI helpers for guiding users through it.

---

## IPC Mechanism Analysis

### Mechanisms Evaluated

We evaluated every documented and undocumented IPC mechanism on Apple platforms:

#### 1. XPC (NSXPCConnection)

**macOS**: First-class support via bundled XPC Services.

**iOS**: XPC is private API. While the framework exists, `xpc_connection_create` and related functions are not available to third-party developers. Network Extension's `sendProviderMessage` is implemented on top of XPC internally but exposed through a public API.

**Verdict**: macOS only.

#### 2. CFMessagePort

**macOS**: Works with App Group prefixes.

**iOS**: According to Apple documentation, "This method is not available on iOS 7 and later—it will return NULL and log a sandbox violation." Our testing confirmed this remains true as of iOS 17.

**Verdict**: macOS only (and deprecated).

#### 3. Darwin Notifications (CFNotificationCenterGetDarwinNotifyCenter)

**Both Platforms**: Works for signaling between processes in the same App Group.

**Limitation**: Cannot carry payload data. The `userInfo` dictionary is explicitly not supported for Darwin notifications.

**Verdict**: Useful for wake-up signals only, not for data transfer.

#### 4. POSIX Shared Memory (shm_open + mmap)

**Both Platforms**: Works when the shared memory name is prefixed with the App Group identifier.

**Usage Pattern**:
```objc
// Create shared memory
int fd = shm_open("group.com.yourteam.app/vigil-channel",
                  O_CREAT | O_RDWR, 0600);
ftruncate(fd, CHANNEL_SIZE);
void *mem = mmap(NULL, CHANNEL_SIZE, PROT_READ | PROT_WRITE,
                 MAP_SHARED, fd, 0);
```

**Limitation**: Requires a process to already be running. Cannot spawn a new process.

**Verdict**: Viable for data exchange IF you have another mechanism to ensure the validator process exists.

#### 5. Unix Domain Sockets

**Both Platforms**: Works within App Group containers.

**Usage Pattern**:
```objc
// Socket path in shared container
NSString *path = [sharedContainer
    stringByAppendingPathComponent:@"vigil.sock"];

int sock = socket(AF_UNIX, SOCK_STREAM, 0);
struct sockaddr_un addr = {0};
addr.sun_family = AF_UNIX;
strncpy(addr.sun_path, path.UTF8String, sizeof(addr.sun_path) - 1);
```

**Limitation**: Same as shared memory—requires existing process.

**Verdict**: Viable for data exchange with existing process.

#### 6. Network Extension IPC

**Both Platforms**: Available via `NEProvider` base class methods.

**iOS**: The only way to have a persistent separate process for App Store apps.

**macOS**: Works but XPC Services are preferred for pure validation use cases.

**Verdict**: Required for iOS, optional for macOS.

### Final IPC Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                        VIGIL IPC LAYER                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌───────────────────────┐   ┌───────────────────────────────┐ │
│   │       macOS           │   │           iOS                 │ │
│   │                       │   │                               │ │
│   │   NSXPCConnection     │   │   NEFilterManager             │ │
│   │         │             │   │         │                     │ │
│   │         ▼             │   │         ▼                     │ │
│   │   XPC Service         │   │   sendProviderMessage         │ │
│   │   (VigilValidator)    │   │         │                     │ │
│   │                       │   │         ▼                     │ │
│   │                       │   │   NEFilterDataProvider        │ │
│   │                       │   │   (VigilFilter)               │ │
│   └───────────────────────┘   └───────────────────────────────┘ │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │              SHARED PROTOCOL LAYER                      │   │
│   │                                                         │   │
│   │   • Message encoding (Protocol Buffers / NSCoding)      │   │
│   │   • Challenge-response protocol                         │   │
│   │   • Timeout handling                                    │   │
│   │   • Error recovery                                      │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

The **protocol layer is identical** across platforms. Only the transport differs.

---

## Cryptographic Design

### Key Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                     SECURE ENCLAVE                              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                                                         │    │
│  │   App Private Key ◄──────► App Public Key ─────────┐    │    │
│  │        │                                           │    │    │
│  │        │ signs                                     │    │    │
│  │        ▼                                           │    │    │
│  │   (hash + nonce)                                   │    │    │
│  │                                                    │    │    │
│  │   Validator Private Key ◄─► Validator Public Key ──┼────┼────┤
│  │        │                                           │    │    │
│  │        │ signs                                     │    │    │
│  │        ▼                                           │    │    │
│  │   (response + nonce)                               │    │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │    KEYCHAIN     │
                    │                 │
                    │  Stored:        │
                    │  • App PubKey   │
                    │  • Valid PubKey │
                    │                 │
                    └─────────────────┘
```

### Algorithm Selection

| Purpose | Algorithm | Justification |
|---------|-----------|---------------|
| Hash | SHA-256 | Industry standard, fast, Secure Enclave compatible |
| Signature | ECDSA P-256 | Required for Secure Enclave, 128-bit security |
| Nonce | 32 bytes random | Matches hash output size, sufficient entropy |

### Key Binding to Code Signing

When an app is re-signed with a different certificate:

1. The **Team ID** changes (e.g., `ABCD1234` to `WXYZ5678`)
2. Keychain access groups include the Team ID prefix
3. The re-signed app has **different access groups**
4. **Secure Enclave keys become inaccessible**

This is a critical security property: even if an attacker obtains your IPA and re-signs it, they cannot access the Secure Enclave keys created by the original app.

```
Original App:
  Team ID: ABCD1234
  Access Group: ABCD1234.com.yourteam.app
  SE Key Tag: ABCD1234.com.yourteam.app.vigil
  ✓ Can access key

Re-signed App:
  Team ID: WXYZ5678
  Access Group: WXYZ5678.com.yourteam.app
  SE Key Tag: ABCD1234.com.yourteam.app.vigil  ← Original tag
  ✗ Cannot access key (different access group)
```

---

## Validation Protocol

### Message Format

```objc
@interface VigilRequest : NSObject <NSSecureCoding>
@property (nonatomic, strong) NSData *hash;          // SHA-256 of __TEXT
@property (nonatomic, strong) NSData *signature;     // SE signature of (hash + nonce)
@property (nonatomic, strong) NSData *publicKey;     // App's SE public key
@property (nonatomic, strong) NSData *nonce;         // Random challenge
@property (nonatomic, assign) uint64_t timestamp;    // For freshness (optional)
@end

@interface VigilResponse : NSObject <NSSecureCoding>
@property (nonatomic, assign) BOOL valid;            // Validation result
@property (nonatomic, strong) NSData *validatorHash; // Validator's __TEXT hash
@property (nonatomic, strong) NSData *signature;     // SE signature of response
@property (nonatomic, strong) NSData *publicKey;     // Validator's SE public key
@property (nonatomic, strong) NSData *nonce;         // Response nonce
@end
```

**Signature Format:**

- **Request signature** covers: `hash + nonce`
- **Response signature** covers: `validByte + validatorHash + nonce`

Note: Timestamp is present in the protocol for potential future use but is not included in signature computation for the XPC transport.

### Protocol Flow

```
┌──────────────┐                              ┌──────────────┐
│     APP      │                              │  VALIDATOR   │
└──────┬───────┘                              └──────┬───────┘
       │                                             │
       │  1. Generate nonce₁                         │
       │  2. Compute hash_app                        │
       │  3. Sign(hash_app + nonce₁)                 │
       │                                             │
       │──── VigilRequest ──────────────────────────►│
       │     { hash_app, sig_app, pk_app, nonce₁ }   │
       │                                             │
       │                    4. Verify sig_app        │
       │                    5. Compare hash_app      │
       │                       to expected           │
       │                    6. Compute hash_val      │
       │                    7. Generate nonce₂       │
       │                    8. Sign(result +         │
       │                       hash_val + nonce₂)    │
       │                                             │
       │◄─── VigilResponse ──────────────────────────│
       │     { valid, hash_val, sig_val,             │
       │       pk_val, nonce₂ }                      │
       │                                             │
       │  9. Verify sig_val                          │
       │  10. Verify pk_val matches stored           │
       │  11. Compare hash_val to expected           │
       │  12. Accept or reject                       │
       │                                             │
       ▼                                             ▼
```

### Timeout Handling

```objc
// Default timeout: 5 seconds
// If validator doesn't respond → VigilResultTimeout → Treat as tampered

dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
    (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (!responseReceived) {
        completion(VigilResultTimeout);
    }
});
```

The fail-closed design means:
- Validator crash → Treated as tampering
- Validator killed → Treated as tampering
- IPC failure → Treated as tampering
- Validator too slow → Treated as tampering

---

## Build-Time Integration

### Hash Pre-computation

At build time, Vigil computes the expected hash of the app binary and embeds it in the validator:

```bash
# Build phase script
vigil-hash-tool --input "${BUILT_PRODUCTS_DIR}/${EXECUTABLE_PATH}" \
                --output "${VALIDATOR_DIR}/ExpectedHashes.plist"
```

This creates a chicken-and-egg problem: the validator must be built after the app, but they're in the same bundle.

**Solution**: Two-pass build

1. **Pass 1**: Build app without validator hash
2. **Pass 2**: Compute app hash, embed in validator, rebuild validator
3. **Pass 3**: Rebuild app with updated validator (optional, for validator hash in app)

### Code Signing Order

```
1. Build app binary
2. Build validator binary
3. Compute app __TEXT hash
4. Embed hash in validator resources
5. Sign validator
6. Compute validator __TEXT hash
7. Embed hash in app resources
8. Sign app (re-signs embedded validator)
9. Compute final hashes (for verification during testing)
```

The signing order ensures both binaries can verify each other's integrity.

---

## Future Considerations

### Potential Enhancements

1. **Multiple Validators**: Run multiple validator instances for redundancy
2. **Continuous Monitoring**: Periodic re-validation during runtime
3. **Behavioral Attestation**: Verify app behavior patterns, not just code
4. **Remote Attestation Mode**: Optional server validation for high-security scenarios

### Known Limitations

1. **Network Extension UX**: iOS requires user to enable Content Filter in Settings
2. **Build Complexity**: Two-pass build adds time and complexity
3. **Simulator**: Secure Enclave not available; testing requires physical devices
4. **Jailbroken Devices**: Kernel-level attacks can bypass any userspace protection

See [SECURITY.md](./SECURITY.md) for complete threat analysis.
