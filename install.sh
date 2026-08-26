#!/bin/bash
set -u
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_YELLOW="\033[33m"
C_CYAN="\033[36m"
C_GRAY="\033[90m"

get_time() {
    local s=""
    local mot="kitty123"
    local couleurs=("180;220;255" "150;200;255" "120;180;255" "90;160;255" "70;140;245" "50;120;230" "40;110;220" "30;100;210" "25;90;200" "20;80;190")
    for ((i=0; i<${#mot}; i++)); do
        s+="\033[38;2;${couleurs[$((i % ${#couleurs[@]}))]}m${mot:$i:1}"
    done
    s+="${C_RESET}"
    printf "%b" "${s}${C_GRAY}::${C_RESET}${C_GREEN}[$(date +%H:%M:%S)]${C_RESET}"
}

log() { printf "%b %b\n" "$(get_time)" "$1"; }

die() {
    spinner_stop "fail" "$1"
    exit 1
}

banner() {
    local line="────────────────────────────────────────────"
    echo ""
    printf "${C_GRAY}%s${C_RESET}\n" "$line"
    printf "  %b  ${C_BOLD}Installer${C_RESET}\n" "$(printf "\033[38;2;120;180;255m%s\033[0m" "kitty123")"
    printf "${C_GRAY}%s${C_RESET}\n" "$line"
    echo ""
}

SPIN_FRAMES=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")
SPINNER_PID=""
SPINNER_MSG=""

spinner_start() {
    SPINNER_MSG="$1"
    printf "\033[?25l\033[?7l"
    (
        local i=0
        while true; do
            local frame="${SPIN_FRAMES[$((i % ${#SPIN_FRAMES[@]}))]}"
            printf "\r\033[2K%b ${C_CYAN}%s${C_RESET}  %s" "$(get_time)" "$frame" "$SPINNER_MSG"
            i=$((i+1))
            sleep 0.08
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null || true
}

spinner_stop() {
    local status="${1:-ok}"
    local msg="${2:-$SPINNER_MSG}"
    if [[ -n "$SPINNER_PID" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    SPINNER_PID=""
    printf "\r\033[2K"
    case "$status" in
        ok)   printf "%b ${C_GREEN}✔${C_RESET}  %b\n" "$(get_time)" "$msg" ;;
        fail) printf "%b ${C_RED}✖${C_RESET}  %b\n"   "$(get_time)" "$msg" ;;
        warn) printf "%b ${C_YELLOW}!${C_RESET}  %b\n" "$(get_time)" "$msg" ;;
        *)    printf "%b    %b\n" "$(get_time)" "$msg" ;;
    esac
    printf "\033[?7h\033[?25h"
}

cleanup() {
    [[ -n "$SPINNER_PID" ]] && kill "$SPINNER_PID" 2>/dev/null
    printf "\033[?7h\033[?25h"
}
trap cleanup EXIT INT TERM

banner

echo ""
log "${C_CYAN}You need a free Spotify Developer app${C_RESET}"
echo ""
printf "  1. Go to ${C_BOLD}https://developer.spotify.com/dashboard${C_RESET}\n"
printf "  2. Create an app (any name)\n"
printf "  3. Add Redirect URI: ${C_BOLD}http://127.0.0.1:8888/callback${C_RESET}\n"
printf "  4. Copy Client ID + Client Secret\n"
echo ""

read -r -p "Paste Client ID: " CLIENT_ID
read -r -p "Paste Client Secret: " CLIENT_SECRET

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
    die "Client ID and Secret are required"
fi

spinner_start "preparing install..."
sleep 0.5
spinner_stop ok "ready"

INSTALL_DIR="$HOME/spotify-overlay-app"
spinner_start "cleaning previous install..."
pkill -f "electron" 2>/dev/null || true
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
spinner_stop ok "cleaned"

# Save credentials
cat > "$INSTALL_DIR/config.json" << EOF
{
  "clientId": "$CLIENT_ID",
  "clientSecret": "$CLIENT_SECRET",
  "redirectUri": "http://127.0.0.1:8888/callback"
}
EOF

spinner_start "writing package.json..."
cat > "$INSTALL_DIR/package.json" << 'PKGEOF'
{
  "name": "spotify-overlay-desktop",
  "version": "1.0.0",
  "main": "app.js",
  "scripts": { "start": "electron ." },
  "devDependencies": { "electron": "^31.0.0" },
  "dependencies": {
    "express": "^4.19.2",
    "open": "^8.4.2",
    "node-fetch": "^2.7.0"
  }
}
PKGEOF
spinner_stop ok "package.json written"

spinner_start "writing app.js (with Spotify API)..."
cat > "$INSTALL_DIR/app.js" << 'APPEOF'
const { app, BrowserWindow, screen, ipcMain, Tray, Menu, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const { exec } = require('child_process');
const express = require('express');
const open = require('open');
const fetch = require('node-fetch');

let win;
let tray = null;
let accessToken = null;
let refreshToken = null;
let tokenExpires = 0;

const CONFIG_PATH = path.join(__dirname, 'config.json');
const TOKEN_PATH = path.join(__dirname, 'tokens.json');
const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));

function loadTokens() {
    try {
        if (fs.existsSync(TOKEN_PATH)) {
            const t = JSON.parse(fs.readFileSync(TOKEN_PATH, 'utf8'));
            accessToken = t.accessToken;
            refreshToken = t.refreshToken;
            tokenExpires = t.expires || 0;
        }
    } catch (e) {}
}

function saveTokens() {
    fs.writeFileSync(TOKEN_PATH, JSON.stringify({
        accessToken,
        refreshToken,
        expires: tokenExpires
    }, null, 2));
}

async function ensureToken() {
    if (accessToken && Date.now() < tokenExpires - 60000) return accessToken;

    if (refreshToken) {
        try {
            const res = await fetch('https://accounts.spotify.com/api/token', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'Authorization': 'Basic ' + Buffer.from(config.clientId + ':' + config.clientSecret).toString('base64')
                },
                body: new URLSearchParams({
                    grant_type: 'refresh_token',
                    refresh_token: refreshToken
                })
            });
            const data = await res.json();
            if (data.access_token) {
                accessToken = data.access_token;
                tokenExpires = Date.now() + (data.expires_in * 1000);
                if (data.refresh_token) refreshToken = data.refresh_token;
                saveTokens();
                return accessToken;
            }
        } catch (e) {}
    }
    return null;
}

function startAuthServer() {
    return new Promise((resolve) => {
        const server = express();
        server.get('/callback', async (req, res) => {
            const code = req.query.code;
            if (!code) {
                res.send('No code received');
                return;
            }
            try {
                const tokenRes = await fetch('https://accounts.spotify.com/api/token', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded',
                        'Authorization': 'Basic ' + Buffer.from(config.clientId + ':' + config.clientSecret).toString('base64')
                    },
                    body: new URLSearchParams({
                        grant_type: 'authorization_code',
                        code,
                        redirect_uri: config.redirectUri
                    })
                });
                const data = await tokenRes.json();
                if (data.access_token) {
                    accessToken = data.access_token;
                    refreshToken = data.refresh_token;
                    tokenExpires = Date.now() + (data.expires_in * 1000);
                    saveTokens();
                    res.send('<h2 style="font-family:sans-serif;color:#1DB954">Success! You can close this tab and return to kitty123.</h2>');
                    setTimeout(() => server.close(), 1000);
                    resolve(true);
                } else {
                    res.send('Token error: ' + JSON.stringify(data));
                    resolve(false);
                }
            } catch (e) {
                res.send('Error: ' + e.message);
                resolve(false);
            }
        });
        server.listen(8888, () => {
            const scopes = 'playlist-read-private playlist-read-collaborative user-library-read user-read-playback-state user-read-currently-playing';
            const authUrl = `https://accounts.spotify.com/authorize?client_id=${config.clientId}&response_type=code&redirect_uri=${encodeURIComponent(config.redirectUri)}&scope=${encodeURIComponent(scopes)}`;
            open(authUrl);
        });
    });
}

