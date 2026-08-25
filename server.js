const express = require("express");
const app = express();

app.use(express.json());

app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.header("Access-Control-Allow-Headers", "Content-Type, x-push-secret");
  if (req.method === "OPTIONS") return res.sendStatus(200);
  next();
});

let currentTrack = {
  status: "paused",
  track: "No Track Playing",
  artist: "",
  position: 0,
  duration: 1,
};

const PUSH_SECRET = process.env.PUSH_SECRET || null;

app.get("/", (req, res) => {
  res.send("Spotify overlay backend is running. Use GET/POST /music.");
});

app.get("/music", (req, res) => {
  res.json(currentTrack);
});

app.post("/music", (req, res) => {
  if (PUSH_SECRET && req.header("x-push-secret") !== PUSH_SECRET) {
    return res.status(401).json({ error: "invalid push secret" });
  }

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
});
