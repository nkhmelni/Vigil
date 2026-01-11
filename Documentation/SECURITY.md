# Vigil Security Model

This document describes Vigil's threat model, the attacks it mitigates, its limitations, and recommendations for defense-in-depth.

## Table of Contents

1. [Threat Model](#threat-model)
2. [Attack Categories](#attack-categories)
3. [Attack Mitigation Matrix](#attack-mitigation-matrix)
4. [Secure Enclave Properties](#secure-enclave-properties)
5. [Limitations and Non-Goals](#limitations-and-non-goals)
6. [Defense in Depth](#defense-in-depth)
7. [Security Assumptions](#security-assumptions)

---

## Threat Model

### Attacker Profile

Vigil is designed to protect against:

| Attacker Level | Capabilities | Example |
|----------------|--------------|---------|
| **Script Kiddie** | Uses pre-built tools, no custom development | Downloading Frida scripts from GitHub |
| **Intermediate** | Modifies existing tools, basic reverse engineering | Customizing Substrate tweaks |
| **Advanced** | Custom tooling, deep platform knowledge | Writing custom hooking frameworks |
| **Expert** | Kernel exploitation, hardware attacks | Exploiting 0-days, JTAG debugging |

Vigil provides strong protection against Script Kiddie through Advanced attackers. Expert-level attackers with kernel access or hardware capabilities are explicitly out of scope.

### Protected Assets

1. **Code Integrity**: Detect modifications to executable code
2. **Runtime Integrity**: Detect injection of foreign code
3. **Execution Authenticity**: Ensure the app is the original, unmodified version

### Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRUSTED COMPUTING BASE                       │
│                                                                 │
│   ┌─────────────────┐    ┌─────────────────┐    ┌───────────┐   │
│   │ Secure Enclave  │    │   iOS/macOS     │    │  Hardware │   │
│   │                 │    │   Kernel        │    │   (CPU,   │   │
│   │ • Key storage   │    │ • Memory prot   │    │   SE)     │   │
│   │ • Signing ops   │    │ • Code signing  │    │           │   │
│   └─────────────────┘    └─────────────────┘    └───────────┘   │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                    VIGIL PROTECTION LAYER                       │
│                                                                 │
│   ┌─────────────────┐    ┌─────────────────┐                    │
│   │   Host App      │◄──►│   Validator     │                    │
│   │   Process       │    │   Process       │                    │
│   └─────────────────┘    └─────────────────┘                    │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                    UNTRUSTED                                    │
│                                                                 │
│   • User-writable filesystem                                    │
│   • Other apps (sandboxed)                                      │
│   • Network                                                     │
│   • Physical environment                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Attack Categories

### 1. Static Binary Modification

**Attack**: Modify the executable on disk before or after installation.

**Examples**:
- Patching conditional jumps to bypass checks
- Replacing functions with attacker-controlled code
- Stripping code signature and re-signing

**Vigil Mitigation**:
- __TEXT hash detects any modification to executable code
- Secure Enclave keys are bound to original Team ID
- Re-signed app cannot access original SE keys

**Effectiveness**: **High**. Binary patches cause hash mismatch.

### 2. DYLD Injection

**Attack**: Inject malicious code via dynamic linker mechanisms.

**Techniques**:
- `DYLD_INSERT_LIBRARIES` environment variable
- `LC_LOAD_DYLIB` modification
- Interposing (dyld interpose sections)

**Vigil Mitigation**:
- HashEngine includes all bundle images in hash computation
- LoadManager-style image monitoring detects unexpected libraries
- Hardened Runtime (macOS) blocks DYLD_INSERT_LIBRARIES

**Effectiveness**: **High** for in-bundle modifications. **Medium** for runtime injection (requires additional detection).

### 3. Runtime Memory Modification

**Attack**: Modify code or data in memory during execution.

**Techniques**:
- `mach_vm_write` via task port
- Debugger attachment (`ptrace`, `task_for_pid`)
- Process memory editors (GameGuardian-style)

**Vigil Mitigation**:
- __TEXT segment is read-only (kernel enforced)
- `task_for_pid` requires special entitlements or root
- Hardened Runtime blocks debugger attachment
- Two-process architecture requires compromising both processes

**Platform Protections**:
- iOS: `task_for_pid` returns `KERN_FAILURE` for third-party apps
- macOS: Requires `com.apple.security.get-task-allow` or root

**Effectiveness**: **High** on iOS. **Medium-High** on macOS with Hardened Runtime.

### 4. Hooking Frameworks

**Attack**: Replace function implementations at runtime.

**Common Frameworks**:
- **Frida**: Dynamic instrumentation
- **Cydia Substrate**: Function hooking
- **fishhook**: Mach-O symbol rebinding
- **Dobby**: Inline hooking

**Vigil Mitigation**:
- Hooking code injected into bundle → hash mismatch
- Symbol table manipulation → hash of __TEXT unchanged, but LoadManager detects injected images
- Validator runs in separate process → attacker must hook both

**Detection Augmentation** (beyond Vigil core):
```objc
// Detect common hooking symbols
NSArray *hookSymbols = @[
    @"frida", @"substrate", @"fishhook",
    @"MSHookFunction", @"dobby", @"_logos"
];
// Check loaded images and symbol tables
```

**Effectiveness**: **Medium-High**. Framework injection detected; sophisticated inline hooks in existing code may require additional detection.

### 5. App Re-signing

**Attack**: Distribute modified app with attacker's code signature.

**Techniques**:
- Extract IPA, modify, re-sign with different certificate
- Replace resources, configuration, or code
- Distribute via sideloading or enterprise certificate

**Vigil Mitigation**:
- **Critical**: Secure Enclave keys are bound to Team ID
- Re-signed app has different Team ID → cannot access original keys
- Validation fails because validator doesn't recognize new public key
- Hash mismatch if code was modified

**Security Property**:
```
Original App:
  Team ID: ORIGINAL_TEAM
  SE Key Access: ✓ Can generate and use keys

Re-signed App (same bundle ID, different team):
  Team ID: ATTACKER_TEAM
  SE Key Access: ✗ Cannot access ORIGINAL_TEAM keys

  If attacker generates new keys:
    → Validator rejects: unknown public key
    → App rejects validator: unknown public key
```

**Effectiveness**: **Very High**. Fundamental cryptographic binding to code signing identity.

### 6. Task Port Attacks (mach_vm_write, thread injection)

**Attack**: Use Mach APIs to manipulate process memory or execution.

**Prerequisites**:
- Obtain target's task port via `task_for_pid`
- Requires: root privileges OR `com.apple.security.get-task-allow` entitlement OR kernel exploit

**Techniques**:
- `mach_vm_allocate` + `mach_vm_write`: Allocate and write to target memory
- `thread_create_running`: Create new thread in target process
- `task_set_exception_ports`: Intercept exceptions for control flow hijacking

**Platform Defenses**:

| Platform | Protection |
|----------|------------|
| iOS | `task_for_pid` blocked for all third-party apps. Returns `KERN_FAILURE`. |
| macOS (sandboxed) | `task_for_pid` blocked by sandbox |
| macOS (non-sandboxed, non-hardened) | Requires root |
| macOS (Hardened Runtime) | Additional protections against debuggers |

**Vigil Mitigation**:
- Two-process architecture: Must compromise both app AND validator task ports
- Secure Enclave signing: Memory modification doesn't grant access to SE private keys
- Fail-closed: If validator is killed or unresponsive, app detects compromise

**Effectiveness**: **High** on iOS. **Medium-High** on macOS with proper configuration.

### 7. Replay Attacks

**Attack**: Capture and replay valid validation messages.

**Technique**:
- Intercept IPC between app and validator
- Store valid request/response pairs
- Replay stored messages to bypass validation

**Vigil Mitigation**:
- **Nonces**: Every request includes a fresh random nonce
- **Timestamp checking**: Responses must be timely
- **Signature binding**: Signature covers hash + nonce, making replay useless

```
Request 1: Sign(hash + nonce_A) → Response for nonce_A
Request 2: Sign(hash + nonce_B) → Replaying Response for nonce_A fails
                                  (nonce_B ≠ nonce_A)
```

**Effectiveness**: **Very High**. Cryptographic prevention of replay.

### 8. Man-in-the-Middle on IPC

**Attack**: Intercept and modify IPC messages between app and validator.

**Vigil Mitigation**:
- All messages are cryptographically signed with Secure Enclave keys
- Public keys are exchanged during initial setup and stored
- Modified messages fail signature verification
- Attacker cannot forge signatures without SE private keys

**Effectiveness**: **Very High**. Cryptographic integrity protection.

---

## Attack Mitigation Matrix

| Attack Vector | Detection | Prevention | Effectiveness |
|--------------|-----------|------------|---------------|
| Binary patching | __TEXT hash | Code signing | Very High |
| DYLD injection | Image monitoring | Hardened Runtime | High |
| Memory modification | Re-hashing (if periodic) | Kernel protections | High |
| Hooking frameworks | Symbol/image checks | Two-process isolation | Medium-High |
| App re-signing | SE key check | Team ID binding | Very High |
| Task port attacks | N/A | Platform protections | High (iOS) |
| Replay attacks | Nonce verification | Cryptographic protocol | Very High |
| IPC MITM | Signature verification | SE signing | Very High |
| Debugger attachment | N/A | Hardened Runtime | Medium-High |
| Jailbreak/root | Detection possible | Out of scope | N/A |

---

## Secure Enclave Properties

### Hardware Security Guarantees

The Secure Enclave is a hardware security module (HSM) integrated into Apple SoCs:

1. **Key Isolation**: Private keys never leave the Secure Enclave
2. **Tamper Resistance**: Protected against physical extraction
3. **Separate Processor**: Independent from main CPU
4. **Encrypted Memory**: SE has dedicated encrypted memory region

### Key Properties Leveraged by Vigil

| Property | Security Benefit |
|----------|-----------------|
| Non-exportable keys | Attacker cannot extract private key, even with full app access |
| Hardware-bound operations | Signing happens inside SE, not in app memory |
| Code signing binding | Keys are scoped to Team ID + Bundle ID |
| Per-device keys | Keys cannot be transferred between devices |

### Access Control

Keys can be created with additional access requirements:

```objc
SecAccessControlRef access = SecAccessControlCreateWithFlags(
    kCFAllocatorDefault,
    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    kSecAccessControlPrivateKeyUsage |    // SE-only signing
    kSecAccessControlBiometryCurrentSet,  // Optional: require biometric
    &error);
```

Options:
- `kSecAccessControlBiometryCurrentSet`: Require Face ID/Touch ID
- `kSecAccessControlDevicePasscode`: Require device passcode
- `kSecAccessControlUserPresence`: Require either biometric or passcode

---

## Limitations and Non-Goals

### What Vigil Does NOT Protect Against

#### 1. Kernel-Level Attacks

If an attacker has kernel code execution (via jailbreak or exploit):
- Can disable all userspace protections
- Can intercept Secure Enclave communications
- Can modify memory protection attributes
- Can fake validation responses at kernel level

**Recommendation**: Detect jailbreak/root as defense-in-depth (see below).

#### 2. Hardware Attacks

Physical attacks with specialized equipment:
- JTAG/SWD debugging
- Chip decapping and probing
- Fault injection (glitching)
- Cold boot attacks

**Reality**: These require expensive equipment and physical access. Out of scope for most threat models.

#### 3. Compromised Build Environment

If the build machine is compromised:
- Attacker can embed malicious code signed with legitimate certificate
- Expected hashes would match malicious code
- Vigil would validate the compromised app as legitimate

**Recommendation**: Secure your CI/CD pipeline. Use hardware security keys for code signing certificates.

#### 4. Social Engineering

User installing attacker's app that mimics yours:
- Different bundle ID → different app entirely
- Vigil only protects YOUR app's integrity

#### 5. Simulator Testing

Secure Enclave is not available on simulators:
- Testing requires physical devices
- Simulator builds must use mock SE implementation

#### 6. First-Launch Window

Between app installation and first Vigil validation:
- Initial SE key generation occurs
- Initial key exchange with validator occurs
- Brief window where attestation is not yet established

**Mitigation**: Perform initial setup as early as possible in app lifecycle.

---

## Defense in Depth

Vigil is one layer in a comprehensive security strategy. Recommended additional measures:

### 1. Jailbreak Detection

Detect compromised OS environments:

```objc
// Example checks (non-exhaustive)
- (BOOL)isJailbroken {
    // Check for common jailbreak files
    NSArray *paths = @[
        @"/Applications/Cydia.app",
        @"/Library/MobileSubstrate",
        @"/usr/sbin/sshd",
        @"/etc/apt",
        @"/private/var/lib/apt/"
    ];
    for (NSString *path in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return YES;
        }
    }

    // Check if we can write outside sandbox
    NSError *error;
    [@"test" writeToFile:@"/private/test.txt"
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:&error];
    if (!error) {
        [[NSFileManager defaultManager] removeItemAtPath:@"/private/test.txt"
                                                   error:nil];
        return YES;
    }

    // Check for suspicious URL schemes
    if ([[UIApplication sharedApplication] canOpenURL:
         [NSURL URLWithString:@"cydia://"]]) {
        return YES;
    }

    return NO;
}
```

### 2. Anti-Debug Measures

Prevent dynamic analysis:

```objc
// Deny debugger attachment
#import <sys/ptrace.h>

__attribute__((constructor)) static void anti_debug() {
    ptrace(PT_DENY_ATTACH, 0, 0, 0);
}

// Detect debugger presence
- (BOOL)isDebuggerAttached {
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};

    if (sysctl(mib, 4, &info, &size, NULL, 0) == 0) {
        return (info.kp_proc.p_flag & P_TRACED) != 0;
    }
    return NO;
}
```

### 3. Symbol Stripping

Remove debugging symbols from release builds:

```
// Build Settings
STRIP_INSTALLED_PRODUCT = YES
STRIP_STYLE = all
DEPLOYMENT_POSTPROCESSING = YES
```

### 4. Code Obfuscation

Make reverse engineering more difficult:
- String encryption
- Control flow flattening
- Dead code insertion
- Symbol renaming

**Tools**: LLVM-based obfuscators, commercial solutions (iXGuard, DexGuard)

### 5. Certificate Pinning

Protect network communications:

```objc
// Pin to your server's certificate
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition,
                             NSURLCredential *))completionHandler {

    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, 0);
    NSData *serverCertData = (__bridge_transfer NSData *)
        SecCertificateCopyData(certificate);

    if ([serverCertData isEqualToData:self.pinnedCertData]) {
        NSURLCredential *credential = [NSURLCredential
            credentialForTrust:serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge,
                          nil);
    }
}
```

### 6. Secure Data Storage

Protect sensitive data at rest:

```objc
// Use Keychain for secrets
NSDictionary *query = @{
    (id)kSecClass: (id)kSecClassGenericPassword,
    (id)kSecAttrAccount: @"api_key",
    (id)kSecValueData: secretData,
    (id)kSecAttrAccessible: (id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly
};
SecItemAdd((__bridge CFDictionaryRef)query, NULL);
```

---

## Security Assumptions

Vigil's security guarantees depend on the following assumptions:

### 1. Apple's Platform Security Is Intact

- Kernel is not compromised
- Secure Enclave is functioning correctly
- Code signing enforcement is active
- Sandbox is enforced

If any of these fail (e.g., jailbreak), Vigil's guarantees are weakened.

### 2. Build Environment Is Secure

- Code signing certificate is protected
- Build machine is not compromised
- CI/CD pipeline is secure
- Dependencies are verified

### 3. Initial Setup Completes Successfully

- First launch establishes SE keys
- Key exchange between app and validator completes
- Attestation store is populated

### 4. Developer Follows Integration Guidelines

- Validation is performed at appropriate times
- Validation failures trigger appropriate responses
- Timeout values are reasonable
- Error handling is correct

---

## Reporting Security Issues

If you discover a security vulnerability in Vigil:

1. **Do not** open a public issue
2. Email security@[project-domain] with details
3. Include steps to reproduce
4. Allow 90 days for fix before public disclosure

We appreciate responsible disclosure and will credit researchers in release notes (unless anonymity is preferred).