async function spotifyGet(endpoint) {
    const token = await ensureToken();
    if (!token) return null;
    const res = await fetch('https://api.spotify.com/v1' + endpoint, {
        headers: { 'Authorization': 'Bearer ' + token }
    });
    if (res.status === 401) {
        accessToken = null;
        return null;
    }
    if (!res.ok) return null;
    return res.json();
}

function createOverlayWindow() {
    const { width, height } = screen.getPrimaryDisplay().workAreaSize;
    win = new BrowserWindow({
        width: 480, height: 110,
        x: Math.floor((width - 480) / 2), y: height - 130,
        frame: false, transparent: true, alwaysOnTop: true,
        resizable: true, hasShadow: false, skipTaskbar: true,
        webPreferences: { nodeIntegration: false, contextIsolation: true, preload: path.join(__dirname, 'preload.js') }
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
            if (isRobloxActive) { if (!win.isVisible()) win.showInactive(); }
            else { if (win.isVisible()) win.hide(); }
        });
    }, 250);

    // Current track via AppleScript (works on Free + never forces focus)
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
                        set trackId to id of cTrack
                        return trackName & "||" & artistName & "||" & totalDur & "||" & playerPos & "||" & pState & "||" & artworkUrl & "||" & trackId
                    on error
                        return "No Track"
                    end try
                end tell
            end if
            return "No Track"
        `;
        exec(`osascript -e '${appleScript}'`, (err, stdout) => {
            if (err || !stdout || stdout.trim() === "No Track") {
                win.webContents.send('spotify-data', { track: "Spotify", artist: "No track playing", position: 0, duration: 1, status: "paused", image: "", id: "" });
                return;
            }
            const parts = stdout.trim().split('||');
            if (parts.length >= 7) {
                const trackTitle = parts[0];
                const artistName = parts[1];
                const rawDur = Number(parts[2]);
                const rawPos = Number(parts[3]);
                const isAd = trackTitle.toLowerCase().includes("advertisement") || artistName.toLowerCase().includes("spotify") || rawDur === 0;
                const calculatedDur = isAd ? 30 : Math.floor(rawDur / 1000);
                const calculatedPos = isAd ? Math.floor(rawPos) : rawPos;
                win.webContents.send('spotify-data', {
                    track: trackTitle, artist: artistName,
                    duration: calculatedDur, position: calculatedPos,
                    status: parts[4].toLowerCase(), image: parts[5], id: parts[6], isAd: isAd
                });
            }
        });
    }, 250);
}

ipcMain.on('spotify-control', async (event, data) => {
    // Basic controls stay on AppleScript so they never force Spotify to front
    if (['playpause','next','prev','scrub'].includes(data.action)) {
        let script = '';
        if (data.action === 'playpause') script = 'tell application "Spotify" to playpause';
        if (data.action === 'next') script = 'tell application "Spotify" to next track';
        if (data.action === 'prev') script = 'tell application "Spotify" to previous track';
        if (data.action === 'scrub') script = `tell application "Spotify" to set player position to ${data.value}`;
        if (script) exec(`osascript -e '${script}'`);
        return;
    }

    if (data.action === 'playUri') {
        exec(`osascript -e 'tell application "Spotify" to play track "${data.value}"'`);
        return;
    }

    if (data.action === 'playPlaylist') {
        exec(`osascript -e 'tell application "Spotify" to play track "${data.value}"'`);
        return;
    }

    if (data.action === 'getRealPlaylists') {
        const token = await ensureToken();
        if (!token) {
            win.webContents.send('playlists-reply', []);
            return;
        }
        try {
            let all = [];
            let url = '/me/playlists?limit=50';
            while (url) {
                const res = await spotifyGet(url);
                if (!res || !res.items) break;
                all = all.concat(res.items.map(p => ({
                    title: p.name,
                    id: p.uri,
                    isPlaylist: true,
                    image: (p.images && p.images[0]) ? p.images[0].url : null
                })));
                url = res.next ? res.next.replace('https://api.spotify.com/v1', '') : null;
            }
            // also add Liked Songs
            all.unshift({ title: 'Liked Songs', id: 'spotify:user:spotify:playlist:37i9dQZF1DX4sWSpwq3LiO', isPlaylist: true });
            win.webContents.send('playlists-reply', all);
        } catch (e) {
            win.webContents.send('playlists-reply', []);
        }
        return;
    }

    if (data.action === 'getPlaylistTracks') {
        const token = await ensureToken();
        if (!token) {
            win.webContents.send('tracks-reply', []);
            return;
        }
        try {
            // extract playlist id from uri
            let playlistId = data.value;
            if (playlistId.includes(':')) playlistId = playlistId.split(':').pop();
            let all = [];
            let url = `/playlists/${playlistId}/tracks?limit=100`;
            while (url) {
                const res = await spotifyGet(url);
                if (!res || !res.items) break;
                all = all.concat(res.items.filter(i => i.track).map(i => ({
                    title: i.track.name,
                    artist: i.track.artists.map(a => a.name).join(', '),
                    id: i.track.uri,
                    image: (i.track.album && i.track.album.images && i.track.album.images[0]) ? i.track.album.images[0].url : null
                })));
                url = res.next ? res.next.replace('https://api.spotify.com/v1', '') : null;
            }
            win.webContents.send('tracks-reply', all);
        } catch (e) {
            win.webContents.send('tracks-reply', []);
        }
        return;
    }

    if (data.action === 'search') {
        const token = await ensureToken();
        if (!token) {
            win.webContents.send('search-reply', []);
            return;
        }
        try {
            const q = encodeURIComponent(data.value);
            const res = await spotifyGet(`/search?q=${q}&type=track&limit=20`);
            if (!res || !res.tracks) {
                win.webContents.send('search-reply', []);
                return;
            }
            const tracks = res.tracks.items.map(t => ({
                title: t.name,
                artist: t.artists.map(a => a.name).join(', '),
                id: t.uri,
                image: (t.album && t.album.images && t.album.images[0]) ? t.album.images[0].url : null
            }));
            win.webContents.send('search-reply', tracks);
        } catch (e) {
            win.webContents.send('search-reply', []);
        }
        return;
    }
});

ipcMain.on('resize-window', (event, bounds) => {
    if (!win || win.isDestroyed()) return;
    const { width: scrW, height: scrH } = screen.getPrimaryDisplay().workAreaSize;
    win.setBounds({
        width: Math.floor(bounds.width), height: Math.floor(bounds.height),
        x: Math.floor((scrW - bounds.width) / 2), y: scrH - Math.floor(bounds.height) - 20
    }, true);
});

ipcMain.on('start-auth', async () => {
    const ok = await startAuthServer();
    if (ok && win && !win.isDestroyed()) {
        win.webContents.send('auth-success');
    }
});

app.whenReady().then(async () => {
    loadTokens();
    createOverlayWindow();
    createTrayMenu();

    // if no token yet, trigger auth
    if (!accessToken) {
        setTimeout(() => {
            if (win && !win.isDestroyed()) win.webContents.send('need-auth');
        }, 1500);
    }

    app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createOverlayWindow(); });
});
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
APPEOF
spinner_stop ok "app.js written"

spinner_start "writing preload.js..."
cat > "$INSTALL_DIR/preload.js" << 'PREEOF'
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('electronAPI', {
    onSpotifyData: (callback) => ipcRenderer.on('spotify-data', (_event, value) => callback(value)),
    onPlaylistsReply: (callback) => ipcRenderer.on('playlists-reply', (_event, value) => callback(value)),
    onTracksReply: (callback) => ipcRenderer.on('tracks-reply', (_event, value) => callback(value)),
    onSearchReply: (callback) => ipcRenderer.on('search-reply', (_event, value) => callback(value)),
    onNeedAuth: (callback) => ipcRenderer.on('need-auth', () => callback()),
    onAuthSuccess: (callback) => ipcRenderer.on('auth-success', () => callback()),
    sendControl: (action, value = null) => ipcRenderer.send('spotify-control', { action, value }),
    startAuth: () => ipcRenderer.send('start-auth'),
    resizeWindow: (bounds) => ipcRenderer.send('resize-window', bounds)
});
PREEOF
spinner_stop ok "preload.js written"

spinner_start "writing icon..."
echo "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAWklEQVQ4y2P4//8/AyUYGegETGg0gGgD0M0gWh9WDRDVAHQzSDYAXQ0w1gB0M8g2AN0MMNYAdDPINgDdDLL1YdUAUQ0g2gB0M4jWh1UDRDWAaAPQzSBaH8wAALw9GBl7N9GNAAAAAElFTkSuQmCC" | base64 -d > "$INSTALL_DIR/icon.png" 2>/dev/null || touch "$INSTALL_DIR/icon.png"
spinner_stop ok "icon ready"

spinner_start "writing overlay.html..."
cat > "$INSTALL_DIR/overlay.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<title>kitty123 Overlay</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;overflow:hidden;background:transparent !important;background-color:rgba(0,0,0,0) !important;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;user-select:none;-webkit-user-select:none}
body{display:flex;align-items:center;justify-content:center;flex-direction:column;gap:10px}
.shell{-webkit-app-region:drag;width:450px;height:80px;border-radius:18px;background:rgba(16,16,19,.88);border:1px solid rgba(255,255,255,.22);box-shadow:0 12px 40px rgba(0,0,0,.45),inset 0 1px 0 rgba(255,255,255,.12);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);display:flex;align-items:center;padding:0 12px;gap:12px;position:relative;overflow:hidden;transition:all 0.25s ease-in-out}
.art{-webkit-app-region:no-drag;width:56px;height:56px;border-radius:12px;background:rgba(45,45,50,.8);object-fit:cover;flex-shrink:0;cursor:pointer}
.artph{width:56px;height:56px;border-radius:12px;background:rgba(45,45,50,.8);display:flex;align-items:center;justify-content:center;color:rgba(255,255,255,.25);font-size:20px;flex-shrink:0;cursor:pointer;-webkit-app-region:no-drag}
.meta{flex:1;min-width:0;display:flex;flex-direction:column;justify-content:center;height:64px;position:relative}
.track{color:#fff;font-weight:700;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding-right:55px}
.artist{color:rgb(170,170,178);font-size:12px;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding-right:55px}
.row{display:flex;align-items:center;gap:8px;margin-top:8px}
.btns{-webkit-app-region:no-drag;display:flex;gap:12px;flex-shrink:0;color:#fff;font-size:14px;font-weight:700;cursor:pointer}
.btns span:hover{color:rgb(30,215,96)}
.progress-wrap{-webkit-app-region:no-drag;flex:1;display:flex;flex-direction:column;gap:2px;min-width:0}
.bar-bg{height:4px;border-radius:2px;background:rgba(255,255,255,.25);position:relative;cursor:pointer}
.bar-fill{height:100%;width:0%;border-radius:2px;background:#fff;transition:width 0.1s linear}
.times{display:flex;justify-content:space-between;color:rgb(170,170,178);font-size:10px;font-variant-numeric:tabular-nums}
.island-waves{-webkit-app-region:no-drag;position:absolute;right:8px;top:6px;display:flex;align-items:flex-end;gap:3px;height:22px;width:48px;justify-content:flex-end;cursor:pointer;z-index:10}
.wave-bar{width:3px;height:6px;border-radius:2px;transition:height 0.12s ease-in-out,background 0.3s ease;background:linear-gradient(180deg,#78b4ff,#4a90e2,#2a6fd6)}
.drawer{-webkit-app-region:no-drag;width:450px;height:0px;border-radius:18px;background:rgba(16,16,19,.92);border:0px solid rgba(255,255,255,.22);box-shadow:0 12px 40px rgba(0,0,0,.45);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);display:flex;flex-direction:column;overflow:hidden;transition:all 0.25s ease-in-out;opacity:0}
.drawer.open{height:260px;border:1px solid rgba(255,255,255,.22);opacity:1;padding:12px}
.search-box{width:100%;padding:8px 12px;background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.1);border-radius:8px;color:#fff;outline:none;font-size:12px;margin-bottom:12px}
.search-box::placeholder{color:rgba(255,255,255,.4)}
.nav-tabs{display:flex;gap:14px;border-bottom:1px solid rgba(255,255,255,.1);padding-bottom:6px;margin-bottom:10px}
.tab{color:rgba(255,255,255,.5);font-size:12px;font-weight:600;cursor:pointer}
.tab.active{color:#fff;border-bottom:2px solid #fff;padding-bottom:4px}
.back-btn{color:rgb(30,215,96);font-size:11px;cursor:pointer;margin-bottom:6px;display:none;font-weight:bold}
.list-container{flex:1;overflow-y:auto;display:flex;flex-direction:column;gap:6px}
.list-item{display:flex;align-items:center;gap:8px;padding:6px;border-radius:6px;cursor:pointer}
.list-item:hover{background:rgba(255,255,255,.05)}
.list-thumb{width:32px;height:32px;border-radius:4px;background:rgba(255,255,255,.1);object-fit:cover;flex-shrink:0}
.list-thumb-ph{width:32px;height:32px;border-radius:4px;background:rgba(255,255,255,.1);display:flex;align-items:center;justify-content:center;color:#fff;font-size:12px;flex-shrink:0}
.list-info{display:flex;flex-direction:column;min-width:0;flex:1}
.list-title{color:#fff;font-size:12px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.list-sub{color:rgba(255,255,255,.5);font-size:10px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.play-btn{-webkit-app-region:no-drag;color:rgb(30,215,96);font-size:14px;font-weight:bold;padding:4px 8px;cursor:pointer;border-radius:4px;flex-shrink:0}
.play-btn:hover{background:rgba(30,215,96,.15)}
.search-hint{color:rgba(255,255,255,.4);font-size:11px;text-align:center;padding:20px 10px}
.auth-banner{background:rgba(30,215,96,.15);border:1px solid rgba(30,215,96,.4);border-radius:8px;padding:10px;margin-bottom:10px;text-align:center;color:#1DB954;font-size:12px;cursor:pointer}
</style>
</head>
<body>
<div class="shell" id="playerShell">
  <img class="art" id="art" alt="" style="display:none"/>
  <div class="artph" id="artPh">♪</div>
  <div class="meta">
    <div class="track" id="track">Connecting...</div>
    <div class="artist" id="artist"></div>
    <div class="island-waves" id="islandWaves" title="Click to expand">
      <div class="wave-bar"></div><div class="wave-bar"></div><div class="wave-bar"></div>
      <div class="wave-bar"></div><div class="wave-bar"></div><div class="wave-bar"></div>
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
  <div id="authBanner" class="auth-banner" style="display:none">Click here to connect your Spotify account</div>
  <input type="text" class="search-box" id="searchBox" placeholder="Search songs or artists..." />
  <div class="nav-tabs" id="drawerTabs">
    <div class="tab active" id="tabPlaylists">Playlists</div>
    <div class="tab" id="tabRecents">Recents</div>
    <div class="tab" id="tabSearch">Search</div>
  </div>
  <div class="back-btn" id="backBtn">&lt; Back to Playlists</div>
  <div class="list-container" id="listContainer"></div>
</div>
<canvas id="colorCanvas" style="display:none;" width="10" height="10"></canvas>
<script>
let total=1,pos=0,playing=false,lastImg="",baseScale=1.0,drawerOpen=false,viewingPlaylist=false;
let recentTracksMemory=[],loadedPlaylistsMemory=[],currentGradient="linear-gradient(180deg,#78b4ff,#4a90e2,#2a6fd6)";
const canvas=document.getElementById("colorCanvas"),ctx=canvas.getContext("2d");

function fmt(s){s=Math.max(0,Math.floor(s+.5));return Math.floor(s/60)+":"+String(s%60).padStart(2,"0")}
function updateWaveColors(r,g,b){
    const r2=Math.min(255,r+40),g2=Math.min(255,g+30),b2=Math.min(255,b+50);
    const r3=Math.max(0,Math.floor(r*0.6)),g3=Math.max(0,Math.floor(g*0.7)),b3=Math.min(255,b+80);
    currentGradient=`linear-gradient(180deg,rgb(${r},${g},${b}),rgb(${r2},${g2},${b2}),rgb(${r3},${g3},${b3}))`;
    document.querySelectorAll('.wave-bar').forEach(bar=>{bar.style.background=currentGradient});
}
function extractColorAndTint(imgEl){
    try{
        ctx.drawImage(imgEl,0,0,10,10);
        const data=ctx.getImageData(0,0,10,10).data;
        let r=0,g=0,b=0,count=0;
        for(let i=0;i<data.length;i+=4){
            if(data[i]+data[i+1]+data[i+2]>60&&data[i]+data[i+1]+data[i+2]<680){r+=data[i];g+=data[i+1];b+=data[i+2];count++}
        }
        if(count>0){r=Math.floor(r/count);g=Math.floor(g/count);b=Math.floor(b/count);updateWaveColors(r,g,b)}
    }catch(e){}
}
function setArt(url){
    const img=document.getElementById("art"),ph=document.getElementById("artPh");
    if(!url){img.style.display="none";ph.style.display="flex";lastImg="";return}
    if(url===lastImg)return;
    lastImg=url;img.crossOrigin="Anonymous";
    img.onload=()=>{img.style.display="block";ph.style.display="none";extractColorAndTint(img)};
    img.onerror=()=>{img.style.display="none";ph.style.display="flex";lastImg=""};
    img.src=url;
}
function paint(){
    const r=total>0?Math.min(1,pos/total):0;
    document.getElementById("fill").style.width=(r*100)+"%";
    document.getElementById("tCur").textContent=fmt(pos);
    document.getElementById("tTot").textContent=fmt(total);
}
function updateWindowBounds(){
    let targetW=Math.floor(480*baseScale),targetH=Math.floor((drawerOpen?380:110)*baseScale);
    document.getElementById("playerShell").style.width=`${Math.floor(450*baseScale)}px`;
    document.getElementById("playerShell").style.height=`${Math.floor(80*baseScale)}px`;
    document.getElementById("extendedDrawer").style.width=`${Math.floor(450*baseScale)}px`;
    window.electronAPI.resizeWindow({width:targetW,height:targetH});
}
function populateList(items){
    const container=document.getElementById("listContainer");
    container.innerHTML="";
    if(!items||items.length===0){container.innerHTML=`<div class="search-hint">No items found</div>`;return}
    items.forEach(item=>{
        const row=document.createElement("div");row.className="list-item";
        let visualMarkup=`<div class="list-thumb-ph">${item.isPlaylist?"📁":"🎵"}</div>`;
        if(item.image)visualMarkup=`<img class="list-thumb" src="${item.image}" onerror="this.style.display='none'"/>`;
        let playMarkup=item.isPlaylist?`<div class="play-btn" title="Play playlist">▶</div>`:"";
        row.innerHTML=`${visualMarkup}<div class="list-info"><div class="list-title">${item.title}</div><div class="list-sub">${item.artist||""}</div></div>${playMarkup}`;
        const playBtn=row.querySelector('.play-btn');
        if(playBtn)playBtn.addEventListener('click',e=>{e.stopPropagation();window.electronAPI.sendControl('playPlaylist',item.id)});
        row.addEventListener('click',()=>{
            if(item.isPlaylist){viewingPlaylist=true;document.getElementById('drawerTabs').style.display='none';document.getElementById('backBtn').style.display='block';window.electronAPI.sendControl('getPlaylistTracks',item.id)}
            else if(item.id)window.electronAPI.sendControl('playUri',item.id);
        });
        container.appendChild(row);
    });
}

document.getElementById('backBtn').addEventListener('click',()=>{viewingPlaylist=false;document.getElementById('backBtn').style.display='none';document.getElementById('drawerTabs').style.display='flex';populateList(loadedPlaylistsMemory)});
document.getElementById('islandWaves').addEventListener('click',()=>{
    drawerOpen=!drawerOpen;const dr=document.getElementById("extendedDrawer");
    if(drawerOpen){dr.classList.add("open");if(!viewingPlaylist)window.electronAPI.sendControl('getRealPlaylists')}
    else dr.classList.remove("open");
    updateWindowBounds();
});
document.getElementById('art').addEventListener('click',()=>{baseScale=baseScale===1.0?1.25:(baseScale===1.25?0.85:1.0);updateWindowBounds()});
document.getElementById('artPh').addEventListener('click',()=>{baseScale=baseScale===1.0?1.25:(baseScale===1.25?0.85:1.0);updateWindowBounds()});

document.getElementById('tabPlaylists').addEventListener('click',e=>{
    document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));e.target.classList.add('active');
    viewingPlaylist=false;document.getElementById('backBtn').style.display='none';document.getElementById('drawerTabs').style.display='flex';
    window.electronAPI.sendControl('getRealPlaylists');
});
document.getElementById('tabRecents').addEventListener('click',e=>{
    document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));e.target.classList.add('active');
    viewingPlaylist=false;document.getElementById('backBtn').style.display='none';document.getElementById('drawerTabs').style.display='flex';
    populateList(recentTracksMemory);
});
document.getElementById('tabSearch').addEventListener('click',e=>{
    document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));e.target.classList.add('active');
    viewingPlaylist=false;document.getElementById('backBtn').style.display='none';document.getElementById('drawerTabs').style.display='flex';
    document.getElementById('listContainer').innerHTML=`<div class="search-hint">Type a song or artist and press Enter</div>`;
    document.getElementById('searchBox').focus();
});

window.electronAPI.onPlaylistsReply(playlists=>{
    loadedPlaylistsMemory=playlists;
    if(document.getElementById('tabPlaylists').classList.contains('active')&&!viewingPlaylist)populateList(playlists);
});
window.electronAPI.onTracksReply(tracks=>{if(viewingPlaylist)populateList(tracks)});
window.electronAPI.onSearchReply(tracks=>{populateList(tracks)});

document.getElementById('searchBox').addEventListener('keydown',e=>{
    if(e.key==='Enter'&&e.target.value.trim()){
        window.electronAPI.sendControl('search',e.target.value);
        document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
        document.getElementById('tabSearch').classList.add('active');
    }
});

document.getElementById('btnPrev').addEventListener('click',()=>window.electronAPI.sendControl('prev'));
document.getElementById('btnPP').addEventListener('click',()=>window.electronAPI.sendControl('playpause'));
document.getElementById('btnNext').addEventListener('click',()=>window.electronAPI.sendControl('next'));
document.getElementById('progressBg').addEventListener('click',e=>{
    const rect=e.currentTarget.getBoundingClientRect();
    const clickX=e.clientX-rect.left;
    const percentage=Math.max(0,Math.min(1,clickX/rect.width));
    const targetSeconds=Math.floor(percentage*total);
    pos=targetSeconds;paint();
    window.electronAPI.sendControl('scrub',targetSeconds);
});

window.electronAPI.onSpotifyData(d=>{
    document.getElementById("track").textContent=d.track||"Spotify";
    document.getElementById("artist").textContent=d.artist||"No track playing";
    total=Math.max(1,Number(d.duration)||1);
    const incomingPos=Math.max(0,Number(d.position)||0);
    if(!playing||Math.abs(incomingPos-pos)>2)pos=incomingPos;
    playing=d.status==="playing"||d.status==="kpsp";
    document.getElementById("btnPP").textContent=playing?"||":"|>";
    setArt(d.image||"");paint();
    if(d.track&&d.track!=="Spotify"&&d.id&&!recentTracksMemory.some(t=>t.id===d.id)){
        recentTracksMemory.unshift({title:d.track,artist:d.artist,id:d.id,image:d.image});
        if(recentTracksMemory.length>20)recentTracksMemory.pop();
    }
});

window.electronAPI.onNeedAuth(()=>{
    document.getElementById('authBanner').style.display='block';
});
window.electronAPI.onAuthSuccess(()=>{
    document.getElementById('authBanner').style.display='none';
    window.electronAPI.sendControl('getRealPlaylists');
});
document.getElementById('authBanner').addEventListener('click',()=>{
    window.electronAPI.startAuth();
});

setInterval(()=>{if(playing&&pos<total){pos=Math.min(total,pos+0.1);paint()}},100);
const bars=document.querySelectorAll('.wave-bar');
setInterval(()=>{bars.forEach(bar=>{if(playing){bar.style.height=(Math.floor(Math.random()*18)+4)+'px'}else{bar.style.height='5px'}bar.style.background=currentGradient})},140);
</script>
</body>
</html>
HTMLEOF
spinner_stop ok "overlay.html written"

spinner_start "installing dependencies..."
npm install --silent
xattr -cr "$INSTALL_DIR/node_modules/electron" 2>/dev/null || true
codesign --force --deep --sign - "$INSTALL_DIR/node_modules/electron/dist/Electron.app" 2>/dev/null || true
spinner_stop ok "dependencies installed"

spinner_start "launching kitty123..."
sleep 0.5
nohup npm start > "$INSTALL_DIR/overlay.log" 2>&1 &
disown
spinner_stop ok "kitty123 launched"

echo ""
printf "  ${C_GREEN}✔  All done — enjoy kitty123${C_RESET}\n"
echo ""
log "A browser window will open so you can log in to Spotify."
log "After you approve, your real playlists + search will work."
echo ""
