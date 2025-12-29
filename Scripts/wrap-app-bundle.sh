#!/bin/bash
# Wrap the built executable in an .app bundle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Find the Xcode-built executable
XCODE_EXEC=$(find ~/Library/Developer/Xcode/DerivedData -name "PickleCider" -type f -perm +111 2>/dev/null | head -1)

if [ -z "$XCODE_EXEC" ]; then
    # Try the Release folder the user mentioned
    XCODE_EXEC=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Release/PickleCider" -type f 2>/dev/null | head -1)
fi

if [ -z "$XCODE_EXEC" ]; then
    echo "Could not find Xcode-built PickleCider executable"
    echo "Falling back to swift build..."
    swift build -c release
    XCODE_EXEC="$PROJECT_DIR/.build/release/PickleCider"
fi

echo "Using executable: $XCODE_EXEC"

# Create app bundle
APP_DIR="/Applications/Pickle Cider.app"
echo "Creating app bundle at: $APP_DIR"

sudo rm -rf "$APP_DIR"
sudo mkdir -p "$APP_DIR/Contents/MacOS"
sudo mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
sudo cp "$XCODE_EXEC" "$APP_DIR/Contents/MacOS/PickleCider"
sudo chmod +x "$APP_DIR/Contents/MacOS/PickleCider"

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

# Re-sign the app bundle (uses the same signature as the executable)
echo "Signing app bundle..."
sudo codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "✅ App bundle created: $APP_DIR"
echo ""
echo "Now:"
echo "1. Open System Settings → Privacy & Security → Full Disk Access"
echo "2. Remove old 'Pickle Cider' entry if present"
echo "3. Click + and add '/Applications/Pickle Cider.app'"
echo "4. Quit and reopen the app"
