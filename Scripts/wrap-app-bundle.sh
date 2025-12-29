#!/bin/bash
# Wrap the Xcode-built executable in an .app bundle
# Preserves Xcode's code signature for Full Disk Access

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Find the Xcode-built executable
XCODE_EXEC=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Release/PickleCider" -type f -perm +111 2>/dev/null | head -1)

if [ -z "$XCODE_EXEC" ]; then
    echo "❌ Could not find Xcode-built PickleCider executable"
    echo ""
    echo "Please build in Xcode first:"
    echo "  1. Open Package.swift in Xcode"
    echo "  2. Product → Build For → Profiling (⇧⌘I)"
    exit 1
fi

echo "Using executable: $XCODE_EXEC"

# Check if it's signed
SIGNATURE=$(codesign -dv "$XCODE_EXEC" 2>&1 | grep "Signature=" || true)
echo "Signature: $SIGNATURE"

# Create app bundle
APP_DIR="/Applications/Pickle Cider.app"
echo "Creating app bundle at: $APP_DIR"

sudo rm -rf "$APP_DIR"
sudo mkdir -p "$APP_DIR/Contents/MacOS"
sudo mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable (preserving signature)
sudo cp -p "$XCODE_EXEC" "$APP_DIR/Contents/MacOS/PickleCider"

# Copy Info.plist
sudo cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Create PkgInfo
echo -n "APPL????" | sudo tee "$APP_DIR/Contents/PkgInfo" > /dev/null

# Generate icon
echo "Generating app icon..."
ICON_DIR="/tmp/pickle-icon"
rm -rf "$ICON_DIR"
mkdir -p "$ICON_DIR"
swift "$PROJECT_DIR/Scripts/generate-icon.swift" "$ICON_DIR" 2>/dev/null
if [ -d "$ICON_DIR/AppIcon.iconset" ]; then
    iconutil -c icns "$ICON_DIR/AppIcon.iconset" -o "/tmp/AppIcon.icns" 2>/dev/null
    sudo cp "/tmp/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
rm -rf "$ICON_DIR"

# Remove quarantine attribute
sudo xattr -cr "$APP_DIR"

# DON'T re-sign - preserve Xcode's signature on the executable
# The bundle itself doesn't need to be signed for FDA to work

echo ""
echo "✅ App bundle created: $APP_DIR"
echo ""
echo "Verifying executable signature..."
codesign -dv "$APP_DIR/Contents/MacOS/PickleCider" 2>&1 | head -5

echo ""
echo "Now:"
echo "1. Open System Settings → Privacy & Security → Full Disk Access"
echo "2. Remove old entries, click + and add '$APP_DIR'"
echo "3. Launch from Applications"
