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

let currentTrack = {
  status: "paused",
  track: "No Track Playing",
  artist: "",
  position: 0,
  duration: 1,
};

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
    if (data.refresh_token) refreshToken = data.refresh_token; // Spotify sometimes rotates it
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
    if (!token) return; // not authorized yet

    const resp = await fetch("https://api.spotify.com/v1/me/player/currently-playing", {
      headers: { Authorization: `Bearer ${token}` },
    });

    if (resp.status === 204) {
      currentTrack = { status: "paused", track: "No Track Playing", artist: "", position: 0, duration: 1 };
      return;
    }
    if (!resp.ok) return;

    const data = await resp.json();
    if (!data || !data.item) {
      currentTrack = { status: "paused", track: "No Track Playing", artist: "", position: 0, duration: 1 };
      return;
    }

    currentTrack = {
      status: data.is_playing ? "playing" : "paused",
      track: data.item.name,
      artist: data.item.artists.map((a) => a.name).join(", "),
      position: Math.floor((data.progress_ms || 0) / 1000),
      duration: Math.floor((data.item.duration_ms || 1000) / 1000),
    };
  } catch (err) {
    console.error("Spotify poll error:", err.message);
  }
}

setInterval(pollSpotify, 5000);

app.get("/", (req, res) => {
  const authed = !!refreshToken;
  res.send(
    authed
      ? "Spotify overlay backend running. Authorized and polling Spotify."
      : `Not authorized yet. <a href="/login">Click here to connect your Spotify account</a>.`
  );
});

app.get("/login", (req, res) => {
  const scope = "user-read-currently-playing user-read-playback-state";
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
  if (!code) return res.status(400).send("Missing code");

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

    console.log("=== SAVE THIS AS SPOTIFY_REFRESH_TOKEN env var for persistence ===");
    console.log(refreshToken);
    console.log("====================================================================");

    pollSpotify();

    res.send(
      "Connected! Your Spotify status will now show in the overlay. " +
      "IMPORTANT: check your Railway logs, copy the refresh token printed there, " +
      "and save it as an SPOTIFY_REFRESH_TOKEN environment variable so this survives restarts. " +
      "You can close this tab."
    );
  } catch (err) {
    res.status(500).send("Error: " + err.message);
  }
});

app.get("/music", (req, res) => {
  res.json(currentTrack);
});

app.post("/music", (req, res) => {
  const { status, track, artist, position, duration } = req.body || {};
  currentTrack = {
    status: typeof status === "string" ? status : "paused",
    track: typeof track === "string" ? track : "No Track Playing",
    artist: typeof artist === "string" ? artist : "",
    position: typeof position === "number" ? position : 0,
    duration: typeof duration === "number" ? duration : 1,
  };
  res.json({ ok: true, currentTrack });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Spotify overlay backend listening on port ${PORT}`);
  if (refreshToken) {
    console.log("Found saved refresh token, starting to poll immediately.");
    pollSpotify();
  } else {
    console.log(`No refresh token yet. Visit ${REDIRECT_URI.replace("/callback", "/login")} to connect.`);
  }
});
