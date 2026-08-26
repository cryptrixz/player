#!/bin/bash
set -e

INSTALL_DIR="$HOME/spotify-overlay-app"

pkill -f "kitty123-app" 2>/dev/null || true
pkill -f "Electron" 2>/dev/null || true
pkill -f "player.html" 2>/dev/null || true
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

rm -rf kitty123.app
mkdir -p kitty123.app/Contents/MacOS
mkdir -p kitty123.app/Contents/Resources
mkdir -p kitty123.app/Contents/images

cat > kitty123.app/Contents/MacOS/applet << 'APPLETEOF'
#!/bin/bash
INSTALL_DIR="$HOME/spotify-overlay-app"

while true; do
    IS_ROBLOX=$(osascript -e '
        tell application "System Events"
            try
                set frontApp to name of first application process whose frontmost is true
                if frontApp contains "Roblox" or frontApp contains "RobloxPlayer" then
                    return "true"
                else
                    return "false"
                end if
            on error
                return "false"
            end try
        end tell
    ')

    if [ "$IS_ROBLOX" = "true" ]; then
        SPOTIFY_DATA=$(osascript -e '
            if application "Spotify" is running then
                tell application "Spotify"
                    try
                        set cTrack to current track
                        set trackName to name of cTrack
                        set artistName to artist of cTrack
                        set totalDur to (duration of cTrack) div 1000
                        set playerPos to player position as integer
                        set pState to player state as string
                        return trackName & "||" & artistName & "||" & totalDur & "||" & playerPos & "||" & pState
                    on error
                        return "No Track"
                    end try
                end tell
            else
                return "No Track"
            end if
        ')
        
        SPOTIFY_CACHE="$HOME/Library/Caches/com.spotify.client/Data"
        if [ -d "$SPOTIFY_CACHE" ]; then
            LATEST_ARTWORK=$(find "$SPOTIFY_CACHE" -type f \( -name "*.file" -o -name "*.png" -o -name "*.jpg" \) 2>/dev/null | xargs stat -f "%m %N" 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-)
            if [ -n "$LATEST_ARTWORK" ]; then
                cp "$LATEST_ARTWORK" "$INSTALL_DIR/current_art.png" 2>/dev/null || true
            fi
        fi

        echo "$SPOTIFY_DATA" > "$INSTALL_DIR/state.txt"
    else
        echo "Offline" > "$INSTALL_DIR/state.txt"
    fi
    sleep 0.4
done &

/System/Library/Frameworks/WebKit.framework/Versions/Current/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent --url "file://$INSTALL_DIR/player.html" >/dev/null 2>&1 &
APPLETEOF
chmod +x kitty123.app/Contents/MacOS/applet

set -e

INSTALL_DIR="$HOME/spotify-overlay-app"
cd "$INSTALL_DIR"

cat > "$INSTALL_DIR/player.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;overflow:hidden;background:transparent !important;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;user-select:none;-webkit-user-select:none}
body{display:flex;align-items:center;justify-content:center}
.shell{
    width:450px;height:80px;border-radius:18px;background:rgba(16,16,19,.92);border:1px solid rgba(255,255,255,.22);box-shadow:0 12px 40px rgba(0,0,0,.5);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);display:flex;align-items:center;padding:0 12px;gap:12px;position:relative;margin-top:1300px
}
.artbox{width:56px;height:56px;border-radius:12px;background:rgba(45,45,50,.8);display:flex;align-items:center;justify-content:center;color:rgba(255,255,255,.25);font-size:20px;flex-shrink:0;overflow:hidden}
.artbox img{width:100%;height:100%;object-fit:cover}
.meta{flex:1;min-width:0;display:flex;flex-direction:column;justify-content:center;height:64px;position:relative}
.track{color:#fff;font-weight:700;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding-right:50px}
.artist{color:rgb(170,170,178);font-size:12px;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding-right:50px}
.row{display:flex;align-items:center;gap:8px;margin-top:8px}
.btns{display:flex;gap:12px;flex-shrink:0;color:#fff;font-size:14px;font-weight:700;cursor:pointer}
.btns span:hover { color: rgb(30, 215, 96); }
.progress-wrap{flex:1;display:flex;flex-direction:column;gap:2px;min-width:0}
.bar-bg{height:4px;border-radius:2px;background:rgba(255,255,255,.25);position:relative;cursor:pointer}
.bar-fill{height:100%;width:0%;border-radius:2px;background:#fff;transition:width 0.2s linear}
.times{display:flex;justify-content:space-between;color:rgb(170,170,178);font-size:10px;font-variant-numeric:tabular-nums}
.island-waves {position:absolute;right:0;top:4px;display:flex;align-items:center;gap:2px;height:20px;width:40px;justify-content:flex-end}
.wave-bar {width:3px;height:4px;background-color:#fff;border-radius:1px}
</style>
</head>
<body>
<div class="shell">
  <div class="artbox" id="albumArtBox">🎵</div>
  <div class="meta">
    <div class="track" id="track">Open Roblox...</div>
    <div class="artist" id="artist"></div>
    <div class="island-waves">
      <div class="wave-bar"></div><div class="wave-bar"></div><div class="wave-bar"></div><div class="wave-bar"></div><div class="wave-bar"></div>
    </div>
    <div class="row">
      <div class="btns">
        <span onclick="runCmd('previous track')">|<</span>
        <span onclick="runCmd('playpause')" id="btnPP">||</span>
        <span onclick="runCmd('next track')">>|</span>
      </div>
      <div class="progress-wrap">
        <div class="bar-bg" id="progressBg" onclick="scrubSong(event)"><div class="bar-fill" id="fill"></div></div>
        <div class="times"><span id="tCur">0:00</span><span id="tTot">0:00</span></div>
      </div>
    </div>
  </div>
</div>
<script>
let total=1,pos=0,playing=false,lastTrack="";
function fmt(s){s=Math.max(0,Math.floor(s+.5));return Math.floor(s/60)+":"+String(s%60).padStart(2,"0")}

function updateUI(track, artist, duration, position, status) {
    document.getElementById("track").textContent = track;
    document.getElementById("artist").textContent = artist;
    total = Math.max(1, Number(duration));
    pos = Math.max(0, Number(position));
    playing = status.toLowerCase() === "playing";
    document.getElementById("btnPP").textContent = playing ? "||" : "|>";
    
    if(track !== lastTrack) {
        lastTrack = track;
        document.getElementById("albumArtBox").innerHTML = `<img src="current_art.png?t=${Date.now()}" onerror="this.parentElement.innerHTML='🎵'" />`;
    }
    
    const r = total > 0 ? Math.min(1, pos / total) : 0;
    document.getElementById("fill").style.width = (r * 100) + "%";
    document.getElementById("tCur").textContent = fmt(pos);
    document.getElementById("tTot").textContent = fmt(total);
    
    const isGabriela = track.toLowerCase().includes("gabriela") || artist.toLowerCase().includes("katseye");
    const activeColor = isGabriela ? "rgb(230, 40, 40)" : "#fff";
    
    document.querySelectorAll('.wave-bar').forEach(bar => {
        bar.style.backgroundColor = activeColor;
        if (playing) {
            bar.style.height = (Math.floor(Math.random() * 16) + 4) + 'px';
        } else {
            bar.style.height = '4px';
        }
    });
}

function runCmd(action) {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", "applescript://run?code=" + encodeURIComponent('tell application "Spotify" to ' + action), true);
    xhr.send();
}

function scrubSong(e) {
    const rect = document.getElementById('progressBg').getBoundingClientRect();
    const pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    const targetSeconds = Math.floor(pct * total);
    const xhr = new XMLHttpRequest();
    xhr.open("GET", "applescript://run?code=" + encodeURIComponent('tell application "Spotify" to set player position to ' + targetSeconds), true);
    xhr.send();
}

setInterval(async () => {
    try {
        const res = await fetch('state.txt?t=' + Date.now());
        const txt = await res.text();
        if (txt.trim() === "Offline" || txt.trim() === "No Track") {
            updateUI("Spotify", "No track playing", 1, 0, "paused");
            return;
        }
        const parts = txt.trim().split("||");
        if (parts.length >= 5) updateUI(parts, parts, parts, parts, parts);
    } catch(e) {}
}, 400);
</script>
</body>
</html>
HTMLEOF

cat > kitty123.app/Contents/Info.plist << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://apple.com">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>applet</string>
    <key>CFBundleIdentifier</key>
    <string>com.kitty123.overlay</string>
    <key>CFBundleName</key>
    <string>Kitty123</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLISTEOF

curl -fsSL "https://githubusercontent.com" -o kitty123.app/Contents/images/source.png
cp kitty123.app/Contents/images/source.png kitty123.app/Contents/Resources/AppIcon.icns

open kitty123.app
