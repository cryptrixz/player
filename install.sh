#!/bin/bash
set -e

RAILWAY_URL="https://player-production-7e33.up.railway.app"
INSTALL_DIR="$HOME/spotify-overlay"
MUSIC_URL="${RAILWAY_URL%/}/music"
PLIST="$HOME/Library/LaunchAgents/com.spotify.overlay.plist"
LABEL="com.spotify.overlay"
OVERLAY_HTML="$INSTALL_DIR/overlay.html"

echo "== Spotify Mac Overlay (no executor) =="
mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$INSTALL_DIR/push_music.sh" << 'SCRIPT_EOF'
#!/bin/bash
MUSIC_URL="__MUSIC_URL__"
LAST_ART_KEY=""
LAST_ART_URL=""

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

time_to_sec() {
  local t; t=$(printf '%s' "$1" | tr -d '[:space:]')
  if [[ "$t" =~ ^([0-9]+):([0-9]+)$ ]]; then
    echo $((10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]}))
  else echo 0; fi
}

fetch_artwork() {
  local track="$1" artist="$2" key="${artist}|||${track}"
  if [ "$key" = "$LAST_ART_KEY" ] && [ -n "$LAST_ART_URL" ]; then printf '%s' "$LAST_ART_URL"; return; fi
  local q raw art
  q=$(printf '%s %s' "$artist" "$track" | sed 's/ /+/g; s/&/%26/g; s/,/%2C/g')
  raw=$(curl -s --max-time 5 "https://itunes.apple.com/search?term=${q}&entity=song&limit=5" 2>/dev/null || true)
  art=$(printf '%s' "$raw" | grep -o '"artworkUrl100":"[^"]*"' | head -1 | sed 's/"artworkUrl100":"//;s/"$//;s/\\//g;s/100x100bb/600x600bb/g;s/100x100/600x600/g')
  if [ -z "$art" ]; then
    q=$(printf '%s' "$track" | sed 's/ /+/g')
    raw=$(curl -s --max-time 5 "https://itunes.apple.com/search?term=${q}&entity=song&limit=5" 2>/dev/null || true)
    art=$(printf '%s' "$raw" | grep -o '"artworkUrl100":"[^"]*"' | head -1 | sed 's/"artworkUrl100":"//;s/"$//;s/\\//g;s/100x100bb/600x600bb/g;s/100x100/600x600/g')
  fi
  LAST_ART_KEY="$key"; LAST_ART_URL="$art"; printf '%s' "$art"
}

fetch_dur() {
  local track="$1" artist="$2" q raw ms
  q=$(printf '%s %s' "$artist" "$track" | sed 's/ /+/g; s/&/%26/g')
  raw=$(curl -s --max-time 4 "https://itunes.apple.com/search?term=${q}&entity=song&limit=1" 2>/dev/null || true)
  ms=$(printf '%s' "$raw" | grep -o '"trackTimeMillis":[0-9]*' | head -1 | grep -o '[0-9]*')
  if [ -n "$ms" ] && [ "$ms" -gt 1000 ] 2>/dev/null; then echo $((ms / 1000)); else echo 0; fi
}

parse_title() {
  local title="$1" clean
  clean=$(printf '%s' "$title" | sed 's/ - Spotify.*//; s/ on Spotify.*//; s/ • Spotify.*//')
  if printf '%s' "$clean" | grep -qi ' by '; then
    printf '%s\n%s' "$(printf '%s' "$clean" | sed 's/ [Bb]y .*//')" "$(printf '%s' "$clean" | sed 's/.* [Bb]y //')"
  elif printf '%s' "$clean" | grep -q ' · '; then
    printf '%s\n%s' "$(printf '%s' "$clean" | sed 's/ · .*//')" "$(printf '%s' "$clean" | sed 's/.* · //')"
  else
    printf '%s\n' "$clean"
  fi
}

