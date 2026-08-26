#!/bin/bash
set -e

INSTALL_DIR="$HOME/spotify-overlay-app"
REPO_RAW="https://raw.githubusercontent.com/cryptrixz/player/refs/heads/main"

echo "== Spotify Desktop Overlay Setup =="
echo "This installs a small floating window that always stays on top of"
echo "everything else, including fullscreen apps like Roblox."
echo ""

# --- Check for Node.js, install via Homebrew if missing ---
if ! command -v node &> /dev/null; then
    echo "Node.js not found."
    if ! command -v brew &> /dev/null; then
        echo "Homebrew not found either. Installing Homebrew first (this will"
        echo "ask for your password)..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
    fi
    echo "Installing Node.js via Homebrew..."
    brew install node
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

# Kill any previous instance first
pkill -f "electron $INSTALL_DIR" 2>/dev/null || true
sleep 1

# Launch in the background so this terminal window doesn't need to stay open
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
