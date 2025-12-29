#!/bin/bash
set -e

# Create DMG installer for Apple Notes Tools
# Creates a beautiful DMG with drag-to-install layout

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release-universal"
DMG_DIR="$PROJECT_DIR/.build/dmg"
VERSION="${1:-1.0.0}"

APP_NAME="Pickle Cider"
DMG_NAME="Pickle-Cider-v$VERSION"
VOLUME_NAME="Pickle Cider"

echo "Creating DMG Installer v$VERSION"
echo "================================"
echo ""

cd "$PROJECT_DIR"

# Clean previous DMG builds
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR/content"
mkdir -p "$DMG_DIR/resources"

# ============================================
# Step 1: Generate App Icon
# ============================================
echo "Step 1: Generating app icon..."

# Generate iconset
swift "$SCRIPT_DIR/generate-icon.swift" "$DMG_DIR/resources"

# Convert to icns
iconutil -c icns "$DMG_DIR/resources/AppIcon.iconset" -o "$DMG_DIR/resources/AppIcon.icns"
echo "  Created AppIcon.icns"

# ============================================
# Step 2: Create App Bundle
# ============================================
echo ""
echo "Step 2: Creating app bundle..."

APP_BUNDLE="$DMG_DIR/content/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/PickleCider" "$APP_BUNDLE/Contents/MacOS/PickleCider"
chmod +x "$APP_BUNDLE/Contents/MacOS/PickleCider"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy icon
cp "$DMG_DIR/resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc sign the app (required for Full Disk Access to work)
echo "  Signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "  Created: $APP_NAME.app"

# ============================================
# Step 3: Create CLI Tools directory
# ============================================
echo ""
echo "Step 3: Adding CLI tools..."

CLI_DIR="$DMG_DIR/content/CLI Tools"
mkdir -p "$CLI_DIR"

cp "$BUILD_DIR/cider" "$CLI_DIR/cider"
cp "$BUILD_DIR/pickle" "$CLI_DIR/pickle"
chmod +x "$CLI_DIR/cider" "$CLI_DIR/pickle"

# Sign CLI tools
codesign --force --sign - "$CLI_DIR/cider"
codesign --force --sign - "$CLI_DIR/pickle"

# Create install script for CLI tools
cat > "$CLI_DIR/install-cli.command" << 'INSTALL_EOF'
#!/bin/bash
# Install Cider & Pickle CLI tools

echo "Installing Apple Notes Tools CLI..."
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check for /usr/local/bin
if [ ! -d "/usr/local/bin" ]; then
    echo "Creating /usr/local/bin..."
    sudo mkdir -p /usr/local/bin
fi

echo "Installing cider..."
sudo cp "$SCRIPT_DIR/cider" /usr/local/bin/cider
sudo chmod +x /usr/local/bin/cider

echo "Installing pickle..."
sudo cp "$SCRIPT_DIR/pickle" /usr/local/bin/pickle
sudo chmod +x /usr/local/bin/pickle

echo ""
echo "Installation complete!"
echo ""
echo "You can now use:"
echo "  cider --help"
echo "  pickle --help"
echo ""
echo "Press any key to close..."
read -n 1
INSTALL_EOF
chmod +x "$CLI_DIR/install-cli.command"

echo "  Added: cider, pickle, install-cli.command"

# ============================================
# Step 4: Create Applications symlink
# ============================================
echo ""
echo "Step 4: Creating Applications symlink..."
ln -s /Applications "$DMG_DIR/content/Applications"

# ============================================
# Step 5: Create README
# ============================================
echo ""
echo "Step 5: Creating README..."

cat > "$DMG_DIR/content/README.txt" << 'README_EOF'
Apple Notes Tools v1.0.0
========================

Three native macOS tools for Apple Notes.

INSTALLATION
------------

1. GUI App (Pickle Cider):
   Drag "Pickle Cider.app" to the Applications folder.

2. CLI Tools (cider & pickle):
   Open "CLI Tools" folder and double-click "install-cli.command"
   Or manually copy to /usr/local/bin

REQUIREMENTS
------------
- macOS 13.0 (Ventura) or later
- Full Disk Access permission for terminal (CLI tools)
- Automation permission for Notes.app

QUICK START
-----------

GUI App:
  Launch Pickle Cider from Applications

CLI - Sync notes:
  cider init
  cider pull ~/Documents/notes --recursive

CLI - Version history:
  pickle install --interval 30
  pickle status
  pickle history "My Note"

DOCUMENTATION
-------------
https://github.com/damienheiser/apple-notes-tools

LICENSE
-------
MIT License - See LICENSE file for details.

README_EOF

# ============================================
# Step 6: Create DMG background
# ============================================
echo ""
echo "Step 6: Creating DMG background..."