while true; do
  STATUS="paused"; TRACK=""; ARTIST=""; POS=0; DUR=1; IMAGE=""; FOUND="no"

  if pgrep -x "Spotify" >/dev/null 2>&1 || pgrep -f "Spotify.app" >/dev/null 2>&1; then
    ST=$(osascript -e 'tell application "Spotify" to player state as string' 2>/dev/null | tr -d '\r\n' | tr '[:upper:]' '[:lower:]')
    if [ "$ST" = "playing" ] || [ "$ST" = "paused" ]; then
      STATUS="$ST"
      TRACK=$(osascript -e 'tell application "Spotify" to name of current track as string' 2>/dev/null | tr -d '\r\n')
      ARTIST=$(osascript -e 'tell application "Spotify" to artist of current track as string' 2>/dev/null | tr -d '\r\n')
      POS=$(osascript -e 'tell application "Spotify" to player position as string' 2>/dev/null | awk -F. '{print $1}')
      DUR_MS=$(osascript -e 'tell application "Spotify" to duration of current track as string' 2>/dev/null | awk -F. '{print $1}')
      if [ -n "$DUR_MS" ] && [ "$DUR_MS" -gt 1000 ] 2>/dev/null; then DUR=$((DUR_MS / 1000)); fi
      if [ -n "$TRACK" ]; then FOUND="yes"; IMAGE=$(fetch_artwork "$TRACK" "$ARTIST"); fi
    fi
  fi

  if [ "$FOUND" = "no" ]; then
    INFO=$(osascript <<'AS' 2>/dev/null || true
tell application "Google Chrome"
  if not (it is running) then return ""
  repeat with w in windows
    repeat with t in tabs of w
      try
        if (URL of t) contains "open.spotify.com" then
          set tabTitle to title of t
          set times to ""
          try
            set times to execute t javascript "(() => { const p=document.querySelector('[data-testid=\"playback-position\"]'); const d=document.querySelector('[data-testid=\"playback-duration\"]'); if(p&&d) return p.textContent.trim()+'|'+d.textContent.trim(); return ''; })()"
          end try
          return tabTitle & "|||" & times
        end if
      end try
    end repeat
  end repeat
end tell
return ""
AS
)
    if [ -n "$INFO" ]; then
      TITLE="${INFO%%%||*}"; TIMES="${INFO##*|||}"
      [ "$TITLE" = "$INFO" ] && TITLE="$INFO" && TIMES=""
      PARSED=$(parse_title "$TITLE")
      TRACK=$(printf '%s' "$PARSED" | sed -n '1p')
      ARTIST=$(printf '%s' "$PARSED" | sed -n '2p')
      if [ -n "$TIMES" ] && printf '%s' "$TIMES" | grep -q '|'; then
        POS=$(time_to_sec "$(printf '%s' "$TIMES" | cut -d'|' -f1)")
        DUR=$(time_to_sec "$(printf '%s' "$TIMES" | cut -d'|' -f2)")
      fi
      if [ -n "$TRACK" ]; then
        STATUS="playing"; FOUND="yes"
        IMAGE=$(fetch_artwork "$TRACK" "$ARTIST")
        [ "$DUR" -le 1 ] && D2=$(fetch_dur "$TRACK" "$ARTIST") && [ "$D2" -gt 1 ] 2>/dev/null && DUR=$D2
      fi
    fi
  fi

  if [ "$FOUND" = "no" ]; then
    INFO=$(osascript <<'AS' 2>/dev/null || true
tell application "Safari"
  if not (it is running) then return ""
  repeat with w in windows
    repeat with t in tabs of w
      try
        if (URL of t) contains "open.spotify.com" then
          set tabTitle to name of t
          set times to ""
          try
            set times to do JavaScript "(() => { const p=document.querySelector('[data-testid=\"playback-position\"]'); const d=document.querySelector('[data-testid=\"playback-duration\"]'); if(p&&d) return p.textContent.trim()+'|'+d.textContent.trim(); return ''; })()" in t
          end try
          return tabTitle & "|||" & times
        end if
      end try
    end repeat
  end repeat
end tell
return ""
AS
)
    if [ -n "$INFO" ]; then
      TITLE="${INFO%%%||*}"; TIMES="${INFO##*|||}"
      [ "$TITLE" = "$INFO" ] && TITLE="$INFO" && TIMES=""
      PARSED=$(parse_title "$TITLE")
      TRACK=$(printf '%s' "$PARSED" | sed -n '1p')
      ARTIST=$(printf '%s' "$PARSED" | sed -n '2p')
      if [ -n "$TIMES" ] && printf '%s' "$TIMES" | grep -q '|'; then
        POS=$(time_to_sec "$(printf '%s' "$TIMES" | cut -d'|' -f1)")
        DUR=$(time_to_sec "$(printf '%s' "$TIMES" | cut -d'|' -f2)")
      fi
      if [ -n "$TRACK" ]; then
        STATUS="playing"; FOUND="yes"
        IMAGE=$(fetch_artwork "$TRACK" "$ARTIST")
        [ "$DUR" -le 1 ] && D2=$(fetch_dur "$TRACK" "$ARTIST") && [ "$D2" -gt 1 ] 2>/dev/null && DUR=$D2
      fi
    fi
  fi

  [ -z "$TRACK" ] && TRACK="No Track Playing"
  case "$POS" in ''|*[!0-9]*) POS=0 ;; esac
  case "$DUR" in ''|*[!0-9]*) DUR=1 ;; esac
  [ "$DUR" -lt 1 ] && DUR=1
  [ "$POS" -gt "$DUR" ] && POS=$DUR
  [ "$FOUND" = "no" ] && STATUS="paused" && IMAGE=""

  ET=$(json_escape "$TRACK"); EA=$(json_escape "$ARTIST"); EI=$(json_escape "$IMAGE")
  JSON="{\"status\":\"$STATUS\",\"track\":\"$ET\",\"artist\":\"$EA\",\"position\":$POS,\"duration\":$DUR,\"image\":\"$EI\"}"
  curl -s -X POST "$MUSIC_URL" -H "Content-Type: application/json" -d "$JSON" >/dev/null 2>&1 || true
  sleep 1
