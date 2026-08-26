const express = require("express");
const app = express();

app.use(express.json({ limit: "2mb" }));
app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.header("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.sendStatus(200);
  next();
});

function emptyTrack() {
  return {
    status: "paused",
    track: "No Track Playing",
    artist: "",
    position: 0,
    duration: 1,
    image: "",
  };
}

let currentTrack = emptyTrack();

app.get("/", (_req, res) => {
  res.send("Spotify overlay backend (passthrough).");
});

app.get("/music", (_req, res) => {
  res.json(currentTrack);
});

app.post("/music", (req, res) => {
  const body = req.body || {};
  currentTrack = {
    status: body.status || "paused",
    track: body.track || "No Track Playing",
    artist: body.artist || "",
    position: Number(body.position) || 0,
    duration: Math.max(1, Number(body.duration) || 1),
    image: body.image || "",
  };
  res.json({ ok: true });
});

app.post("/control/:action", (_req, res) => {
  res.json({ ok: true });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Passthrough backend listening on port ${PORT}`);
});
