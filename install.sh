#!/bin/bash
set -e

INSTALL_DIR="$HOME/spotify-overlay"
BUCKET_FILE="$HOME/.spotify_overlay_bucket"

echo "== Installer =="
echo "This sets up a background script that publishes your Spotify status"
echo "to a free, anonymous storage bucket so your Roblox overlay can read it."
echo "No GitHub token, no git, no Xcode, no account of any kind required."
echo ""

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# --- Create a fresh anonymous kvdb.io bucket (no login, no API key) ---
if [ -f "$BUCKET_FILE" ]; then
    BUCKET_ID=$(cat "$BUCKET_FILE")
    echo "Reusing existing bucket: $BUCKET_ID"
else
    echo "Creating a new anonymous storage bucket..."
    BUCKET_ID=$(curl -s -d "email=noreply@example.com" https://kvdb.io)
    if [ -z "$BUCKET_ID" ]; then
        echo "Failed to create a bucket. Check your internet connection and try again."
        exit 1
    fi
    echo "$BUCKET_ID" > "$BUCKET_FILE"
    echo "Created bucket: $BUCKET_ID"
fi

MUSIC_URL="https://kvdb.io/$BUCKET_ID/music.json"

# --- Write the push script ---
cat > "$INSTALL_DIR/push_music.sh" <<SCRIPT_EOF
#!/bin/bash

MUSIC_URL="$MUSIC_URL"

while true; do
    STATUS="paused"
    TRACK=""
    ARTIST=""
    POS=0
    DUR=1
    FOUND="no"

    # --- Desktop app, only trusted if actually playing ---
    if pgrep -x "Spotify" > /dev/null; then
        APP_STATUS=\$(osascript -e 'tell application "Spotify" to player state' 2>/dev/null)
        if [ "\$APP_STATUS" == "playing" ]; then
            STATUS="playing"
            TRACK=\$(osascript -e 'tell application "Spotify" to name of current track' 2>/dev/null | sed 's/"/\\\\"/g')
            ARTIST=\$(osascript -e 'tell application "Spotify" to artist of current track' 2>/dev/null | sed 's/"/\\\\"/g')
            POS=\$(osascript -e 'tell application "Spotify" to player position' 2>/dev/null | cut -d'.' -f1)
            DUR=\$(osascript -e 'tell application "Spotify" to (duration of current track) / 1000' 2>/dev/null | cut -d'.' -f1)
            FOUND="yes"
        fi
    fi

    # --- Otherwise scan ALL browser tabs (not just active one) for open.spotify.com ---
    if [ "\$FOUND" == "no" ]; then
        CHROME_TITLE=\$(osascript <<'APPLESCRIPT_EOF' 2>/dev/null
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
        if [ -z "\$CHROME_TITLE" ]; then
            SAFARI_TITLE=\$(osascript <<'APPLESCRIPT_EOF' 2>/dev/null
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

        FOUND_TITLE=""
        if [ -n "\$CHROME_TITLE" ]; then
            FOUND_TITLE="\$CHROME_TITLE"
        elif [ -n "\$SAFARI_TITLE" ]; then
            FOUND_TITLE="\$SAFARI_TITLE"
        fi

        if [ -n "\$FOUND_TITLE" ]; then
            CLEAN_TITLE=\$(echo "\$FOUND_TITLE" | sed 's/ - Spotify//g')
            TRACK=\$(echo "\$CLEAN_TITLE" | awk -F ' by ' '{print \$1}')
            ARTIST=\$(echo "\$CLEAN_TITLE" | awk -F ' by ' '{print \$2}')
            STATUS="playing"
            FOUND="yes"
        fi
    fi

    if [ -z "\$TRACK" ]; then TRACK="No Track Playing"; fi
    if [ -z "\$POS" ]; then POS=0; fi
    if [ -z "\$DUR" ]; then DUR=1; fi
    if [ "\$FOUND" == "no" ]; then STATUS="paused"; fi

    JSON_CONTENT="{\\"status\\":\\"\$STATUS\\",\\"track\\":\\"\$TRACK\\",\\"artist\\":\\"\$ARTIST\\",\\"position\\":\$POS,\\"duration\\":\$DUR}"
    echo "\$JSON_CONTENT" > "$INSTALL_DIR/music.json"

    # Write straight to kvdb.io — no auth, no token, no GitHub
    curl -s -X PUT --data-raw "\$JSON_CONTENT" "\$MUSIC_URL" > /dev/null

    sleep 10
done
SCRIPT_EOF

chmod +x "$INSTALL_DIR/push_music.sh"

pkill -f push_music.sh 2>/dev/null || true
sleep 1

echo ""
echo "Installed to $INSTALL_DIR"
echo "Starting the background updater now..."

nohup "$INSTALL_DIR/push_music.sh" > "$INSTALL_DIR/push.log" 2>&1 &
disown

sleep 1
echo ""
echo "======================================================"
echo "Done! Running in the background (PID $!)."
echo ""
echo "Your personal music data URL:"
echo "  $MUSIC_URL"
echo ""
echo "To check status:   cat $INSTALL_DIR/music.json"
echo "To stop it later:  pkill -f push_music.sh"
echo ""
echo "PASTE THIS EXACT SNIPPET into your executor (not just the loadstring"
echo "alone) — the first line tells the overlay which bucket is yours:"
echo ""
echo "_G.SpotifyBucketId = \"$BUCKET_ID\""
echo 'loadstring(game:HttpGet("https://raw.githubusercontent.com/cryptrixz/player/refs/heads/main/overlay.lua"))()'
echo "======================================================"
