#!/bin/bash
set -e
INSTALL_DIR="$HOME/spotify-overlay-app"
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
        resizable: true,
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
    const contextMenu = Menu.buildFromTemplate([
        { label: 'Open Overlay', click: () => { if (win && !win.isDestroyed()) win.showInactive(); } },
        { label: 'Close Overlay', click: () => { if (win && !win.isDestroyed()) win.hide(); } },
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
    }, 250);

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
                        set artworkUrl to artwork url of cTrack
                        return trackName & "||" & artistName & "||" & totalDur & "||" & playerPos & "||" & pState & "||" & artworkUrl
                    on error
                        return "No Track"
                    end try
                end tell
            end if
            return "No Track"
        `;
        exec(`osascript -e '${appleScript}'`, (err, stdout) => {
            if (err || !stdout || stdout.trim() === "No Track") {
                win.webContents.send('spotify-data', { track: "Spotify", artist: "No track playing", position: 0, duration: 1, status: "paused", image: "" });
                return;
            }
            const parts = stdout.trim().split('||');
            if (parts.length >= 6) {
                const trackTitle = parts[0];
                const artistName = parts[1];
                const rawDur = Number(parts[2]);
                const rawPos = Number(parts[3]);
                const isAd = trackTitle.toLowerCase().includes("advertisement") || artistName.toLowerCase().includes("spotify") || rawDur === 0;
                const calculatedDur = isAd ? 30 : Math.floor(rawDur / 1000);
                const calculatedPos = isAd ? Math.floor(rawPos) : rawPos;
                win.webContents.send('spotify-data', {
                    track: trackTitle,
                    artist: artistName,
                    duration: calculatedDur,
                    position: calculatedPos,
                    status: parts[4].toLowerCase(),
                    image: parts[5],
                    isAd: isAd
                });
            }
        });
    }, 250);
}

ipcMain.on('spotify-control', (event, data) => {
    let script = '';
    if (data.action === 'playpause') script = 'tell application "Spotify" to playpause';
    if (data.action === 'next') script = 'tell application "Spotify" to next track';
    if (data.action === 'prev') script = 'tell application "Spotify" to previous track';
    if (data.action === 'scrub') script = `tell application "Spotify" to set player position to ${data.value}`;
    if (data.action === 'searchPlay') {
        script = `tell application "Spotify" to play track "spotify:search:${encodeURIComponent(data.value)}"`;
    }
    if (data.action === 'playUri') {
        script = `tell application "Spotify" to play track "${data.value}"`;
    }
    if (data.action === 'playPlaylist') {
        script = `tell application "Spotify" to play track "${data.value}"`;
    }
    if (data.action === 'getRealPlaylists') {
        const fetchScript = `
            if application "Spotify" is running then
                tell application "Spotify"
                    set out to ""
                    try
                        set allPlaylists to playlists
                        repeat with pl in allPlaylists
                            try
                                set plName to name of pl
                                set plId to id of pl
                                set out to out & plName & "::" & plId & "||"
                            end try
                        end repeat
                    on error
                        try
                            set allPlaylists to bookmarks of folder "Playlists" of library
                            repeat with pl in allPlaylists
                                try
                                    set plName to name of pl
                                    set plId to id of pl
                                    set out to out & plName & "::" & plId & "||"
                                end try
                            end repeat
                        end try
                    end try
                    return out
                end tell
            end if
            return ""
        `;
        exec(`osascript -e '${fetchScript}'`, (err, stdout) => {
            if (err || !stdout) {
                win.webContents.send('playlists-reply', []);
                return;
            }
            const list = stdout.trim().split('||').filter(Boolean).map(p => {
                const parts = p.split('::');
                return { title: parts[0], id: parts[1], isPlaylist: true };
            });
            win.webContents.send('playlists-reply', list);
        });
        return;
    }
    if (data.action === 'getPlaylistTracks') {
        const fetchTracks = `
            tell application "Spotify"
                set out to ""
                try
                    set trackList to tracks of playlist id "${data.value}"
                    repeat with t in trackList
                        try
                            set out to out & name of t & "::" & artist of t & "::" & id of t & "||"
                        end try
                    end repeat
                end try
                return out
            end tell
        `;
        exec(`osascript -e '${fetchTracks}'`, (err, stdout) => {
            if (err || !stdout) {
                win.webContents.send('tracks-reply', []);
                return;
            }
            const tracks = stdout.trim().split('||').filter(Boolean).map(t => {
                const parts = t.split('::');
                return { title: parts[0], artist: parts[1], id: parts[2] };
            });
            win.webContents.send('tracks-reply', tracks);
        });
        return;
    }
    if (script) {
        exec(`osascript -e '${script}'`, (err) => { if (err) console.log(err); });
    }
});

ipcMain.on('resize-window', (event, bounds) => {
    if (!win || win.isDestroyed()) return;
    const { width: scrW, height: scrH } = screen.getPrimaryDisplay().workAreaSize;
    win.setBounds({
        width: Math.floor(bounds.width),
        height: Math.floor(bounds.height),
        x: Math.floor((scrW - bounds.width) / 2),
        y: scrH - Math.floor(bounds.height) - 20
    }, true);
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
    onPlaylistsReply: (callback) => ipcRenderer.on('playlists-reply', (_event, value) => callback(value)),
    onTracksReply: (callback) => ipcRenderer.on('tracks-reply', (_event, value) => callback(value)),
    sendControl: (action, value = null) => ipcRenderer.send('spotify-control', { action, value }),
    resizeWindow: (bounds) => ipcRenderer.send('resize-window', bounds)
});
PREEOF

echo "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAWklEQVQ4y2P4//8/AyUYGegETGg0gGgD0M0gWh9WDRDVAHQzSDYAXQ0w1gB0M8g2AN0MMNYAdDPINgDdDLL1YdUAUQ0g2gB0M4jWh1UDRDWAaAPQzSBaH8wAALw9GBl7N9GNAAAAAElFTkSuQmCC" | base64 -d > "$INSTALL_DIR/icon.png" 2>/dev/null || touch "$INSTALL_DIR/icon.png"

cat > "$INSTALL_DIR/overlay.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<title>Spotify Overlay</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;overflow:hidden;background:transparent !important;background-color:rgba(0,0,0,0) !important;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;user-select:none;-webkit-user-select:none}
body{display:flex;align-items:center;justify-content:center;flex-direction:column;gap:10px}
.shell{
    -webkit-app-region: drag;
    width:450px;height:80px;border-radius:18px;background:rgba(16,16,19,.88);border:1px solid rgba(255,255,255,.22);box-shadow:0 12px 40px rgba(0,0,0,.45),inset 0 1px 0 rgba(255,255,255,.12);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);display:flex;align-items:center;padding:0 12px;gap:12px;position:relative;overflow:hidden;transition:all 0.25s ease-in-out
}
.art{-webkit-app-region:no-drag;width:56px;height:56px;border-radius:12px;background:rgba(45,45,50,.8);object-fit:cover;flex-shrink:0;cursor:pointer}
.artph{width:56px;height:56px;border-radius:12px;background:rgba(45,45,50,.8);display:flex;align-items:center;justify-content:center;color:rgba(255,255,255,.25);font-size:20px;flex-shrink:0;cursor:pointer;-webkit-app-region:no-drag}
.meta{flex:1;min-width:0;display:flex;flex-direction:column;justify-content:center;height:64px;position:relative}
.track{color:#fff;font-weight:700;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding-right:50px}
.artist{color:rgb(170,170,178);font-size:12px;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding-right:50px}
.row{display:flex;align-items:center;gap:8px;margin-top:8px}
.btns{
    -webkit-app-region: no-drag;
    display:flex;gap:12px;flex-shrink:0;color:#fff;font-size:14px;font-weight:700;cursor:pointer
}
.btns span:hover { color: rgb(30, 215, 96); }
.progress-wrap{
    -webkit-app-region: no-drag;
    flex:1;display:flex;flex-direction:column;gap:2px;min-width:0
}
.bar-bg{height:4px;border-radius:2px;background:rgba(255,255,255,.25);position:relative;cursor:pointer}
.bar-fill{height:100%;width:0%;border-radius:2px;background:#fff;transition:width 0.1s linear}
.times{display:flex;justify-content:space-between;color:rgb(170,170,178);font-size:10px;font-variant-numeric:tabular-nums}
.island-waves {
    -webkit-app-region: no-drag;
    position: absolute;
    right: 0;
    top: 4px;
    display: flex;
    align-items: center;
    gap: 2px;
    height: 20px;
    width: 45px;
    justify-content: flex-end;
    cursor: pointer;
    background: linear-gradient(90deg, #ff007f, #7f00ff, #00f0ff);
}
.wave-bar {
    width: 3px;
    height: 16px;
    background-color: rgba(16,16,19,.88);
    border-radius: 1px;
    transition: height 0.1s ease-in-out;
}
.drawer{
    -webkit-app-region: no-drag;
    width:450px;height:0px;border-radius:18px;background:rgba(16,16,19,.92);border:0px solid rgba(255,255,255,.22);box-shadow:0 12px 40px rgba(0,0,0,.45);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);display:flex;flex-direction:column;overflow:hidden;transition:all 0.25s ease-in-out;opacity:0
}
.drawer.open{
    height:220px;border:1px solid rgba(255,255,255,.22);opacity:1;padding:12px
}
.search-box{
    width:100%;padding:8px 12px;background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.1);border-radius:8px;color:#fff;outline:none;font-size:12px;margin-bottom:12px
}
.search-box::placeholder{color:rgba(255,255,255,.4)}
.nav-tabs{display:flex;gap:12px;border-bottom:1px solid rgba(255,255,255,.1);padding-bottom:6px;margin-bottom:10px}
.tab{color:rgba(255,255,255,.5);font-size:12px;font-weight:600;cursor:pointer}
.tab.active{color:#fff;border-bottom:2px solid #fff;padding-bottom:4px}
.back-btn{color:rgb(30, 215, 96);font-size:11px;cursor:pointer;margin-bottom:6px;display:none;font-weight:bold}
.list-container{flex:1;overflow-y:auto;display:flex;flex-direction:column;gap:6px}
.list-item{display:flex;align-items:center;gap:8px;padding:6px;border-radius:6px;cursor:pointer}
.list-item:hover{background:rgba(255,255,255,.05)}
.list-thumb{width:32px;height:32px;border-radius:4px;background:rgba(255,255,255,.1);object-fit:cover;flex-shrink:0}
.list-thumb-ph{width:32px;height:32px;border-radius:4px;background:rgba(255,255,255,.1);display:flex;align-items:center;justify-content:center;color:#fff;font-size:12px;flex-shrink:0}
.list-info{display:flex;flex-direction:column;min-width:0;flex:1}
.list-title{color:#fff;font-size:12px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.list-sub{color:rgba(255,255,255,.5);font-size:10px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.play-btn{
    -webkit-app-region: no-drag;
    color:rgb(30,215,96);font-size:14px;font-weight:bold;padding:4px 8px;cursor:pointer;border-radius:4px;flex-shrink:0
}
.play-btn:hover{background:rgba(30,215,96,.15)}
</style>
</head>
<body>
<div class="shell" id="playerShell">
  <img class="art" id="art" alt="" style="display:none"/>
  <div class="artph" id="artPh">♪</div>
  <div class="meta">
    <div class="track" id="track">Connecting...</div>
    <div class="artist" id="artist"></div>
    <div class="island-waves" id="islandWaves" title="Click to expand browser">
      <div class="wave-bar"></div>
      <div class="wave-bar"></div>
      <div class="wave-bar"></div>
      <div class="wave-bar"></div>
      <div class="wave-bar"></div>
    </div>
    <div class="row">
      <div class="btns">
        <span id="btnPrev">|&lt;</span>
        <span id="btnPP">||</span>
        <span id="btnNext">&gt;|</span>
      </div>
      <div class="progress-wrap">
        <div class="bar-bg" id="progressBg"><div class="bar-fill" id="fill"></div></div>
        <div class="times"><span id="tCur">0:00</span><span id="tTot">0:00</span></div>
      </div>
    </div>
  </div>
</div>
<div class="drawer" id="extendedDrawer">
  <input type="text" class="search-box" id="searchBox" placeholder="Search songs or artists..." />
  <div class="nav-tabs" id="drawerTabs">
    <div class="tab active" id="tabPlaylists">Playlists</div>
    <div class="tab" id="tabRecents">Recents</div>
  </div>
  <div class="back-btn" id="backBtn">&lt; Back to Playlists</div>
  <div class="list-container" id="listContainer"></div>
</div>
<canvas id="colorCanvas" style="display:none;" width="10" height="10"></canvas>
<script>
let total=1,pos=0,playing=false,lastImg="",baseScale=1.0,drawerOpen=false,viewingPlaylist=false;
let recentTracksMemory = [];
let loadedPlaylistsMemory = [];
const canvas=document.getElementById("colorCanvas"),ctx=canvas.getContext("2d");
function fmt(s){s=Math.max(0,Math.floor(s+.5));return Math.floor(s/60)+":"+String(s%60).padStart(2,"0")}
function updateGradientBars(r, g, b) {
    const container = document.getElementById('islandWaves');
    container.style.background = `linear-gradient(90deg, rgb(${r},${g},${b}), rgb(${g},${b},${r}), #00f0ff)`;
    container.style.webkitBackgroundClip = 'text';
    container.style.backgroundClip = 'text';
}
function extractColorAndTint(imgEl) {
    try {
        ctx.drawImage(imgEl, 0, 0, 10, 10);
        const data = ctx.getImageData(0, 0, 10, 10).data;
        let r=0, g=0, b=0, count=0;
        for (let i=0; i<data.length; i+=4) {
            if (data[i]+data[i+1]+data[i+2] > 60 && data[i]+data[i+1]+data[i+2] < 680) {
                r += data[i]; g += data[i+1]; b += data[i+2]; count++;
            }
        }
        if (count > 0) {
            r = Math.floor(r/count); g = Math.floor(g/count); b = Math.floor(b/count);
            updateGradientBars(r, g, b);
        }
    } catch(e){}
}
function setArt(url){
    const img=document.getElementById("art"),ph=document.getElementById("artPh");
    if(!url){
        img.style.display="none";ph.style.display="flex";lastImg="";
        return;
    }
    if(url===lastImg)return;
    lastImg=url;
    img.crossOrigin = "Anonymous";
    img.onload=()=>{
        img.style.display="block";ph.style.display="none";
        extractColorAndTint(img);
    };
    img.onerror=()=>{
        img.style.display="none";ph.style.display="flex";lastImg="";
    };
    img.src=url;
}
function paint(){
    const r=total>0?Math.min(1,pos/total):0;
    document.getElementById("fill").style.width=(r*100)+"%";
    document.getElementById("tCur").textContent=fmt(pos);
    document.getElementById("tTot").textContent=fmt(total);
}
function updateWindowBounds() {
    let targetW = Math.floor(480 * baseScale);
    let targetH = Math.floor((drawerOpen ? 340 : 110) * baseScale);
    document.getElementById("playerShell").style.width = `${Math.floor(450 * baseScale)}px`;
    document.getElementById("playerShell").style.height = `${Math.floor(80 * baseScale)}px`;
    document.getElementById("extendedDrawer").style.width = `${Math.floor(450 * baseScale)}px`;
    window.electronAPI.resizeWindow({ width: targetW, height: targetH });
}
function populateList(items) {
    const container = document.getElementById("listContainer");
    container.innerHTML = "";
    items.forEach(item => {
        const row = document.createElement("div");
        row.className = "list-item";
        let visualMarkup = `<div class="list-thumb-ph">${item.isPlaylist ? "📁" : "🎵"}</div>`;
        if (item.image) {
            visualMarkup = `<img class="list-thumb" src="${item.image}" onerror="this.style.display='none'" />`;
        }
        let playMarkup = "";
        if (item.isPlaylist) {
            playMarkup = `<div class="play-btn" title="Play playlist">▶</div>`;
        }
        row.innerHTML = `
            ${visualMarkup}
            <div class="list-info">
                <div class="list-title">${item.title}</div>
                <div class="list-sub">${item.artist || item.id || ""}</div>
            </div>
            ${playMarkup}
        `;
        const playBtn = row.querySelector('.play-btn');
        if (playBtn) {
            playBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                window.electronAPI.sendControl('playPlaylist', item.id);
            });
        }
        row.addEventListener('click', () => {
            if (item.isPlaylist) {
                viewingPlaylist = true;
                document.getElementById('drawerTabs').style.display = 'none';
                document.getElementById('backBtn').style.display = 'block';
                window.electronAPI.sendControl('getPlaylistTracks', item.id);
            } else {
                window.electronAPI.sendControl('playUri', item.id);
            }
        });
        container.appendChild(row);
    });
}
document.getElementById('backBtn').addEventListener('click', () => {
    viewingPlaylist = false;
    document.getElementById('backBtn').style.display = 'none';
    document.getElementById('drawerTabs').style.display = 'flex';
    populateList(loadedPlaylistsMemory);
});
document.getElementById('islandWaves').addEventListener('click', () => {
    drawerOpen = !drawerOpen;
    const dr = document.getElementById("extendedDrawer");
    if (drawerOpen) {
        dr.classList.add("open");
        if (!viewingPlaylist) {
            window.electronAPI.sendControl('getRealPlaylists');
        }
    } else {
        dr.classList.remove("open");
    }
    updateWindowBounds();
});
document.getElementById('art').addEventListener('click', () => {
    baseScale = baseScale === 1.0 ? 1.25 : (baseScale === 1.25 ? 0.85 : 1.0);
    updateWindowBounds();
});
document.getElementById('artPh').addEventListener('click', () => {
    baseScale = baseScale === 1.0 ? 1.25 : (baseScale === 1.25 ? 0.85 : 1.0);
    updateWindowBounds();
});
document.getElementById('tabPlaylists').addEventListener('click', (e) => {
    document.getElementById('tabRecents').classList.remove('active');
    e.target.classList.add('active');
    window.electronAPI.sendControl('getRealPlaylists');
});
document.getElementById('tabRecents').addEventListener('click', (e) => {
    document.getElementById('tabPlaylists').classList.remove('active');
    e.target.classList.add('active');
    populateList(recentTracksMemory);
});
window.electronAPI.onPlaylistsReply((playlists) => {
    loadedPlaylistsMemory = playlists;
    if (document.getElementById('tabPlaylists').classList.contains('active') && !viewingPlaylist) {
        populateList(playlists);
    }
});
window.electronAPI.onTracksReply((tracks) => {
    if (viewingPlaylist) {
        populateList(tracks);
    }
});
document.getElementById('searchBox').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && e.target.value.trim()) {
        window.electronAPI.sendControl('searchPlay', e.target.value);
    }
});
document.getElementById('btnPrev').addEventListener('click', () => window.electronAPI.sendControl('prev'));
document.getElementById('btnPP').addEventListener('click', () => window.electronAPI.sendControl('playpause'));
document.getElementById('btnNext').addEventListener('click', () => window.electronAPI.sendControl('next'));
document.getElementById('progressBg').addEventListener('click', (e) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const percentage = Math.max(0, Math.min(1, clickX / rect.width));
    const targetSeconds = Math.floor(percentage * total);
    pos = targetSeconds;
    paint();
    window.electronAPI.sendControl('scrub', targetSeconds);
});
window.electronAPI.onSpotifyData((d) => {
    document.getElementById("track").textContent = d.track || "Spotify";
    document.getElementById("artist").textContent = d.artist || "No track playing";
    total = Math.max(1, Number(d.duration) || 1);
    const incomingPos = Math.max(0, Number(d.position) || 0);
    if (!playing || Math.abs(incomingPos - pos) > 2) {
        pos = incomingPos;
    }
    playing = d.status === "playing" || d.status === "kpsp";
    document.getElementById("btnPP").textContent = playing ? "||" : "|>";
    setArt(d.image || "");
    paint();
    if (d.track && d.track !== "Spotify" && !recentTracksMemory.some(t => t.title === d.track)) {
        recentTracksMemory.unshift({ title: d.track, artist: d.artist, id: d.track, image: d.image });
        if (recentTracksMemory.length > 20) recentTracksMemory.pop();
    }
});
setInterval(() => {
    if (playing && pos < total) {
        pos = Math.min(total, pos + 0.1);
        paint();
    }
}, 100);
const bars = document.querySelectorAll('.wave-bar');
setInterval(() => {
    bars.forEach((bar) => {
        if (playing) {
            const randomHeight = Math.floor(Math.random() * 16) + 4;
            bar.style.height = randomHeight + 'px';
            bar.style.marginTop = (20 - randomHeight) + 'px';
        } else {
            bar.style.height = '4px';
            bar.style.marginTop = '16px';
        }
    });
}, 150);
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
echo "Done. Overlay started."
