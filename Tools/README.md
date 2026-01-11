# Vigil Build Tools

This directory contains tools for integrating Vigil into your build process.

## vigil-hash-tool

Command-line utility for computing __TEXT segment hashes at build time.

### Usage

```bash
# Compute hash of a binary
vigil-hash-tool --binary /path/to/YourApp

# Compute hash and output to plist
vigil-hash-tool --binary /path/to/YourApp --output ExpectedHashes.plist

# Compute hash for specific architecture
vigil-hash-tool --binary /path/to/YourApp --arch arm64
```

### Build Phase Integration

Add a Run Script build phase after "Link Binary With Libraries":

```bash
#!/bin/bash
set -e

TOOL="${SRCROOT}/Tools/vigil-hash-tool"
BINARY="${BUILT_PRODUCTS_DIR}/${EXECUTABLE_PATH}"
OUTPUT="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/ExpectedHashes.plist"

if [ -f "$BINARY" ]; then
    "$TOOL" --binary "$BINARY" --output "$OUTPUT"
    echo "Generated hash: $(cat "$OUTPUT" | grep app_text_hash)"
fi
```

### Building the Tool

```bash
cd Tools
make
```

## vigil-validate

Command-line utility for validating Vigil integration in your app bundle.

### Usage

```bash
# Validate an app bundle
vigil-validate /path/to/YourApp.app

# Verbose output
vigil-validate --verbose /path/to/YourApp.app
```

### Checks Performed

1. Vigil framework is properly embedded
2. Validator (XPC Service or Network Extension) is present
3. Entitlements are correctly configured
4. Expected hashes are embedded
5. Code signing is valid