done
SCRIPT_EOF

sed -i '' "s|__MUSIC_URL__|$MUSIC_URL|g" "$INSTALL_DIR/push_music.sh"
chmod +x "$INSTALL_DIR/push_music.sh"

cat > "$OVERLAY_HTML" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<title>Spotify Overlay</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;overflow:hidden;background:transparent;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;user-select:none;-webkit-user-select:none}
body{display:flex;align-items:flex-end;justify-content:center;padding-bottom:20px}
.shell{width:450px;height:80px;border-radius:18px;background:rgba(16,16,19,.88);border:1px solid rgba(255,255,255,.22);box-shadow:0 12px 40px rgba(0,0,0,.45),inset 0 1px 0 rgba(255,255,255,.12);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);display:flex;align-items:center;padding:0 12px;gap:12px;position:relative;overflow:hidden}
.art{width:56px;height:56px;border-radius:12px;background:rgba(45,45,50,.8);object-fit:cover;flex-shrink:0}
.artph{width:56px;height:56px;border-radius:12px;background:rgba(45,45,50,.8);display:flex;align-items:center;justify-content:center;color:rgba(255,255,255,.25);font-size:20px;flex-shrink:0}
.meta{flex:1;min-width:0;display:flex;flex-direction:column;justify-content:center;height:64px}
.track{color:#fff;font-weight:700;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.artist{color:rgb(170,170,178);font-size:12px;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row{display:flex;align-items:center;gap:8px;margin-top:8px}
.btns{display:flex;gap:6px;flex-shrink:0;color:#fff;font-size:13px;font-weight:700}
.progress-wrap{flex:1;display:flex;flex-direction:column;gap:2px;min-width:0}
.bar-bg{height:4px;border-radius:2px;background:rgba(255,255,255,.25);position:relative}
.bar-fill{height:100%;width:0%;border-radius:2px;background:#fff}
.dot{position:absolute;top:50%;width:12px;height:12px;margin-top:-6px;margin-left:-6px;border-radius:50%;background:#fff;left:0%}
.times{display:flex;justify-content:space-between;color:rgb(170,170,178);font-size:10px;font-variant-numeric:tabular-nums}
</style>
</head>
<body>
<div class="shell">
  <img class="art" id="art" alt="" style="display:none"/>
  <div class="artph" id="artPh">♪</div>
  <div class="meta">
    <div class="track" id="track">Connecting...</div>
    <div class="artist" id="artist"></div>
    <div class="row">
      <div class="btns"><span>|&lt;</span>&nbsp;<span id="pp">||</span>&nbsp;<span>&gt;|</span></div>
      <div class="progress-wrap">
        <div class="bar-bg"><div class="bar-fill" id="fill"></div><div class="dot" id="dot"></div></div>
        <div class="times"><span id="tCur">0:00</span><span id="tTot">0:00</span></div>
      </div>
    </div>
  </div>
</div>
<script>
const API="https://player-production-7e33.up.railway.app/music";
let total=1,pos=0,playing=false,lastImg="";
function fmt(s){s=Math.max(0,Math.floor(s+.5));return Math.floor(s/60)+":"+String(s%60).padStart(2,"0")}
function setArt(url){const img=document.getElementById("art"),ph=document.getElementById("artPh");if(!url){img.style.display="none";ph.style.display="flex";lastImg="";return}if(url===lastImg)return;lastImg=url;img.onload=()=>{img.style.display="block";ph.style.display="none"};img.onerror=()=>{img.style.display="none";ph.style.display="flex";lastImg=""};img.src=url}
function apply(d){const track=d.track||"";if(track&&track!=="No Track Playing"){document.getElementById("track").textContent=track;document.getElementById("artist").textContent=d.artist||"Unknown Artist";total=Math.max(1,Number(d.duration)||1);pos=Math.max(0,Number(d.position)||0);if(pos>total)pos=total;playing=String(d.status||"").toLowerCase()==="playing";setArt(d.image||"")}else{document.getElementById("track").textContent="Spotify";document.getElementById("artist").textContent="No track playing";total=1;pos=0;playing=false;setArt("")}document.getElementById("pp").textContent=playing?"||":"|>";paint()}
function paint(){const r=total>0?Math.min(1,pos/total):0;document.getElementById("fill").style.width=(r*100)+"%";document.getElementById("dot").style.left=(r*100)+"%";document.getElementById("tCur").textContent=fmt(pos);document.getElementById("tTot").textContent=fmt(total)}
async function poll(){try{const res=await fetch(API+"?t="+Date.now(),{cache:"no-store"});if(res.ok)apply(await res.json())}catch(e){document.getElementById("track").textContent="Offline";document.getElementById("artist").textContent="Check connection"}}
setInterval(poll,1000);setInterval(()=>{if(playing&&total>1){pos=Math.min(total,pos+.25);paint()}},250);poll();
</script>
</body>
</html>
HTMLEOF

cat > "$INSTALL_DIR/start-overlay.sh" << 'START'
#!/bin/bash
INSTALL_DIR="$HOME/spotify-overlay"
HTML="$INSTALL_DIR/overlay.html"
open_chrome() {
  local CHROME=""
  for c in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
  do
    [ -x "$c" ] && CHROME="$c" && break
  done
  if [ -n "$CHROME" ]; then
    "$CHROME" --app="file://${HTML}" --window-size=480,140 --window-position=720,900 --disable-extensions --no-first-run >/dev/null 2>&1 &
    return 0
  fi
  return 1
}
if ! open_chrome; then open -a Safari "$HTML"; fi
sleep 1
osascript <<'AS' 2>/dev/null || true
tell application "System Events"
  set procs to {"Google Chrome", "Chromium", "Microsoft Edge", "Safari"}
  repeat with pname in procs
    if exists process pname then
      tell process pname
        set frontmost to true
        try
          set position of front window to {700, 900}
          set size of front window to {480, 140}
        end try
      end tell
      exit repeat
    end if
  end repeat
end tell
AS
echo "Overlay window opened."
START
chmod +x "$INSTALL_DIR/start-overlay.sh"

cat > "$INSTALL_DIR/stop-overlay.sh" << 'STOP'
#!/bin/bash
osascript <<'AS' 2>/dev/null || true
tell application "System Events"
  repeat with pname in {"Google Chrome", "Chromium", "Microsoft Edge"}
    if exists process pname then
      tell process pname
        repeat with w in windows
          try
            if name of w contains "Spotify Overlay" then
              click button 1 of w
            end if
          end try
        end repeat
      end tell
    end if
  end repeat
end tell
AS
pkill -f "app=file://.*spotify-overlay/overlay.html" 2>/dev/null || true
echo "Overlay window closed. Scanner still running."
STOP
chmod +x "$INSTALL_DIR/stop-overlay.sh"

cat > "$INSTALL_DIR/uninstall.sh" << 'UN'
#!/bin/bash
LABEL="com.spotify.overlay"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f push_music.sh 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.spotify.overlay.plist"
bash "$HOME/spotify-overlay/stop-overlay.sh" 2>/dev/null || true
echo "Stopped scanner + overlay."
UN
chmod +x "$INSTALL_DIR/uninstall.sh"

osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1 || {
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  echo "Enable Terminal under Accessibility if you use browser Spotify, then press Enter."
  read -r
}

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f push_music.sh 2>/dev/null || true
sleep 1

cat > "$PLIST" << PLIST_EOF
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
sleep 1
bash "$INSTALL_DIR/start-overlay.sh"

echo ""
echo "======================================================"
echo "Done. No Roblox executor required."
echo "  Stop overlay:     ~/spotify-overlay/stop-overlay.sh"
echo "  Stop everything:  ~/spotify-overlay/uninstall.sh"
echo "  Start overlay:    ~/spotify-overlay/start-overlay.sh"
echo "Use Roblox windowed/borderless so the overlay can sit on top."
echo "======================================================"
