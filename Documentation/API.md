# Vigil API Reference

Complete API documentation for the Vigil framework.

## Table of Contents

1. [Vigil (Main Interface)](#vigil-main-interface)
2. [HashEngine](#hashengine)
3. [SEKeyManager](#sekeymanager)
4. [AttestationStore](#attestationstore)
5. [VigilValidatorProtocol](#vigilvalidatorprotocol)
6. [Types and Constants](#types-and-constants)
7. [Error Codes](#error-codes)
8. [Swift Interface](#swift-interface)

---

## Vigil (Main Interface)

The primary class for performing integrity validation.

### Class Methods

#### `+initialize:completion:`

Initializes Vigil, generating Secure Enclave keys and establishing connection with the validator.

```objc
+ (void)initializeWithCompletion:(void (^)(BOOL success, NSError *error))completion;
```

**Parameters:**
- `completion`: Called when initialization completes. `success` is `YES` if initialization succeeded.

**Notes:**
- Must be called before any validation attempts
- Generates SE key pair if not already present
- Performs initial key exchange with validator if needed
- Thread-safe; can be called from any thread

**Example:**
```objc
[Vigil initializeWithCompletion:^(BOOL success, NSError *error) {
    if (success) {
        NSLog(@"Vigil initialized successfully");
    } else {
        NSLog(@"Initialization failed: %@", error.localizedDescription);
    }
}];
```

---

#### `+validate:completion:`

Performs integrity validation with the default timeout (5 seconds).

```objc
+ (void)validateWithCompletion:(void (^)(VigilResult result))completion;
```

**Parameters:**
- `completion`: Called with the validation result.

**Example:**
```objc
[Vigil validateWithCompletion:^(VigilResult result) {
    if (result == VigilResultValid) {
        // Proceed with normal operation
    }
}];
```

---

#### `+validate:timeout:completion:`

Performs integrity validation with a custom timeout.

```objc
+ (void)validateWithTimeout:(NSTimeInterval)timeout
                 completion:(void (^)(VigilResult result))completion;
```

**Parameters:**
- `timeout`: Maximum time to wait for validator response (in seconds)
- `completion`: Called with the validation result

**Notes:**
- If timeout elapses before response, returns `VigilResultTimeout`
- Recommended timeout: 3-10 seconds
- Completion always called on main thread

**Example:**
```objc
[Vigil validateWithTimeout:3.0 completion:^(VigilResult result) {
    switch (result) {
        case VigilResultValid:
            break;
        case VigilResultTampered:
        case VigilResultTimeout:
            [self handleCompromise];
            break;
        case VigilResultError:
            [self retryValidation];
            break;
    }
}];
```

---

#### `+validateSync`

Performs synchronous validation (blocks calling thread).

```objc
+ (VigilResult)validateSync;
```

**Returns:** `VigilResult` indicating validation outcome.

**Warning:** Do not call on main thread. Will block until validation completes or times out.

**Example:**
```objc
dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    VigilResult result = [Vigil validateSync];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self handleResult:result];
    });
});
```

---

#### `+isInitialized`

Checks if Vigil has been initialized.

```objc
+ (BOOL)isInitialized;
```

**Returns:** `YES` if `initializeWithCompletion:` has completed successfully.

---

#### `+setLogLevel:`

Sets the logging verbosity.

```objc
+ (void)setLogLevel:(VigilLogLevel)level;
```

**Parameters:**
- `level`: One of `VigilLogLevelNone`, `VigilLogLevelError`, `VigilLogLevelWarning`, `VigilLogLevelInfo`, `VigilLogLevelDebug`

**Example:**
```objc
#ifdef DEBUG
[Vigil setLogLevel:VigilLogLevelDebug];
#else
[Vigil setLogLevel:VigilLogLevelError];
#endif
```

---

#### `+validatorStatus`

Returns the current status of the validator process.

```objc
+ (VigilValidatorStatus)validatorStatus;
```

**Returns:** One of:
- `VigilValidatorStatusUnknown`: Status not yet determined
- `VigilValidatorStatusRunning`: Validator is running and responsive
- `VigilValidatorStatusNotRunning`: Validator is not running
- `VigilValidatorStatusNotConfigured`: Validator not set up (iOS: Content Filter disabled)

---

## HashEngine

Computes cryptographic hashes of executable code segments.

### Class Methods

#### `+computeTextHash`

Computes SHA-256 hash of the current process's `__TEXT` segments.

```objc
+ (NSData *)computeTextHash;
```

**Returns:** 32-byte `NSData` containing SHA-256 hash, or `nil` on error.

**Notes:**
- Includes all Mach-O images within the app bundle
- Excludes system frameworks and dylibs
- Hash is deterministic for identical binaries

**Example:**
```objc
NSData *hash = [HashEngine computeTextHash];
NSLog(@"Current hash: %@", [hash base64EncodedStringWithOptions:0]);
```

---

#### `+computeTextHashForPath:`

Computes SHA-256 hash of a binary at the specified path.

```objc
+ (NSData *)computeTextHashForPath:(NSString *)path;
```

**Parameters:**
- `path`: Absolute path to a Mach-O binary

**Returns:** 32-byte `NSData` containing SHA-256 hash, or `nil` on error.

**Notes:**
- Used primarily for build-time hash computation
- Can hash any Mach-O binary, not just the current process

---

#### `+combineHashes:`

Combines multiple hashes into a single digest.

```objc
+ (NSData *)combineHashes:(NSArray<NSData *> *)hashes;
```

**Parameters:**
- `hashes`: Array of hash `NSData` objects

**Returns:** Combined 32-byte SHA-256 hash.

**Notes:**
- Order-dependent: `[A, B]` produces different result than `[B, A]`
- Used for multi-binary validation scenarios

---

#### `+hexStringFromData:`

Converts hash data to hexadecimal string.

```objc
+ (NSString *)hexStringFromData:(NSData *)data;
```

**Parameters:**
- `data`: Binary data to convert

**Returns:** Lowercase hexadecimal string representation.

**Example:**
```objc
NSData *hash = [HashEngine computeTextHash];
NSString *hexHash = [HashEngine hexStringFromData:hash];
// "a3f2b1c4..."
```

---

## SEKeyManager

Manages Secure Enclave key pairs for cryptographic operations.

### Shared Instance

#### `+sharedManager`

Returns the singleton instance.

```objc
+ (instancetype)sharedManager;
```

---

### Class Methods

#### `+isSecureEnclaveAvailable`

Checks if Secure Enclave is available on this device.

```objc
+ (BOOL)isSecureEnclaveAvailable;
```

**Returns:** `YES` if SE is available (physical device with SE hardware).

**Notes:**
- Returns `NO` on simulators
- Returns `NO` on devices without SE (pre-iPhone 5s, some iPads)

---

### Instance Methods

#### `-generateKeyPairWithTag:error:`

Generates a new Secure Enclave key pair.

```objc
- (BOOL)generateKeyPairWithTag:(NSString *)tag error:(NSError **)error;
```

**Parameters:**
- `tag`: Unique identifier for the key pair (e.g., `"com.myapp.vigil"`)
- `error`: Pointer to receive error information

**Returns:** `YES` if key generation succeeded.

**Notes:**
- Keys are permanent and persist across app launches
- Keys are device-specific and non-exportable
- Returns `NO` if key with this tag already exists

**Example:**
```objc
NSError *error;
BOOL success = [[SEKeyManager sharedManager]
    generateKeyPairWithTag:@"com.myapp.vigil" error:&error];
if (!success) {
    NSLog(@"Key generation failed: %@", error);
}
```

---

#### `-publicKeyDataForTag:`

Retrieves the public key for a key pair.

```objc
- (NSData *)publicKeyDataForTag:(NSString *)tag;
```

**Parameters:**
- `tag`: Tag of the key pair

**Returns:** Public key in X.509 SubjectPublicKeyInfo format, or `nil` if not found.

**Notes:**
- Public key can be freely shared
- Format is compatible with standard crypto libraries

---

#### `-signData:withKeyTag:error:`

Signs data using the Secure Enclave private key.

```objc
- (NSData *)signData:(NSData *)data
          withKeyTag:(NSString *)tag
               error:(NSError **)error;
```

**Parameters:**
- `data`: Data to sign
- `tag`: Tag of the key pair to use
- `error`: Pointer to receive error information

**Returns:** ECDSA signature in DER format, or `nil` on error.

**Notes:**
- Signing operation occurs inside Secure Enclave
- Private key never leaves SE hardware
- Uses SHA-256 for digest

**Example:**
```objc
NSData *message = [@"Hello, World!" dataUsingEncoding:NSUTF8StringEncoding];
NSError *error;
NSData *signature = [[SEKeyManager sharedManager]
    signData:message withKeyTag:@"com.myapp.vigil" error:&error];
```

---

#### `-verifySignature:forData:withPublicKey:error:`

Verifies an ECDSA signature.

```objc
- (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
          withPublicKey:(NSData *)publicKey
                  error:(NSError **)error;
```

**Parameters:**
- `signature`: ECDSA signature in DER format
- `data`: Original signed data
- `publicKey`: Public key in X.509 format
- `error`: Pointer to receive error information

**Returns:** `YES` if signature is valid.

**Notes:**
- Does not require Secure Enclave (verification uses public key only)
- Works on simulators for testing

---

#### `-deleteKeyPairWithTag:error:`

Deletes a key pair from the Secure Enclave.

```objc
- (BOOL)deleteKeyPairWithTag:(NSString *)tag error:(NSError **)error;
```

**Parameters:**
- `tag`: Tag of the key pair to delete
- `error`: Pointer to receive error information

**Returns:** `YES` if deletion succeeded.

**Warning:** Deleted keys cannot be recovered.

---

## AttestationStore

Persistent storage for exchanged public keys.

### Shared Instance

#### `+sharedStore`

Returns the singleton instance.

```objc
+ (instancetype)sharedStore;
```

---

### Instance Methods

#### `-storeAppPublicKey:error:`

Stores the app's public key (called by validator).

```objc
- (BOOL)storeAppPublicKey:(NSData *)publicKey error:(NSError **)error;
```

**Parameters:**
- `publicKey`: App's public key data
- `error`: Pointer to receive error information

**Returns:** `YES` if storage succeeded.

---

#### `-storeValidatorPublicKey:error:`

Stores the validator's public key (called by app).

```objc
- (BOOL)storeValidatorPublicKey:(NSData *)publicKey error:(NSError **)error;
```

**Parameters:**
- `publicKey`: Validator's public key data
- `error`: Pointer to receive error information

**Returns:** `YES` if storage succeeded.

---

#### `-appPublicKey`

Retrieves the stored app public key.

```objc
- (NSData *)appPublicKey;
```

**Returns:** App's public key, or `nil` if not stored.

---

#### `-validatorPublicKey`

Retrieves the stored validator public key.

```objc
- (NSData *)validatorPublicKey;
```

**Returns:** Validator's public key, or `nil` if not stored.

---

#### `-isAttestationConfigured`

Checks if initial key exchange has been completed.

```objc
- (BOOL)isAttestationConfigured;
```

**Returns:** `YES` if both app and validator public keys are stored.

---

#### `-clearStore:`

Removes all stored keys.

```objc
- (BOOL)clearStore:(NSError **)error;
```

**Parameters:**
- `error`: Pointer to receive error information

**Returns:** `YES` if clearing succeeded.

**Warning:** Requires re-running key exchange after clearing.

---

## VigilValidatorProtocol

Protocol implemented by the validator (XPC Service or Network Extension).

```objc
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

- (void)ping:(void (^)(BOOL alive))reply;

@end
```

### Methods

#### `validateHash:signature:publicKey:nonce:withReply:`

Validates the app's integrity claim.

**Parameters:**
- `hash`: SHA-256 hash of app's `__TEXT` segment
- `signature`: SE signature of `(hash + nonce)`
- `publicKey`: App's SE public key
- `nonce`: Random challenge nonce
- `reply`: Completion block with validation result

**Reply Parameters:**
- `valid`: `YES` if hash matches expected value and signature is valid
- `validatorHash`: Validator's own `__TEXT` hash
- `responseSignature`: SE signature of response
- `validatorPublicKey`: Validator's SE public key

---

#### `exchangePublicKey:withReply:`

Exchanges public keys during initial setup.

**Parameters:**
- `appPublicKey`: App's SE public key
- `reply`: Completion block with validator's public key

---

#### `ping:`

Checks if validator is alive and responsive.

**Parameters:**
- `reply`: Completion block with alive status

---

## Types and Constants

### VigilResult

```objc
typedef NS_ENUM(NSInteger, VigilResult) {
    VigilResultValid = 0,      // Integrity verified
    VigilResultTampered = 1,   // Tampering detected
    VigilResultTimeout = 2,    // Validator unresponsive
    VigilResultError = 3       // Validation error occurred
};
```

### VigilValidatorStatus

```objc
typedef NS_ENUM(NSInteger, VigilValidatorStatus) {
    VigilValidatorStatusUnknown = 0,
    VigilValidatorStatusRunning = 1,
    VigilValidatorStatusNotRunning = 2,
    VigilValidatorStatusNotConfigured = 3
};
```

### VigilLogLevel

```objc
typedef NS_ENUM(NSInteger, VigilLogLevel) {
    VigilLogLevelNone = 0,
    VigilLogLevelError = 1,
    VigilLogLevelWarning = 2,
    VigilLogLevelInfo = 3,
    VigilLogLevelDebug = 4
};
```

### Constants

```objc
// Default validation timeout
extern NSTimeInterval const VigilDefaultTimeout;  // 5.0 seconds

// Notification posted when validation completes
extern NSString *const VigilValidationDidCompleteNotification;

// UserInfo keys for notification
extern NSString *const VigilResultKey;  // NSNumber containing VigilResult
```

---

## Error Codes

### VigilErrorDomain

```objc
extern NSString *const VigilErrorDomain;
```

### Error Codes

```objc
typedef NS_ENUM(NSInteger, VigilErrorCode) {
    // Initialization errors
    VigilErrorSecureEnclaveUnavailable = 1000,
    VigilErrorKeyGenerationFailed = 1001,
    VigilErrorKeyExchangeFailed = 1002,

    // Validation errors
    VigilErrorValidatorNotRunning = 2000,
    VigilErrorValidatorNotConfigured = 2001,
    VigilErrorIPCFailure = 2002,
    VigilErrorSignatureInvalid = 2003,
    VigilErrorHashMismatch = 2004,
    VigilErrorPublicKeyMismatch = 2005,

    // Storage errors
    VigilErrorKeychainAccessFailed = 3000,
    VigilErrorStorageCorrupted = 3001,

    // Internal errors
    VigilErrorInternalFailure = 9000
};
```

---

## Swift Interface

Vigil provides a native Swift API.

### Main Interface

```swift
public final class Vigil {

    /// Initialize Vigil (must call before validation)
    public static func initialize() async throws

    /// Validate integrity with default timeout
    public static func validate() async -> VigilResult

    /// Validate integrity with custom timeout
    public static func validate(timeout: TimeInterval) async -> VigilResult

    /// Check if Vigil is initialized
    public static var isInitialized: Bool { get }

    /// Current validator status
    public static var validatorStatus: VigilValidatorStatus { get }

    /// Set log level
    public static var logLevel: VigilLogLevel { get set }
}
```

### Result Type

```swift
public enum VigilResult: Int, Sendable {
    case valid = 0
    case tampered = 1
    case timeout = 2
    case error = 3
}
```

### Usage Example

```swift
import Vigil

@main
struct MyApp: App {
    init() {
        Task {
            do {
                try await Vigil.initialize()
                let result = await Vigil.validate(timeout: 5.0)

                switch result {
                case .valid:
                    print("Integrity verified")
                case .tampered, .timeout:
                    fatalError("App integrity compromised")
                case .error:
                    print("Validation error - retrying")
                }
            } catch {
                print("Vigil initialization failed: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Combine Integration

```swift
import Combine

extension Vigil {
    /// Publisher for validation results
    public static var validationPublisher: AnyPublisher<VigilResult, Never> {
        NotificationCenter.default
            .publisher(for: .vigilValidationDidComplete)
            .compactMap { notification in
                notification.userInfo?[Vigil.resultKey] as? VigilResult
            }
            .eraseToAnyPublisher()
    }
}
```

### Error Handling

```swift
public enum VigilError: Error {
    case secureEnclaveUnavailable
    case keyGenerationFailed(underlying: Error?)
    case keyExchangeFailed(underlying: Error?)
    case validatorNotRunning
    case validatorNotConfigured
    case ipcFailure(underlying: Error?)
    case signatureInvalid
    case hashMismatch
    case publicKeyMismatch
    case keychainAccessFailed(status: OSStatus)
    case storageCorrupted
    case internalFailure(message: String)
}
```

---

## Thread Safety

All Vigil APIs are thread-safe unless otherwise noted:

- `Vigil` class methods: Thread-safe
- `HashEngine` class methods: Thread-safe
- `SEKeyManager` methods: Thread-safe (but SE operations are serialized internally)
- `AttestationStore` methods: Thread-safe (uses Keychain, which is thread-safe)

Completion handlers are always called on the main thread unless using the `Sync` variants.

---

## Memory Management

Vigil uses ARC. No manual memory management required.

Key objects (`SEKeyManager`, `AttestationStore`) are singletons with static lifetime.

---

## Deprecated APIs

None currently. Future deprecations will be marked with `__deprecated_msg()` and announced in release notes.
