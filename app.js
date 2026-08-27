const fs = require('fs');
const path = require('path');
const fetch = require('node-fetch');

const CLIENT_ID = "4119f479e60d4a049e3d384ec366dc65";
const CLIENT_SECRET = "d7a0a39742f24c228af25e0b0ef56ef7";
const TOKEN_PATH = path.join(__dirname, 'token.txt');
const PLAYLISTS_PATH = path.join(__dirname, 'playlists.json');

let accessToken = null;
let tokenExpires = 0;

async function getToken() {
    if (accessToken && Date.now() < tokenExpires - 60000) return accessToken;
    try {
        const stored = fs.readFileSync(TOKEN_PATH, 'utf8').trim();
        if (!stored) return null;

        if (stored.length > 100) {
            accessToken = stored;
            tokenExpires = Date.now() + 3500000;
            return accessToken;
        }

        const res = await fetch('https://accounts.spotify.com/api/token', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Authorization': 'Basic ' + Buffer.from(CLIENT_ID + ':' + CLIENT_SECRET).toString('base64')
            },
            body: 'grant_type=refresh_token&refresh_token=' + encodeURIComponent(stored)
        });
        const data = await res.json();
        if (data.access_token) {
            accessToken = data.access_token;
            tokenExpires = Date.now() + (data.expires_in * 1000);
            if (data.refresh_token) {
                fs.writeFileSync(TOKEN_PATH, data.refresh_token);
            }
            return accessToken;
        }
    } catch (e) {}
    return null;
}

async function spotifyGet(endpoint) {
    const token = await getToken();
    if (!token) return null;
    const res = await fetch('https://api.spotify.com/v1' + endpoint, {
        headers: { 'Authorization': 'Bearer ' + token }
    });
    if (!res.ok) return null;
    return res.json();
}

function loadCachedPlaylists() {
    try {
        if (fs.existsSync(PLAYLISTS_PATH)) {
            return JSON.parse(fs.readFileSync(PLAYLISTS_PATH, 'utf8'));
        }
    } catch (e) {}
    return null;
}

function savePlaylists(playlists) {
    try {
        fs.writeFileSync(PLAYLISTS_PATH, JSON.stringify(playlists, null, 2));
    } catch (e) {}
}

async function getPlaylists() {
    const cached = loadCachedPlaylists();
    if (cached && cached.length > 0) {
        return cached;
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

        if (all.length > 0) {
            savePlaylists(all); 
        }
        return all;
    } catch (e) {
        return [];
    }
}

module.exports = { getToken, spotifyGet, getPlaylists, loadCachedPlaylists, savePlaylists };
