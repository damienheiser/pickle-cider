#!/bin/bash
set -e

# Build release script for Cider & Pickle
# Creates universal binaries for Intel and Apple Silicon Macs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release-universal"
VERSION="${1:-1.0.0}"

echo "Building Cider & Pickle v$VERSION"
echo "================================="
echo ""

cd "$PROJECT_DIR"

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build for Apple Silicon
echo "Building for Apple Silicon (arm64)..."
swift build -c release --arch arm64

# Build for Intel
echo "Building for Intel (x86_64)..."
swift build -c release --arch x86_64

# Create universal binaries
echo "Creating universal binaries..."

# Cider
lipo -create \
    .build/arm64-apple-macosx/release/cider \
    .build/x86_64-apple-macosx/release/cider \
    -output "$BUILD_DIR/cider"

# Pickle
lipo -create \
    .build/arm64-apple-macosx/release/pickle \
    .build/x86_64-apple-macosx/release/pickle \
    -output "$BUILD_DIR/pickle"

# Make executable
chmod +x "$BUILD_DIR/cider"
chmod +x "$BUILD_DIR/pickle"

# Verify
echo ""
echo "Verifying universal binaries..."
file "$BUILD_DIR/cider"
file "$BUILD_DIR/pickle"

# Create release archive
echo ""
echo "Creating release archive..."
ARCHIVE_NAME="apple-notes-tools-v$VERSION-macos-universal.tar.gz"
cd "$BUILD_DIR"
tar -czf "$ARCHIVE_NAME" cider pickle

echo ""
echo "Build complete!"
echo ""
echo "Binaries:"
echo "  $BUILD_DIR/cider"
echo "  $BUILD_DIR/pickle"
echo ""
echo "Archive:"
echo "  $BUILD_DIR/$ARCHIVE_NAME"
echo ""
echo "To install:"
echo "  sudo cp $BUILD_DIR/cider /usr/local/bin/"
echo "  sudo cp $BUILD_DIR/pickle /usr/local/bin/"
