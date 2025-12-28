#!/bin/bash
set -e

# Install script for Cider & Pickle
# Builds and installs to /usr/local/bin

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

echo "Installing Cider & Pickle"
echo "========================="
echo ""

cd "$PROJECT_DIR"

# Build release
echo "Building release..."
swift build -c release

# Check if we need sudo
if [ -w "$INSTALL_DIR" ]; then
    SUDO=""
else
    SUDO="sudo"
    echo "Installing to $INSTALL_DIR (requires sudo)..."
fi

# Install binaries
echo "Installing cider..."
$SUDO cp .build/release/cider "$INSTALL_DIR/"
$SUDO chmod +x "$INSTALL_DIR/cider"

echo "Installing pickle..."
$SUDO cp .build/release/pickle "$INSTALL_DIR/"
$SUDO chmod +x "$INSTALL_DIR/pickle"

echo ""
echo "Installation complete!"
echo ""
echo "Installed to:"
echo "  $INSTALL_DIR/cider"
echo "  $INSTALL_DIR/pickle"
echo ""
echo "Quick start:"
echo "  cider --help"
echo "  pickle --help"
echo ""
echo "To set up Pickle daemon:"
echo "  pickle install"
