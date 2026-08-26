const fs = require('fs');
const path = require('path');
const fetch = require('node-fetch');

const CLIENT_ID = "4119f479e60d4a049e3d384ec366dc65";
const CLIENT_SECRET = "d7a0a39742f24c228af25e0b0ef56ef7";
const TOKEN_PATH = path.join(__dirname, 'token.txt');

let accessToken = null;
let tokenExpires = 0;

async function getToken() {
    if (accessToken && Date.now() < tokenExpires - 60000) return accessToken;

    try {
        const refresh = fs.readFileSync(TOKEN_PATH, 'utf8').trim();
        if (!refresh) return null;

        const res = await fetch('https://accounts.spotify.com/api/token', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Authorization': 'Basic ' + Buffer.from(CLIENT_ID + ':' + CLIENT_SECRET).toString('base64')
            },
            body: 'grant_type=refresh_token&refresh_token=' + encodeURIComponent(refresh)
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
