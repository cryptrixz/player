while true; do
    STATUS="paused"
    TRACK=""
    ARTIST=""
    POS=0
    DUR=1

    if pgrep -x "Spotify" > /dev/null; then
        STATUS=$(osascript -e 'tell application "Spotify" to player state' 2>/dev/null)
        TRACK=$(osascript -e 'tell application "Spotify" to name of current track' 2>/dev/null | sed 's/"/\\"/g')
        ARTIST=$(osascript -e 'tell application "Spotify" to artist of current track' 2>/dev/null | sed 's/"/\\"/g')
        POS=$(osascript -e 'tell application "Spotify" to player position' 2>/dev/null | cut -d'.' -f1)
        DUR=$(osascript -e 'tell application "Spotify" to (duration of current track) / 1000' 2>/dev/null | cut -d'.' -f1)
    else
        CHROME_TITLE=$(osascript -e 'tell application "Google Chrome" to to get title of active tab of first window' 2>/dev/null)
        SAFARI_TITLE=$(osascript -e 'tell application "Safari" to to get name of current tab of first window' 2>/dev/null)
        
        if [[ "$CHROME_TITLE" == *"Spotify"* ]]; then
            CLEAN_TITLE=$(echo "$CHROME_TITLE" | sed 's/ - Spotify//g')
            TRACK=$(echo "$CLEAN_TITLE" | awk -F ' by ' '{print $1}')
            ARTIST=$(echo "$CLEAN_TITLE" | awk -F ' by ' '{print $2}')
            STATUS="playing"
        elif [[ "$SAFARI_TITLE" == *"Spotify"* ]]; then
            CLEAN_TITLE=$(echo "$SAFARI_TITLE" | sed 's/ - Spotify//g')
            TRACK=$(echo "$CLEAN_TITLE" | awk -F ' by ' '{print $1}')
            ARTIST=$(echo "$CLEAN_TITLE" | awk -F ' by ' '{print $2}')
            STATUS="playing"
        fi
    fi

    if [ -z "$TRACK" ]; then TRACK="No Track Playing"; fi
    if [ -z "$POS" ]; then POS=0; fi
    if [ -z "$DUR" ]; then DUR=1; fi
    
    echo "{\"status\":\"$STATUS\",\"track\":\"$TRACK\",\"artist\":\"$ARTIST\",\"position\":$POS,\"duration\":$DUR}" > music.json
    
    git add music.json
    git commit -m "sync" --quiet
    git push --quiet
         
    sleep 10
done
