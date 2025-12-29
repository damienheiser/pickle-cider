#!/bin/bash
set -e

# Pickle Cider - Quick Install Script
# Builds and installs with your local development certificate

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo ""
echo "  🫙 Pickle Cider Installer"
echo "  ========================="
echo ""

cd "$PROJECT_DIR"

# Check for Xcode command line tools
if ! xcode-select -p &>/dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo ""
    echo "Please run this script again after installation completes."
    exit 1
fi

# Build release
echo "Building Pickle Cider..."
swift build -c release

# Build app bundle with signing
echo ""
"$SCRIPT_DIR/build-app-bundle.sh"

BUILD_DIR="$PROJECT_DIR/.build/release"

# Install app
echo ""
echo "Installing to Applications..."
cp -r "$BUILD_DIR/Pickle Cider.app" /Applications/

# Install CLI tools
echo "Installing CLI tools to /usr/local/bin..."
sudo mkdir -p /usr/local/bin
sudo cp "$BUILD_DIR/cider" /usr/local/bin/
sudo cp "$BUILD_DIR/pickle" /usr/local/bin/

echo ""
echo "================================"
echo "  Installation Complete! 🎉"
echo "================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Open System Settings → Privacy & Security → Full Disk Access"
echo "2. Click + and add 'Pickle Cider' from Applications"
echo "3. Also add 'Terminal' if using CLI tools"
echo "4. Launch Pickle Cider from Applications"
echo ""
echo "CLI tools installed:"
echo "  cider --help"
echo "  pickle --help"
echo ""
