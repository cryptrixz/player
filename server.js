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

let currentTrack = {
  status: "paused",
  track: "No Track Playing",
  artist: "",
  position: 0,
  duration: 1,
  image: "",
};

app.get("/", (_req, res) => res.send("ok"));

app.get("/music", (_req, res) => res.json(currentTrack));

app.post("/music", (req, res) => {
  const b = req.body || {};
  currentTrack = {
    status: b.status || "paused",
    track: b.track || "No Track Playing",
    artist: b.artist || "",
    position: Math.max(0, Number(b.position) || 0),
    duration: Math.max(1, Number(b.duration) || 1),
    image: b.image || "",
  };
  res.json({ ok: true });
});

app.get("/art", async (req, res) => {
  try {
    const url = req.query.url;
    if (!url || typeof url !== "string") return res.status(400).end();
    if (!/mzstatic\.com/i.test(url)) return res.status(400).end();
    const r = await fetch(url);
    if (!r.ok) return res.status(502).end();
    const buf = Buffer.from(await r.arrayBuffer());
    res.set("Content-Type", r.headers.get("content-type") || "image/jpeg");
    res.set("Cache-Control", "public, max-age=86400");
    res.send(buf);
  } catch {
    res.status(502).end();
  }
});

app.post("/control/:action", (_req, res) => res.json({ ok: true }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log("listening", PORT));
