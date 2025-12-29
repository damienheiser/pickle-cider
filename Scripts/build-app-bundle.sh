#!/bin/bash
set -e

# Build Pickle Cider app bundle with proper signing
# Uses your local development certificate for Full Disk Access compatibility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_NAME="Pickle Cider"

echo "Building Pickle Cider App Bundle"
echo "================================"
echo ""

cd "$PROJECT_DIR"

# Build if not already built
if [ ! -f "$BUILD_DIR/PickleCider" ]; then
    echo "Building release binary..."
    swift build -c release
fi

# Find signing identity
echo "Looking for signing identity..."
IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/')

if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID" | head -1 | sed 's/.*"\(.*\)".*/\1/')
fi

if [ -z "$IDENTITY" ]; then
    # Fall back to first available identity
    IDENTITY=$(security find-identity -v -p codesigning | grep -v "valid identities found" | head -1 | sed 's/.*"\(.*\)".*/\1/')
fi

if [ -z "$IDENTITY" ]; then
    echo "ERROR: No code signing identity found!"
    echo ""
    echo "You need a development certificate. Options:"
    echo "  1. Open Xcode → Settings → Accounts → Manage Certificates"
    echo "  2. Click + and create 'Apple Development' certificate"
    echo "  3. Re-run this script"
    echo ""
    echo "Or build with Xcode directly:"
    echo "  swift package generate-xcodeproj"
    echo "  open *.xcodeproj"
    exit 1
fi

echo "Using identity: $IDENTITY"
echo ""

# Create app bundle structure
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "Creating app bundle..."

# Copy binary
cp "$BUILD_DIR/PickleCider" "$APP_BUNDLE/Contents/MacOS/PickleCider"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Generate icon if script exists
if [ -f "$SCRIPT_DIR/generate-icon.swift" ]; then
    echo "Generating app icon..."
    ICON_DIR="$BUILD_DIR/icon-temp"
    mkdir -p "$ICON_DIR"
    swift "$SCRIPT_DIR/generate-icon.swift" "$ICON_DIR" 2>/dev/null || true
    if [ -d "$ICON_DIR/AppIcon.iconset" ]; then
        iconutil -c icns "$ICON_DIR/AppIcon.iconset" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    fi
    rm -rf "$ICON_DIR"
fi

# Sign the app bundle
echo "Signing app bundle..."
codesign --force --deep --sign "$IDENTITY" "$APP_BUNDLE"

# Also sign CLI tools
echo "Signing CLI tools..."
codesign --force --sign "$IDENTITY" "$BUILD_DIR/cider"
codesign --force --sign "$IDENTITY" "$BUILD_DIR/pickle"

# Verify signature
echo ""
echo "Verifying signatures..."
codesign --verify --verbose "$APP_BUNDLE"

echo ""
echo "================================"
echo "Build complete!"
echo ""
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To install:"
echo "  cp -r \"$APP_BUNDLE\" /Applications/"
echo "  sudo cp \"$BUILD_DIR/cider\" \"$BUILD_DIR/pickle\" /usr/local/bin/"
echo ""
echo "Then grant Full Disk Access in System Settings."
