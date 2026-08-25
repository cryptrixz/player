const express = require("express");
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

let refreshToken = process.env.SPOTIFY_REFRESH_TOKEN || null;
let accessToken = null;
let accessTokenExpiresAt = 0;

function emptyTrack() {
  return { status: "paused", track: "No Track Playing", artist: "", position: 0, duration: 1, image: "" };
}

let currentTrack = emptyTrack();

function basicAuthHeader() {
  return "Basic " + Buffer.from(`${CLIENT_ID}:${CLIENT_SECRET}`).toString("base64");
}

async function refreshAccessToken() {
  if (!refreshToken) return null;
  const resp = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      Authorization: basicAuthHeader(),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    }),
  });
  const data = await resp.json();
  if (data.access_token) {
    accessToken = data.access_token;
    accessTokenExpiresAt = Date.now() + (data.expires_in - 30) * 1000;
    if (data.refresh_token) refreshToken = data.refresh_token;
  } else {
    console.error("Refresh failed:", data);
  }
  return accessToken;
}

async function getValidAccessToken() {
  if (accessToken && Date.now() < accessTokenExpiresAt) return accessToken;
  return refreshAccessToken();
}

async function pollSpotify() {
  try {
    const token = await getValidAccessToken();
    if (!token) {
      console.log("No valid token yet — not authorized. Visit /login.");
      return;
    }

    const resp = await fetch("https://api.spotify.com/v1/me/player/currently-playing", {
      headers: { Authorization: `Bearer ${token}` },
    });

    if (resp.status === 204) {
      currentTrack = emptyTrack();
      return;
    }
    if (!resp.ok) {
      console.error("Spotify API error:", resp.status, await resp.text());
      return;
    }

    const data = await resp.json();
    if (!data || !data.item) {
      currentTrack = emptyTrack();
      return;
    }

    const images = (data.item.album && data.item.album.images) || [];
    const image = images.length ? images[0].url : "";

    currentTrack = {
      status: data.is_playing ? "playing" : "paused",
      track: data.item.name,
      artist: data.item.artists.map((a) => a.name).join(", "),
      position: Math.floor((data.progress_ms || 0) / 1000),
      duration: Math.floor((data.item.duration_ms || 1000) / 1000),
      image,
    };
  } catch (err) {
    console.error("Poll error:", err.message);
  }
}

setInterval(pollSpotify, 5000);

app.get("/", (req, res) => {
  const authed = !!refreshToken;
  res.send(
    authed
      ? "Spotify overlay backend running. Authorized and polling."
      : `Not authorized. <a href="/login">Click here to connect your Spotify account</a>.`
  );
});

app.get("/login", (req, res) => {
  const scope = "user-read-currently-playing user-read-playback-state user-modify-playback-state";
  const params = new URLSearchParams({
    response_type: "code",
    client_id: CLIENT_ID,
    scope,
    redirect_uri: REDIRECT_URI,
  });
  res.redirect("https://accounts.spotify.com/authorize?" + params.toString());
});

app.get("/callback", async (req, res) => {
  const code = req.query.code;
  if (!code) return res.status(400).send("Missing code: " + JSON.stringify(req.query));

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

    refreshToken = data.refresh_token;
    accessToken = data.access_token;
    accessTokenExpiresAt = Date.now() + (data.expires_in - 30) * 1000;

    console.log("=== COPY THIS AS YOUR SPOTIFY_REFRESH_TOKEN RAILWAY VARIABLE ===");
    console.log(refreshToken);
    console.log("==================================================================");

    pollSpotify();

    res.send(`
      <html><body style="font-family: monospace; padding: 24px; line-height: 1.6;">
        <h2>Connected!</h2>
        <p><b>Required — do this now, or this breaks again on the next restart:</b></p>
        <ol>
          <li>Go to your Railway service → check the <b>Deploy Logs</b> tab</li>
          <li>Find the refresh token printed there (between the === lines)</li>
          <li>Copy it, then go to <b>Variables</b> and add:<br>
              <code>SPOTIFY_REFRESH_TOKEN</code> = (the token you copied)</li>
          <li>Save — Railway will redeploy once. After that, this survives every future restart.</li>
        </ol>
        <p>You can close this tab once you've saved the variable.</p>
      </body></html>
    `);
  } catch (err) {
    res.status(500).send("Error: " + err.message);
  }
});

app.get("/music", (req, res) => {
  res.json(currentTrack);
});

async function controlAction(action) {
  const token = await getValidAccessToken();
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
  try {
    const status = await controlAction(req.params.action);
    if (status === 404) {
      return res.status(404).json({ ok: false, error: "No active Spotify device found." });
    }
    res.json({ ok: true });
    pollSpotify();
  } catch (err) {
    res.status(400).json({ ok: false, error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Spotify overlay backend listening on port ${PORT}`);
  if (refreshToken) {
    console.log("Found saved refresh token — polling immediately.");
    pollSpotify();
  } else {
    console.log("No refresh token set. Visit /login to connect your account.");
  }
});
