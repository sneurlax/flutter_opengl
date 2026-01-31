#!/bin/bash
#
# Build the Rust static library for iOS targets.
# Called by the CocoaPods script_phase in flutter_opengl.podspec.
#
# Environment variables set by Xcode/CocoaPods:
#   CONFIGURATION       - Debug or Release
#   ARCHS               - Space-separated list of architectures (arm64, x86_64)
#   PLATFORM_NAME       - iphoneos or iphonesimulator
#   PODS_TARGET_SRCROOT - Path to the pod's source root (ios/)
#

set -e

RUST_DIR="${PODS_TARGET_SRCROOT}/../rust"
LIB_NAME="libflutter_opengl_rust.a"

# Determine Cargo profile
if [ "$CONFIGURATION" = "Release" ]; then
    CARGO_PROFILE="release"
    CARGO_FLAGS="--release"
else
    CARGO_PROFILE="debug"
    CARGO_FLAGS=""
fi

# Map Xcode architectures + platform to Rust targets
RUST_TARGETS=""
for ARCH in $ARCHS; do
    case "$ARCH" in
        arm64)
            if [ "$PLATFORM_NAME" = "iphonesimulator" ]; then
                RUST_TARGETS="$RUST_TARGETS aarch64-apple-ios-sim"
            else
                RUST_TARGETS="$RUST_TARGETS aarch64-apple-ios"
            fi
            ;;
        x86_64)
            RUST_TARGETS="$RUST_TARGETS x86_64-apple-ios"
            ;;
        *)
            echo "warning: unsupported architecture $ARCH, skipping"
            ;;
    esac
done

if [ -z "$RUST_TARGETS" ]; then
    echo "error: no supported architectures found in ARCHS=$ARCHS"
    exit 1
fi

# Ensure Rust targets are installed and build each one
BUILT_LIBS=""
for TARGET in $RUST_TARGETS; do
    rustup target add "$TARGET" 2>/dev/null || true
    cargo build $CARGO_FLAGS --target "$TARGET" --manifest-path "$RUST_DIR/Cargo.toml"
    BUILT_LIBS="$BUILT_LIBS $RUST_DIR/target/$TARGET/$CARGO_PROFILE/$LIB_NAME"
done

# Create a universal (fat) library if multiple architectures, otherwise just copy
OUTPUT_DIR="$RUST_DIR/target/ios-universal/$CARGO_PROFILE"
mkdir -p "$OUTPUT_DIR"

LIB_COUNT=$(echo $BUILT_LIBS | wc -w | tr -d ' ')
if [ "$LIB_COUNT" -gt 1 ]; then
    lipo -create $BUILT_LIBS -output "$OUTPUT_DIR/$LIB_NAME"
else
    cp $BUILT_LIBS "$OUTPUT_DIR/$LIB_NAME"
fi

echo "Rust library built: $OUTPUT_DIR/$LIB_NAME"
