#!/bin/bash
set -e

REPO="cryptrixz/player"
BRANCH="main"
INSTALL_DIR="$HOME/spotify-overlay"
API_URL="https://api.github.com/repos/$REPO/contents/music.json"

echo "Dom :3"
echo "This sets up a background script that pushes your Spotify status to GitHub"
echo "so your Roblox overlay can show it. No Xcode or git required."
echo ""

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

read -s -p "Paste your GitHub Personal Access Token (input hidden): " GITHUB_TOKEN
echo ""
if [ -z "$GITHUB_TOKEN" ]; then
    echo "No token entered. Exiting."
    exit 1
fi

TOKEN_FILE="$HOME/.spotify_overlay_token"
echo "$GITHUB_TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

cat > "$INSTALL_DIR/push_music.sh" <<'SCRIPT_EOF'
#!/bin/bash

REPO="cryptrixz/player"
FILE_PATH="music.json"
BRANCH="main"
TOKEN_FILE="$HOME/.spotify_overlay_token"
API_URL="https://api.github.com/repos/$REPO/contents/$FILE_PATH"

if [ ! -f "$TOKEN_FILE" ]; then
    echo "Token file not found at $TOKEN_FILE. Run install.sh again."
    exit 1
fi
GITHUB_TOKEN=$(cat "$TOKEN_FILE")

while true; do
    STATUS="paused"
    TRACK=""
    ARTIST=""
    POS=0
    DUR=1
    FOUND="no"

    # --- Try desktop app first, but only USE it if it's actually playing ---
    if pgrep -x "Spotify" > /dev/null; then
        APP_STATUS=$(osascript -e 'tell application "Spotify" to player state' 2>/dev/null)
        if [ "$APP_STATUS" == "playing" ]; then
            STATUS="playing"
            TRACK=$(osascript -e 'tell application "Spotify" to name of current track' 2>/dev/null | sed 's/"/\\"/g')
            ARTIST=$(osascript -e 'tell application "Spotify" to artist of current track' 2>/dev/null | sed 's/"/\\"/g')
            POS=$(osascript -e 'tell application "Spotify" to player position' 2>/dev/null | cut -d'.' -f1)
            DUR=$(osascript -e 'tell application "Spotify" to (duration of current track) / 1000' 2>/dev/null | cut -d'.' -f1)
            FOUND="yes"
        fi
    fi

    # --- If desktop app isn't playing, check browser tabs instead ---
    # Check the tab's URL (not just its title) so we only match real
    # open.spotify.com tabs, not any tab that happens to mention "Spotify".
    if [ "$FOUND" == "no" ]; then
        CHROME_URL=$(osascript -e 'tell application "Google Chrome" to get URL of active tab of first window' 2>/dev/null)
        CHROME_TITLE=$(osascript -e 'tell application "Google Chrome" to get title of active tab of first window' 2>/dev/null)
        SAFARI_URL=$(osascript -e 'tell application "Safari" to get URL of current tab of first window' 2>/dev/null)
        SAFARI_TITLE=$(osascript -e 'tell application "Safari" to get name of current tab of first window' 2>/dev/null)

        if [[ "$CHROME_URL" == *"open.spotify.com"* ]]; then
            CLEAN_TITLE=$(echo "$CHROME_TITLE" | sed 's/ - Spotify//g')
            TRACK=$(echo "$CLEAN_TITLE" | awk -F ' by ' '{print $1}')
            ARTIST=$(echo "$CLEAN_TITLE" | awk -F ' by ' '{print $2}')
            STATUS="playing"
            FOUND="yes"
        elif [[ "$SAFARI_URL" == *"open.spotify.com"* ]]; then
            CLEAN_TITLE=$(echo "$SAFARI_TITLE" | sed 's/ - Spotify//g')
            TRACK=$(echo "$CLEAN_TITLE" | awk -F ' by ' '{print $1}')
            ARTIST=$(echo "$CLEAN_TITLE" | awk -F ' by ' '{print $2}')
            STATUS="playing"
            FOUND="yes"
        fi
    fi

    if [ -z "$TRACK" ]; then TRACK="No Track Playing"; fi
    if [ -z "$POS" ]; then POS=0; fi
    if [ -z "$DUR" ]; then DUR=1; fi
    if [ "$FOUND" == "no" ]; then STATUS="paused"; fi

    JSON_CONTENT="{\"status\":\"$STATUS\",\"track\":\"$TRACK\",\"artist\":\"$ARTIST\",\"position\":$POS,\"duration\":$DUR}"
    echo "$JSON_CONTENT" > "$HOME/spotify-overlay/music.json"

    ENCODED_CONTENT=$(echo -n "$JSON_CONTENT" | base64)

    CURRENT_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "$API_URL?ref=$BRANCH" | grep -m1 '"sha"' | sed -E 's/.*"sha": *"([^"]+)".*/\1/')

    if [ -n "$CURRENT_SHA" ]; then
        BODY="{\"message\":\"sync\",\"content\":\"$ENCODED_CONTENT\",\"sha\":\"$CURRENT_SHA\",\"branch\":\"$BRANCH\"}"
    else
        BODY="{\"message\":\"sync\",\"content\":\"$ENCODED_CONTENT\",\"branch\":\"$BRANCH\"}"
    fi

    curl -s -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$BODY" \
        "$API_URL" > /dev/null

    sleep 10
done
SCRIPT_EOF

chmod +x "$INSTALL_DIR/push_music.sh"

# Kill any old instance before starting a fresh one
pkill -f push_music.sh 2>/dev/null || true
sleep 1

echo ""
echo "Installed to $INSTALL_DIR"
echo "Starting the background updater now (logs at $INSTALL_DIR/push.log)..."

nohup "$INSTALL_DIR/push_music.sh" > "$INSTALL_DIR/push.log" 2>&1 &
disown

sleep 1
echo ""
echo "Done. It's now running in the background (PID $!)."
echo "To stop it later:  pkill -f push_music.sh"
echo "To check status:   cat $INSTALL_DIR/music.json"
echo ""
echo "In Roblox, run your loadstring as usual — no changes needed there:"
echo 'loadstring(game:HttpGet("https://raw.githubusercontent.com/cryptrixz/player/refs/heads/main/overlay.lua"))()'
