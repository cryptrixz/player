#!/bin/bash
set -e

INSTALL_DIR="$HOME/spotify-overlay-app"
REPO_RAW="https://raw.githubusercontent.com/cryptrixz/player/refs/heads/main"

echo "== Spotify Desktop Overlay Setup =="
echo "This installs a small floating window that always stays on top of"
echo "everything else, including fullscreen apps like Roblox."
echo ""

if ! command -v node &> /dev/null; then
    echo "Node.js not found. Downloading the official installer..."
    ARCH=$(uname -m)
    if [ "$ARCH" == "arm64" ]; then
        NODE_URL="https://nodejs.org/dist/v20.17.0/node-v20.17.0.pkg"
    else
        NODE_URL="https://nodejs.org/dist/v20.17.0/node-v20.17.0-x64.pkg"
    fi
    curl -fsSL "$NODE_URL" -o /tmp/node-installer.pkg
    echo "Installing Node.js (this will ask for your password — normal macOS"
    echo "installer prompt, not Xcode)..."
    sudo installer -pkg /tmp/node-installer.pkg -target /
    rm /tmp/node-installer.pkg
    export PATH="/usr/local/bin:$PATH"
fi

echo "Node.js found: $(node --version)"
echo ""

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "Downloading app files..."
curl -fsSL "$REPO_RAW/app.js" -o app.js
curl -fsSL "$REPO_RAW/overlay.html" -o overlay.html
curl -fsSL "$REPO_RAW/package.json" -o package.json

echo "Installing dependencies (this may take a minute)..."
npm install --silent

echo ""
echo "======================================================"
echo "Setup complete. Launching the overlay now..."
echo "======================================================"

pkill -f "electron $INSTALL_DIR" 2>/dev/null || true
sleep 1

nohup npm start > "$INSTALL_DIR/overlay.log" 2>&1 &
disown

sleep 2
echo ""
echo "Done! The overlay should now be visible near the bottom of your screen,"
echo "and will stay on top even when Roblox is fullscreen."
echo ""
echo "To stop it:    pkill -f electron"
echo "To run again:  cd $INSTALL_DIR && npm start"
echo "======================================================"
