#!/bin/bash
set -e

RAILWAY_URL="https://player-production-7e33.up.railway.app"
INSTALL_DIR="$HOME/spotify-overlay"
MUSIC_URL="${RAILWAY_URL%/}/music"
OVERLAY_RAW="https://raw.githubusercontent.com/cryptrixz/player/refs/heads/main/overlay.lua"
PLIST="$HOME/Library/LaunchAgents/com.spotify.overlay.plist"
LABEL="com.spotify.overlay"

echo "== Spotify Overlay Setup =="
mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$INSTALL_DIR/push_music.sh" <<'SCRIPT_EOF'
#!/bin/bash
MUSIC_URL="__MUSIC_URL__"
INSTALL_DIR="__INSTALL_DIR__"
LAST_ART_KEY=""
LAST_ART_URL=""

urlencode() {
  python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1" 2>/dev/null || echo "$1"
}

fetch_artwork() {
  local track="$1"
  local artist="$2"
  local key="${artist}|||${track}"
  if [ "$key" = "$LAST_ART_KEY" ] && [ -n "$LAST_ART_URL" ]; then
    echo "$LAST_ART_URL"
    return
  fi
  local q
  q=$(urlencode "${artist} ${track}")
  local url
  url=$(curl -s --max-time 4 "https://itunes.apple.com/search?term=${q}&entity=song&limit=1" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    r = d.get('results') or []
    if r:
        u = r[0].get('artworkUrl100') or ''
        print(u.replace('100x100bb','300x300bb').replace('100x100','300x300'))
    else:
        print('')
except Exception:
    print('')
" 2>/dev/null)
  LAST_ART_KEY="$key"
  LAST_ART_URL="$url"
  echo "$url"
}

while true; do
    STATUS="paused"
    TRACK=""
    ARTIST=""
    POS=0
    DUR=1
    IMAGE=""
    FOUND="no"

    if pgrep -x "Spotify" > /dev/null; then
        APP_STATUS=$(osascript -e 'tell application "Spotify" to player state as string' 2>/dev/null || true)
        if [ "$APP_STATUS" = "playing" ] || [ "$APP_STATUS" = "paused" ]; then
            STATUS="$APP_STATUS"
            TRACK=$(osascript -e 'tell application "Spotify" to name of current track' 2>/dev/null | sed 's/"/\\"/g' || true)
            ARTIST=$(osascript -e 'tell application "Spotify" to artist of current track' 2>/dev/null | sed 's/"/\\"/g' || true)
            POS=$(osascript -e 'tell application "Spotify" to (player position as integer)' 2>/dev/null || true)
            DUR=$(osascript -e 'tell application "Spotify" to ((duration of current track) / 1000 as integer)' 2>/dev/null || true)
            if [ -n "$TRACK" ]; then
                FOUND="yes"
                IMAGE=$(fetch_artwork "$TRACK" "$ARTIST")
            fi
        fi
    fi

    if [ "$FOUND" = "no" ]; then
        CHROME_TITLE=$(osascript <<'APPLESCRIPT_EOF' 2>/dev/null || true
tell application "Google Chrome"
    if it is running then
        repeat with w in windows
            repeat with t in tabs of w
                if (URL of t) contains "open.spotify.com" then
                    return title of t
                end if
            end repeat
        end repeat
    end if
    return ""
end tell
APPLESCRIPT_EOF
)
        if [ -z "$CHROME_TITLE" ]; then
            SAFARI_TITLE=$(osascript <<'APPLESCRIPT_EOF' 2>/dev/null || true
tell application "Safari"
    if it is running then
        repeat with w in windows
            repeat with t in tabs of w
                if (URL of t) contains "open.spotify.com" then
                    return name of t
                end if
            end repeat
        end repeat
    end if
    return ""
end tell
APPLESCRIPT_EOF
)
        fi
        FOUND_TITLE="${CHROME_TITLE:-$SAFARI_TITLE}"
        if [ -n "$FOUND_TITLE" ]; then
            CLEAN_TITLE=$(echo "$FOUND_TITLE" | sed 's/ - Spotify//g')
            TRACK=$(echo "$CLEAN_TITLE" | awk -F ' by ' '{print $1}')
            ARTIST=$(echo "$CLEAN_TITLE" | awk -F ' by ' '{print $2}')
            STATUS="playing"
            FOUND="yes"
            POS=0
            DUR=180
            IMAGE=$(fetch_artwork "$TRACK" "$ARTIST")
        fi
    fi

    if [ -z "$TRACK" ]; then TRACK="No Track Playing"; fi
    if ! [[ "$POS" =~ ^[0-9]+$ ]]; then POS=0; fi
    if ! [[ "$DUR" =~ ^[0-9]+$ ]] || [ "$DUR" -lt 1 ]; then DUR=1; fi
    if [ "$FOUND" = "no" ]; then STATUS="paused"; IMAGE=""; fi

    JSON_CONTENT=$(python3 -c "
import json
print(json.dumps({
  'status': '''$STATUS''',
  'track': '''$TRACK''',
  'artist': '''$ARTIST''',
  'position': int('$POS'),
  'duration': int('$DUR'),
  'image': '''$IMAGE'''
}))
" 2>/dev/null)

    if [ -z "$JSON_CONTENT" ]; then
      JSON_CONTENT="{\"status\":\"$STATUS\",\"track\":\"$TRACK\",\"artist\":\"$ARTIST\",\"position\":$POS,\"duration\":$DUR,\"image\":\"$IMAGE\"}"
    fi

    echo "$JSON_CONTENT" > "$INSTALL_DIR/music.json"
    curl -s -X POST "$MUSIC_URL" \
        -H "Content-Type: application/json" \
        -d "$JSON_CONTENT" > /dev/null 2>&1 || true
    sleep 2
done
SCRIPT_EOF

sed -i '' "s|__MUSIC_URL__|$MUSIC_URL|g" "$INSTALL_DIR/push_music.sh"
sed -i '' "s|__INSTALL_DIR__|$INSTALL_DIR|g" "$INSTALL_DIR/push_music.sh"
chmod +x "$INSTALL_DIR/push_music.sh"

echo "Checking Accessibility..."
osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1 || {
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    echo "Enable Terminal/iTerm in Accessibility, then press Enter."
    read -r
}

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f "push_music.sh" 2>/dev/null || true
sleep 1

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$INSTALL_DIR/push_music.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/push.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/push.log</string>
</dict>
</plist>
PLIST_EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null || true

sleep 2
echo ""
echo "======================================================"
echo "Always-on scanner installed."
echo "Check:  cat $INSTALL_DIR/music.json"
echo "Backend: curl $MUSIC_URL"
echo "Log:     tail -f $INSTALL_DIR/push.log"
echo ""
echo "Roblox (once):"
echo "loadstring(game:HttpGet(\"$OVERLAY_RAW\"))()"
echo "======================================================"
