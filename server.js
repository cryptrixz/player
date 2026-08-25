const express = require("express");
const crypto = require("crypto");
const app = express();

app.use(express.json());

app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.header("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.sendStatus(200);
  next();
});

const CLIENT_ID = process.env.SPOTIFY_CLIENT_ID;
const CLIENT_SECRET = process.env.SPOTIFY_CLIENT_SECRET;
const REDIRECT_URI = process.env.RAILWAY_URL
  ? `${process.env.RAILWAY_URL.replace(/\/$/, "")}/callback`
  : "http://localhost:3000/callback";

const users = {}; 

function newUserId() {
  return crypto.randomBytes(9).toString("base64url");
}

function emptyTrack() {
  return { status: "paused", track: "No Track Playing", artist: "", position: 0, duration: 1, image: "" };
}

function basicAuthHeader() {
  return "Basic " + Buffer.from(`${CLIENT_ID}:${CLIENT_SECRET}`).toString("base64");
}

async function refreshAccessToken(user) {
  if (!user.refreshToken) return null;
  const resp = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      Authorization: basicAuthHeader(),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: user.refreshToken,
    }),
  });
  const data = await resp.json();
  if (data.access_token) {
    user.accessToken = data.access_token;
    user.accessTokenExpiresAt = Date.now() + (data.expires_in - 30) * 1000;
    if (data.refresh_token) user.refreshToken = data.refresh_token;
  }
  return user.accessToken;
}

async function getValidAccessToken(user) {
  if (user.accessToken && Date.now() < user.accessTokenExpiresAt) return user.accessToken;
  return refreshAccessToken(user);
}

async function pollUser(userId) {
  const user = users[userId];
  if (!user) return;
  try {
    const token = await getValidAccessToken(user);
    if (!token) return;

    const resp = await fetch("https://api.spotify.com/v1/me/player/currently-playing", {
      headers: { Authorization: `Bearer ${token}` },
    });

    if (resp.status === 204) {
      user.currentTrack = emptyTrack();
      return;
    }
    if (!resp.ok) return;

    const data = await resp.json();
    if (!data || !data.item) {
      user.currentTrack = emptyTrack();
      return;
    }

    const images = (data.item.album && data.item.album.images) || [];
    const image = images.length ? images[0].url : "";

    user.currentTrack = {
      status: data.is_playing ? "playing" : "paused",
      track: data.item.name,
      artist: data.item.artists.map((a) => a.name).join(", "),
      position: Math.floor((data.progress_ms || 0) / 1000),
      duration: Math.floor((data.item.duration_ms || 1000) / 1000),
      image,
    };
  } catch (err) {
    console.error(`Poll error for ${userId}:`, err.message);
  }
}

async function pollAllUsers() {
  await Promise.all(Object.keys(users).map(pollUser));
}
setInterval(pollAllUsers, 5000);

app.get("/", (req, res) => {
  res.send(
    `Spotify overlay backend running. ${Object.keys(users).length} user(s) connected. ` +
    `<a href="/login">Click here to connect your own Spotify account</a>.`
  );
});

app.get("/login", (req, res) => {
  const userId = newUserId();
  const scope = "user-read-currently-playing user-read-playback-state user-modify-playback-state";
  const params = new URLSearchParams({
    response_type: "code",
    client_id: CLIENT_ID,
    scope,
    redirect_uri: REDIRECT_URI,
    state: userId,
  });
  res.redirect("https://accounts.spotify.com/authorize?" + params.toString());
});

app.get("/callback", async (req, res) => {
  const code = req.query.code;
  const userId = req.query.state;
  if (!code || !userId) return res.status(400).send("Missing code or state");

  try {
    const resp = await fetch("https://accounts.spotify.com/api/token", {
      method: "POST",
      headers: {
        Authorization: basicAuthHeader(),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code,
        redirect_uri: REDIRECT_URI,
      }),
    });
    const data = await resp.json();

    if (!data.refresh_token) {
      return res.status(400).send("Auth failed: " + JSON.stringify(data));
    }

    users[userId] = {
      refreshToken: data.refresh_token,
      accessToken: data.access_token,
      accessTokenExpiresAt: Date.now() + (data.expires_in - 30) * 1000,
      currentTrack: emptyTrack(),
    };

    pollUser(userId);

    const railwayBase = process.env.RAILWAY_URL
      ? process.env.RAILWAY_URL.replace(/\/$/, "")
      : REDIRECT_URI.replace("/callback", "");

    res.send(`
      <html><body style="font-family: monospace; padding: 24px; line-height: 1.6;">
        <h2>Connected!</h2>
        <p>Your personal ID: <b>${userId}</b></p>
        <p>Paste this exact snippet into your executor:</p>
        <pre style="background:#eee; padding:12px;">_G.SpotifyUserId = "${userId}"
loadstring(game:HttpGet("https://raw.githubusercontent.com/cryptrixz/player/refs/heads/main/overlay.lua"))()</pre>
        <p>To check your status anytime from Terminal:</p>
        <pre style="background:#eee; padding:12px;">curl "${railwayBase}/music?id=${userId}"</pre>
        <p>Save your ID somewhere — you'll need it every time. You can close this tab.</p>
      </body></html>
    `);
  } catch (err) {
    res.status(500).send("Error: " + err.message);
  }
});

app.get("/music", (req, res) => {
  const userId = req.query.id;
  const user = users[userId];
  if (!user) return res.json(emptyTrack());
  res.json(user.currentTrack);
});

async function controlAction(userId, action) {
  const user = users[userId];
  if (!user) throw new Error("Unknown user");
  const token = await getValidAccessToken(user);
  if (!token) throw new Error("Not authorized");

  const endpoints = {
    play: { method: "PUT", url: "https://api.spotify.com/v1/me/player/play" },
    pause: { method: "PUT", url: "https://api.spotify.com/v1/me/player/pause" },
    next: { method: "POST", url: "https://api.spotify.com/v1/me/player/next" },
    previous: { method: "POST", url: "https://api.spotify.com/v1/me/player/previous" },
  };
  const ep = endpoints[action];
  if (!ep) throw new Error("Unknown action");

  const resp = await fetch(ep.url, {
    method: ep.method,
    headers: { Authorization: `Bearer ${token}` },
  });
  return resp.status;
}

app.post("/control/:action", async (req, res) => {
  const userId = req.query.id;
  const { action } = req.params;
  try {
    const status = await controlAction(userId, action);
    if (status === 404) {
      return res.status(404).json({ ok: false, error: "No active Spotify device found. Open Spotify somewhere first." });
    }
    res.json({ ok: true });
    pollUser(userId); 
  } catch (err) {
    res.status(400).json({ ok: false, error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Spotify overlay backend listening on port ${PORT}`);
});
