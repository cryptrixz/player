#!/bin/bash
set -e

INSTALL_DIR="$HOME/spotify-overlay-app"

echo "Setting up Spotify overlay directory files..."

pkill -f "electron" 2>/dev/null || true
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

cat > "$INSTALL_DIR/package.json" << 'PKGEOF'
{
  "name": "spotify-overlay-desktop",
  "version": "1.0.0",
  "main": "app.js",
  "scripts": {
    "start": "electron ."
  },
  "devDependencies": {
    "electron": "^31.0.0"
  }
}
PKGEOF

cat > "$INSTALL_DIR/app.js" << 'APPEOF'
const { app, BrowserWindow, screen, ipcMain, Tray, Menu } = require('electron');
const path = require('path');
const { exec } = require('child_process');

let win;
let tray = null;

function createOverlayWindow() {
    const { width, height } = screen.getPrimaryDisplay().workAreaSize;
    win = new BrowserWindow({
        width: 480,
        height: 110,
        x: Math.floor((width - 480) / 2),
        y: height - 130,
        frame: false,
        transparent: true,
        alwaysOnTop: true,
        resizable: false,
        hasShadow: false,
        skipTaskbar: true,
        webPreferences: {
            nodeIntegration: false,
            contextIsolation: true,
            preload: path.join(__dirname, 'preload.js')
        }
    });
    
    win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
    win.setAlwaysOnTop(true, 'screen-saver', 1);
    win.setIgnoreMouseEvents(false); 
    win.loadFile(path.join(__dirname, 'overlay.html'));

    startAutomationLoops();
}

function createTrayMenu() {
    tray = new Tray(path.join(__dirname, 'icon.png')); 
    tray.setTitle("🎵"); 
    
    const contextMenu = Menu.buildFromTemplate([
        { 
            label: 'Open Overlay', 
            click: () => { if (win && !win.isDestroyed()) win.showInactive(); } 
        },
        { 
            label: 'Close Overlay', 
            click: () => { if (win && !win.isDestroyed()) win.hide(); } 
        },
        { type: 'separator' },
        { label: 'Quit', click: () => app.quit() }
    ]);
    
    tray.setContextMenu(contextMenu);
}

function startAutomationLoops() {
    setInterval(() => {
        if (!win || win.isDestroyed()) return;
        
        exec('osascript -e "get name of first application process whose frontmost is true"', (err, stdout) => {
            if (err) return;
            const activeApp = stdout.trim();
            const isRobloxActive = activeApp.includes('Roblox') || activeApp.includes('RobloxPlayer');
            
            if (isRobloxActive) {
                if (!win.isVisible()) win.showInactive();
            } else {
                if (win.isVisible()) win.hide();
            }
        });
    }, 500);

    setInterval(() => {
        if (!win || win.isDestroyed() || !win.isVisible()) return;

        const appleScript = `
            if application "Spotify" is running then
                tell application "Spotify"
                    try
                        set cTrack to current track
                        set trackName to name of cTrack
                        set artistName to artist of cTrack
                        set totalDur to duration of cTrack
                        set playerPos to player position
                        set pState to player state as string
                        return trackName & "||" & artistName & "||" & totalDur & "||" & playerPos & "||" & pState
                    on error
                        return "No Track"
                    end try
                end tell
            end if
            return "No Track"
        `;

        exec(`osascript -e '${appleScript}'`, (err, stdout) => {
            if (err || !stdout || stdout.trim() === "No Track") {
                win.webContents.send('spotify-data', { track: "Spotify", artist: "No track playing", position: 0, duration: 1, status: "paused" });
                return;
            }

            const parts = stdout.trim().split('||');
            if (parts.length >= 5) {
                win.webContents.send('spotify-data', {
                    track: parts[0],
                    artist: parts[1],
                    duration: Math.floor(Number(parts[2]) / 1000),
                    position: Math.floor(Number(parts[3])),
                    status: parts[4].toLowerCase()
                });
            }
        });
    }, 1000);
}

ipcMain.on('spotify-control', (event, action) => {
    let script = '';
    if (action === 'playpause') script = 'tell application "Spotify" to playpause';
    if (action === 'next') script = 'tell application "Spotify" to next track';
    if (action === 'prev') script = 'tell application "Spotify" to previous track';

    if (script) {
        exec(`osascript -e '${script}'`, (err) => { if (err) console.log(err); });
    }
});

app.whenReady().then(() => {
    createOverlayWindow();
    createTrayMenu();
    app.on('activate', () => {
        if (BrowserWindow.getAllWindows().length === 0) createOverlayWindow();
    });
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
});
APPEOF

cat > "$INSTALL_DIR/preload.js" << 'PREEOF'
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
    onSpotifyData: (callback) => ipcRenderer.on('spotify-data', (_event, value) => callback(value)),
    sendControl: (action) => ipcRenderer.send('spotify-control', action)
});
PREEOF

echo "iVBORw0KGgoAAAANSUhEUSuQmCC" | base64 -d > "$INSTALL_DIR/icon.png" 2>/dev/null || touch "$INSTALL_DIR/icon.png"

#!/bin/bash
set -e

