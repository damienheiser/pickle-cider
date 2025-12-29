#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🫙 Building Pickle Cider (all components)"
echo "=========================================="
echo ""

cd "$PROJECT_DIR"

# Pull latest
git pull 2>/dev/null || true

# Build all three executables
echo "Building release binaries..."
swift build -c release

BUILD_DIR="$PROJECT_DIR/.build/release"

echo ""
echo "Built:"
ls -la "$BUILD_DIR/cider" "$BUILD_DIR/pickle" "$BUILD_DIR/PickleCider"

# Try to find a signing identity
echo ""
echo "Looking for signing identity..."
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -E "Apple Development|Developer ID|Pickle Cider" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)

# If no identity, create a local development certificate
if [ -z "$IDENTITY" ]; then
    echo "No signing identity found. Creating local certificate..."
    "$SCRIPT_DIR/create-signing-cert.sh"
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Pickle Cider" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
fi

if [ -z "$IDENTITY" ]; then
    echo "No signing identity in keychain."
    echo ""
    echo "Your certificate is cloud-managed by Xcode and cannot be accessed from CLI."
    echo ""

    # Check if user has already built in Xcode
    XCODE_PICKLE=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Release/PickleCider" -type f -perm +111 2>/dev/null | head -1)

    if [ -n "$XCODE_PICKLE" ]; then
        echo "Found Xcode-built binary: $XCODE_PICKLE"
        echo "Checking signature..."
        XCODE_SIG=$(codesign -dv "$XCODE_PICKLE" 2>&1 | grep "Signature=" || echo "")
        echo "  $XCODE_SIG"

        if [[ "$XCODE_SIG" != *"adhoc"* ]] && [[ -n "$XCODE_SIG" ]]; then
            echo ""
            echo "Using properly-signed Xcode binary!"
            cp "$XCODE_PICKLE" "$BUILD_DIR/PickleCider"
        fi
    fi

    # If we don't have a signed binary, provide instructions
    CURRENT_SIG=$(codesign -dv "$BUILD_DIR/PickleCider" 2>&1 | grep "Signature=" || echo "adhoc")
    if [[ "$CURRENT_SIG" == *"adhoc"* ]]; then
        echo ""
        echo "================================================"
        echo "TO GET PROPERLY SIGNED BINARIES FOR FULL DISK ACCESS:"
        echo ""
        echo "1. Open Package.swift in Xcode:"
        echo "   open Package.swift"
        echo ""
        echo "2. In Xcode:"
        echo "   - Select 'PickleCider' scheme (top left dropdown)"
        echo "   - Select 'My Mac' as destination"
        echo "   - Product → Build For → Profiling (⇧⌘I)"
        echo ""
        echo "3. Then run:"
        echo "   ./Scripts/wrap-app-bundle.sh"
        echo ""
        echo "This will create a properly signed app bundle."
        echo "================================================"
        echo ""
        echo "Continuing with ad-hoc signed binaries for now..."
        echo "(These work but may not be able to access Full Disk Access)"
    fi
else
    echo "Found identity: $IDENTITY"
    echo "Signing binaries..."
    codesign --force --sign "$IDENTITY" "$BUILD_DIR/cider"
    codesign --force --sign "$IDENTITY" "$BUILD_DIR/pickle"
    codesign --force --sign "$IDENTITY" "$BUILD_DIR/PickleCider"
fi

# Create app bundle
echo ""
echo "Creating app bundle..."
APP_DIR="/Applications/Pickle Cider.app"
sudo rm -rf "$APP_DIR"
sudo mkdir -p "$APP_DIR/Contents/MacOS"
sudo mkdir -p "$APP_DIR/Contents/Resources"

sudo cp "$BUILD_DIR/PickleCider" "$APP_DIR/Contents/MacOS/PickleCider"
sudo cp "$BUILD_DIR/pickle" "$APP_DIR/Contents/MacOS/pickle"
sudo cp "$BUILD_DIR/cider" "$APP_DIR/Contents/MacOS/cider"
sudo cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
echo -n "APPL????" | sudo tee "$APP_DIR/Contents/PkgInfo" > /dev/null

# Generate icon
ICON_DIR="/tmp/pickle-icon"
rm -rf "$ICON_DIR" && mkdir -p "$ICON_DIR"
swift "$PROJECT_DIR/Scripts/generate-icon.swift" "$ICON_DIR" 2>/dev/null || true
if [ -d "$ICON_DIR/AppIcon.iconset" ]; then
    iconutil -c icns "$ICON_DIR/AppIcon.iconset" -o "/tmp/AppIcon.icns" 2>/dev/null
    sudo cp "/tmp/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Fix permissions so bundle can be read
sudo chmod 644 "$APP_DIR/Contents/Info.plist"
sudo chmod -R a+r "$APP_DIR"

# Sign the whole bundle
if [ -n "$IDENTITY" ]; then
    echo "Signing app bundle..."
    sudo codesign --force --deep --sign "$IDENTITY" "$APP_DIR"
fi

# Remove quarantine
sudo xattr -cr "$APP_DIR"

# Install CLI tools
echo ""
echo "Installing CLI tools..."
sudo mkdir -p /usr/local/bin
sudo cp "$BUILD_DIR/cider" /usr/local/bin/cider
sudo cp "$BUILD_DIR/pickle" /usr/local/bin/pickle
sudo chmod +x /usr/local/bin/cider /usr/local/bin/pickle
sudo xattr -cr /usr/local/bin/cider /usr/local/bin/pickle

# Install and start the Pickle daemon
echo ""
echo "Setting up Pickle daemon..."
mkdir -p ~/.pickle/logs

# Install daemon (creates launchd plist)
/usr/local/bin/pickle install --force 2>/dev/null || /usr/local/bin/pickle install 2>/dev/null || true

# Load daemon
launchctl load ~/Library/LaunchAgents/com.pickle.daemon.plist 2>/dev/null || true

echo ""
echo "=========================================="
echo "✅ Build complete!"
echo ""
echo "Installed:"
echo "  📱 /Applications/Pickle Cider.app"
echo "  🍺 /usr/local/bin/cider"
echo "  🥒 /usr/local/bin/pickle"
echo ""
echo "Daemon status:"
/usr/local/bin/pickle status 2>/dev/null | grep -E "Daemon:|✓|✗|⚠" || echo "  Run: pickle status"
echo ""
echo "Signatures:"
codesign -dv "$APP_DIR/Contents/MacOS/PickleCider" 2>&1 | grep -E "Authority" | head -1 || true
echo ""
echo "=========================================="
echo "NEXT STEPS:"
echo ""
echo "1. Grant Full Disk Access to the app:"
echo "   System Settings → Privacy & Security → Full Disk Access"
echo "   Click + and add '/Applications/Pickle Cider.app'"
echo ""
echo "2. Grant FDA to the daemon (for automatic version tracking):"
echo "   In Full Disk Access, click +"
echo "   Press Cmd+Shift+G, enter: /Applications/Pickle Cider.app/Contents/MacOS/pickle"
echo ""
echo "3. Restart the daemon:"
echo "   pickle stop && pickle start"
echo ""
echo "4. Check status: pickle status"
echo "=========================================="
