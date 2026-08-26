#!/bin/bash
set -e

# === Colors ===
BLUE='\033[38;5;33m'      # bright blue
DARKBLUE='\033[38;5;24m'  # darker blue
BOLD='\033[1m'
RESET='\033[0m'

INSTALL_DIR="$HOME/spotify-overlay-app"
REPO_RAW="https://raw.githubusercontent.com/cryptrixz/player/refs/heads/main"

echo -e "${DARKBLUE}┌─────────────────────────────────────┐${RESET}"
echo -e "${DARKBLUE}│${RESET}  ${BOLD}${BLUE}kitty123 Installer${RESET}                  ${DARKBLUE}│${RESET}"
echo -e "${DARKBLUE}└─────────────────────────────────────┘${RESET}"
echo ""
echo -e "${BLUE}kitty123${RESET}::[$(date +%H:%M:%S)] Setting up Spotify overlay..."
echo ""
echo "This installs a small floating window that always stays on top of"
echo "everything else, including fullscreen apps like Roblox."
echo ""

# --- Check for Node.js, install via the official .pkg installer if missing ---
if ! command -v node &> /dev/null; then
    echo -e "${BLUE}kitty123${RESET}::[$(date +%H:%M:%S)] Node.js not found, downloading installer..."
    ARCH=$(uname -m)
    if [ "$ARCH" == "arm64" ]; then
        NODE_URL="https://nodejs.org/dist/v20.17.0/node-v20.17.0.pkg"
    else
        NODE_URL="https://nodejs.org/dist/v20.17.0/node-v20.17.0-x64.pkg"
    fi
    curl -fsSL "$NODE_URL" -o /tmp/node-installer.pkg
    echo -e "${BLUE}kitty123${RESET}::[$(date +%H:%M:%S)] admin access required — enter your mac password if asked"
    sudo installer -pkg /tmp/node-installer.pkg -target /
    rm /tmp/node-installer.pkg
    export PATH="/usr/local/bin:$PATH"
fi

echo -e "${BLUE}kitty123${RESET}::[$(date +%H:%M:%S)] node.js ready: $(node --version)"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo -e "${BLUE}kitty123${RESET}::[$(date +%H:%M:%S)] downloading app files..."
curl -fsSL "$REPO_RAW/app.js" -o app.js
curl -fsSL "$REPO_RAW/overlay.html" -o overlay.html
curl -fsSL "$REPO_RAW/electron-package.json" -o package.json

echo -e "${BLUE}kitty123${RESET}::[$(date +%H:%M:%S)] installing dependencies..."
npm install --silent

echo ""
echo -e "${DARKBLUE}────────────────────────────────────────${RESET}"
echo -e "${BLUE}kitty123${RESET}::[$(date +%H:%M:%S)] setup complete, launching overlay..."
echo -e "${DARKBLUE}────────────────────────────────────────${RESET}"

# Kill any previous instance first
pkill -f "electron $INSTALL_DIR" 2>/dev/null || true
sleep 1

nohup npm start > "$INSTALL_DIR/overlay.log" 2>&1 &
disown

sleep 2
echo ""
echo -e "${BLUE}kitty123${RESET}::[$(date +%H:%M:%S)] done! overlay is running near the bottom of your screen"
echo -e "${BLUE}kitty123${RESET}::[$(date +%H:%M:%S)] stays on top even when Roblox is fullscreen"
echo ""
echo -e "  ${DARKBLUE}stop:${RESET}    pkill -f electron"
echo -e "  ${DARKBLUE}restart:${RESET} cd $INSTALL_DIR && npm start"
echo -e "${DARKBLUE}────────────────────────────────────────${RESET}"
