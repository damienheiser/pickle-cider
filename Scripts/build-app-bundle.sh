#!/bin/bash
set -e

# Build Pickle Cider app bundle with proper signing
# Uses Xcode for automatic signing with your development certificate

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/xcode-release"
APP_NAME="Pickle Cider"

echo "Building Pickle Cider with Xcode"
echo "================================"
echo ""

cd "$PROJECT_DIR"

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build using xcodebuild with automatic signing
echo "Building with xcodebuild (automatic signing)..."
xcodebuild \
    -scheme PickleCider \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -destination "platform=macOS" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="" \
    build 2>&1 | tail -20

# Find the built app
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "PickleCider.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo ""
    echo "xcodebuild didn't produce an app bundle."
    echo "Falling back to manual bundle creation..."
    echo ""

    # Build with swift
    swift build -c release

    # Create app bundle manually
    SWIFT_BUILD="$PROJECT_DIR/.build/release"
    APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    cp "$SWIFT_BUILD/PickleCider" "$APP_BUNDLE/Contents/MacOS/PickleCider"
    cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
    echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

    # Generate icon
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

    # Try to sign - if no identity, use ad-hoc but warn
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -v "valid identities" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)

    if [ -n "$IDENTITY" ]; then
        echo "Signing with: $IDENTITY"
        codesign --force --deep --sign "$IDENTITY" "$APP_BUNDLE"
        codesign --force --sign "$IDENTITY" "$SWIFT_BUILD/cider"
        codesign --force --sign "$IDENTITY" "$SWIFT_BUILD/pickle"
    else
        echo ""
        echo "⚠️  No signing identity found in keychain."
        echo ""
        echo "For Full Disk Access to work, build with Xcode:"
        echo "  1. Open Xcode"
        echo "  2. File → Open → select Package.swift in this folder"
        echo "  3. Select 'PickleCider' scheme"
        echo "  4. Product → Build"
        echo "  5. Product → Show Build Folder in Finder"
        echo ""
        # Still create the bundle for testing
        codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
    fi

    APP_PATH="$APP_BUNDLE"
    CLI_PATH="$SWIFT_BUILD"
else
    echo "Build successful!"
    CLI_PATH="$PROJECT_DIR/.build/release"
    # Also build CLI tools
    swift build -c release
fi

echo ""
echo "================================"
echo "Build complete!"
echo ""
echo "App: $APP_PATH"
echo ""
echo "To install:"
echo "  cp -r \"$APP_PATH\" /Applications/"
if [ -d "$CLI_PATH" ]; then
    echo "  sudo cp \"$CLI_PATH/cider\" \"$CLI_PATH/pickle\" /usr/local/bin/"
fi
echo ""
echo "Then grant Full Disk Access in System Settings."
