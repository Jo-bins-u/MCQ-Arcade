// Run MCQ Arcade without Vercel: serves public/ and the two API routes.
// Start with:  npm install  then  npm start   (reads .env or .env.local)
const path = require("path");
const fs = require("fs");
const express = require("express");

// Load env files without extra packages (.env.local overrides .env). Real environment variables win over both.
for (const f of [".env.local", ".env"]) {
  const p = path.join(__dirname, f);
  if (!fs.existsSync(p)) continue;
  for (const line of fs.readFileSync(p, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (m && !line.trim().startsWith("#") && process.env[m[1]] === undefined) {
      process.env[m[1]] = m[2].replace(/^(['"])(.*)\1$/, "$2");
    }
  }
}

const app = express();
app.use(express.json({ limit: "300kb" }));
app.get("/api/config", require("./api/config"));
app.post("/api/chat", require("./api/chat"));
app.use(express.static(path.join(__dirname, "public")));

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`MCQ Arcade running at http://localhost:${port}`));