INSTALL_DIR="$HOME/spotify-overlay-app"
cd "$INSTALL_DIR"

echo "Building layout interfaces and environment configurations..."

ARCH=$(uname -m)
if ! command -v node &> /dev/null; then
    if [ "$ARCH" == "arm64" ]; then
        NODE_URL="https://nodejs.org"
    else
        NODE_URL="https://nodejs.org"
    fi
    curl -fsSL "$NODE_URL" -o /tmp/node-installer.pkg
    sudo installer -pkg /tmp/node-installer.pkg -target /
    rm /tmp/node-installer.pkg
    export PATH="/usr/local/bin:$PATH"
fi

cat > "$INSTALL_DIR/overlay.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<title>Spotify Overlay</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;overflow:hidden;background:transparent !important;background-color:rgba(0,0,0,0) !important;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;user-select:none;-webkit-user-select:none}
body{display:flex;align-items:center;justify-content:center}
.shell{
    -webkit-app-region: drag;
    width:450px;height:80px;border-radius:18px;background:rgba(16,16,19,.88);border:1px solid rgba(255,255,255,.22);box-shadow:0 12px 40px rgba(0,0,0,.45),inset 0 1px 0 rgba(255,255,255,.12);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);display:flex;align-items:center;padding:0 12px;gap:12px;position:relative;overflow:hidden
}
.artph{width:56px;height:56px;border-radius:12px;background:rgba(45,45,50,.8);display:flex;align-items:center;justify-content:center;color:rgba(255,255,255,.25);font-size:20px;flex-shrink:0}
.meta{flex:1;min-width:0;display:flex;flex-direction:column;justify-content:center;height:64px}
.track{color:#fff;font-weight:700;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.artist{color:rgb(170,170,178);font-size:12px;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row{display:flex;align-items:center;gap:8px;margin-top:8px}
.btns{
    -webkit-app-region: no-drag;
    display:flex;gap:12px;flex-shrink:0;color:#fff;font-size:14px;font-weight:700;cursor:pointer
}
.btns span:hover { color: rgb(30, 215, 96); }
.progress-wrap{flex:1;display:flex;flex-direction:column;gap:2px;min-width:0}
.bar-bg{height:4px;border-radius:2px;background:rgba(255,255,255,.25);position:relative}
.bar-fill{height:100%;width:0%;border-radius:2px;background:#fff}
.dot{position:absolute;top:50%;width:12px;height:12px;margin-top:-6px;margin-left:-6px;border-radius:50%;background:#fff;left:0%}
.times{display:flex;justify-content:space-between;color:rgb(170,170,178);font-size:10px;font-variant-numeric:tabular-nums}
</style>
</head>
<body>
<div class="shell">
  <div class="artph" id="artPh">♪</div>
  <div class="meta">
    <div class="track" id="track">Connecting...</div>
    <div class="artist" id="artist"></div>
    <div class="row">
      <div class="btns">
        <span id="btnPrev">|&lt;</span>
        <span id="btnPP">||</span>
        <span id="btnNext">&gt;|</span>
      </div>
      <div class="progress-wrap">
        <div class="bar-bg"><div class="bar-fill" id="fill"></div><div class="dot" id="dot"></div></div>
        <div class="times"><span id="tCur">0:00</span><span id="tTot">0:00</span></div>
      </div>
    </div>
  </div>
</div>
<script>
let total=1,pos=0,playing=false;
function fmt(s){s=Math.max(0,Math.floor(s+.5));return Math.floor(s/60)+":"+String(s%60).padStart(2,"0")}
function paint(){const r=total>0?Math.min(1,pos/total):0;document.getElementById("fill").style.width=(r*100)+"%";document.getElementById("dot").style.left=(r*100)+"%";document.getElementById("tCur").textContent=fmt(pos);document.getElementById("tTot").textContent=fmt(total)}

document.getElementById('btnPrev').addEventListener('click', () => window.electronAPI.sendControl('prev'));
document.getElementById('btnPP').addEventListener('click', () => window.electronAPI.sendControl('playpause'));
document.getElementById('btnNext').addEventListener('click', () => window.electronAPI.sendControl('next'));

window.electronAPI.onSpotifyData((d) => {
    document.getElementById("track").textContent = d.track || "Spotify";
    document.getElementById("artist").textContent = d.artist || "No track playing";
    total = Math.max(1, Number(d.duration) || 1);
    pos = Math.max(0, Number(d.position) || 0);
    playing = d.status === "playing" || d.status === "kpsp";
    document.getElementById("btnPP").textContent = playing ? "||" : "|>";
    paint();
});

setInterval(() => {
    if (playing && pos < total) {
        pos = Math.min(total, pos + 0.25);
        paint();
    }
}, 250);
</script>
</body>
</html>
HTMLEOF

npm install --silent

xattr -cr "$INSTALL_DIR/node_modules/electron" 2>/dev/null || true
codesign --force --deep --sign - "$INSTALL_DIR/node_modules/electron/dist/Electron.app" 2>/dev/null || true

sleep 1
nohup npm start > "$INSTALL_DIR/overlay.log" 2>&1 &
disown

sleep 2
echo "Done. Application logic execution complete."