# Create background image using Swift
cat > "$DMG_DIR/create-background.swift" << 'BG_EOF'
#!/usr/bin/env swift
import AppKit

let width: CGFloat = 600
let height: CGFloat = 400

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

// Gradient background
let gradient = NSGradient(colors: [
    NSColor(red: 0.12, green: 0.20, blue: 0.06, alpha: 1.0),
    NSColor(red: 0.08, green: 0.14, blue: 0.04, alpha: 1.0)
])!
gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -45)

// Title text
let title = "Apple Notes Tools"
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .bold),
    .foregroundColor: NSColor.white.withAlphaComponent(0.9)
]
let titleSize = title.size(withAttributes: titleAttrs)
title.draw(at: NSPoint(x: (width - titleSize.width) / 2, y: height - 60), withAttributes: titleAttrs)

// Subtitle
let subtitle = "Drag to Applications to install"
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.6)
]
let subSize = subtitle.size(withAttributes: subAttrs)
subtitle.draw(at: NSPoint(x: (width - subSize.width) / 2, y: height - 90), withAttributes: subAttrs)

// Arrow pointing right (from app to Applications)
let arrowPath = NSBezierPath()
let arrowY: CGFloat = 180
let arrowStartX: CGFloat = 220
let arrowEndX: CGFloat = 380

// Arrow line
arrowPath.move(to: NSPoint(x: arrowStartX, y: arrowY))
arrowPath.line(to: NSPoint(x: arrowEndX - 15, y: arrowY))

// Arrow head
arrowPath.move(to: NSPoint(x: arrowEndX - 25, y: arrowY + 12))
arrowPath.line(to: NSPoint(x: arrowEndX, y: arrowY))
arrowPath.line(to: NSPoint(x: arrowEndX - 25, y: arrowY - 12))

NSColor.white.withAlphaComponent(0.4).setStroke()
arrowPath.lineWidth = 3
arrowPath.lineCapStyle = .round
arrowPath.stroke()

image.unlockFocus()

// Save as PNG
guard let tiffData = image.tiffRepresentation,
      let bitmapRep = NSBitmapImageRep(data: tiffData),
      let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    print("Failed to create background")
    exit(1)
}

let outputPath = CommandLine.arguments[1]
try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("Created background: \(outputPath)")
BG_EOF

swift "$DMG_DIR/create-background.swift" "$DMG_DIR/resources/background.png"

# ============================================
# Step 7: Create temporary DMG
# ============================================
echo ""
echo "Step 7: Creating DMG..."

TEMP_DMG="$DMG_DIR/temp.dmg"
FINAL_DMG="$BUILD_DIR/$DMG_NAME.dmg"

# Calculate size needed (add 50MB buffer)
SIZE_MB=$(du -sm "$DMG_DIR/content" | cut -f1)
SIZE_MB=$((SIZE_MB + 50))

# Create temporary DMG
hdiutil create -srcfolder "$DMG_DIR/content" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "${SIZE_MB}m" \
    "$TEMP_DMG"

# ============================================
# Step 8: Customize DMG appearance
# ============================================
echo ""
echo "Step 8: Customizing DMG appearance..."

# Mount DMG
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG" | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')
echo "  Mounted at: $MOUNT_DIR"

# Create .background directory and copy background
mkdir -p "$MOUNT_DIR/.background"
cp "$DMG_DIR/resources/background.png" "$MOUNT_DIR/.background/background.png"

# Set DMG window appearance using AppleScript
echo "  Configuring window layout..."
osascript << APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 700, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set background picture of viewOptions to file ".background:background.png"

        -- Position items
        set position of item "$APP_NAME.app" of container window to {140, 200}
        set position of item "Applications" of container window to {460, 200}
        set position of item "CLI Tools" of container window to {140, 340}
        set position of item "README.txt" of container window to {460, 340}

        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Set volume icon
cp "$DMG_DIR/resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true

# Unmount
sync
hdiutil detach "$MOUNT_DIR"

# ============================================
# Step 9: Convert to compressed DMG
# ============================================
echo ""
echo "Step 9: Compressing final DMG..."

hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$FINAL_DMG"

# Clean up
rm -f "$TEMP_DMG"

# ============================================
# Done!
# ============================================
echo ""
echo "============================================"
echo "DMG created successfully!"
echo ""
echo "Output: $FINAL_DMG"
echo "Size: $(du -h "$FINAL_DMG" | cut -f1)"
echo ""
echo "Contents:"
echo "  - Pickle Cider.app (GUI)"
echo "  - CLI Tools/"
echo "      - cider"
echo "      - pickle"
echo "      - install-cli.command"
echo "  - Applications (symlink)"
echo "  - README.txt"
echo "============================================"
