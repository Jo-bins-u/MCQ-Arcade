# MCQ Arcade 🕹️

> **A self-hosted quiz platform** — nested sections, per-user permissions, a Groq-powered AI study assistant, and a full admin console. Everything syncs across every browser you sign in on.

![Netlify](https://img.shields.io/badge/Deploy-Netlify-00C7B7?logo=netlify&logoColor=white)
![Supabase](https://img.shields.io/badge/Backend-Supabase-3ECF8E?logo=supabase&logoColor=white)
![Groq](https://img.shields.io/badge/AI-Groq-F55036?logo=groq&logoColor=white)
![Node](https://img.shields.io/badge/Node-%3E%3D18-339933?logo=node.js&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)

---

## ✨ Features

- **Three question types** — Multiple-choice (MCQ), multi-select (MSQ), and short-answer
- **Nested sections** — Organise questions into topics and sub-topics to any depth
- **Markdown import** — Paste or drag-and-drop `.md` files; the importer creates topics automatically
- **AI study assistant** — Groq-powered chat docked on every page; knows what you're looking at and gives hints without spoiling unanswered questions
- **Admin console** — Manage users, permissions, section visibility, and content from a built-in UI
- **Granular permissions** — Seven per-user toggles (AI assistant, shuffle, read answers, mistake log, notes, reset progress, own content)
- **Progress & XP** — Tracks every attempt per question; XP is calculated server-side
- **Mistake log** — Review every question you've gotten wrong, grouped by topic
- **Personal notes** — Write markdown notes under any topic; comes together in a searchable Notes page
- **Code in questions** — Inline backticks and fenced code blocks render with syntax colouring
- **Dark / light mode** — Follows your OS preference; override per-session
- **PWA ready** — Installable on Android and iOS

---

## 🏗️ Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Vanilla JS, single `public/index.html` |
| Auth + Database | [Supabase](https://supabase.com) (Postgres + Row Level Security) |
| AI assistant | [Groq](https://console.groq.com) (`llama-3.3-70b-versatile` by default) |
| API functions | Netlify Functions (Node ≥ 18) |
| Hosting | [Netlify](https://netlify.com) |
| Local dev server | Express (`server.js`) |

---

## 📁 Project Structure

```
├── public/
│   ├── index.html        # Entire frontend (one file)
│   ├── manifest.json     # PWA manifest
│   └── logo-*.png        # App icons (32 / 192 / 512 px)
├── netlify/
│   └── functions/
│       ├── chat.js       # AI assistant endpoint (guards Groq key + checks permissions)
│       └── config.js     # Passes public Supabase URL + anon key to the browser
├── api/                  # Same handlers, Express-style (used by server.js for local dev)
│   ├── chat.js
│   └── config.js
├── supabase/
│   └── schema.sql        # Tables, RLS policies, functions — safe to re-run
├── netlify.toml          # Build + redirect config
├── server.js             # Local Express dev server (no Netlify CLI needed)
└── .env.example          # Copy to .env.local for local development
```

---

## 🚀 Deploy to Netlify (5 minutes)

### 1 — Set up Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. **SQL Editor → New query** → paste the contents of `supabase/schema.sql` → **Run**.  
   *(Safe to re-run at any time. Upgrades from v2 in place.)*
3. **Project Settings → API**: copy your **Project URL** and **anon / publishable key**.
4. **Authentication → Providers → Email** is on by default. For a private install, disable **Confirm email** so sign-up is instant. If you keep it on, set **Auth → URL Configuration → Site URL** to your Netlify domain.

> **Sign up first.** The very first account becomes the admin. Everyone who signs up afterwards is a regular user.

### 2 — Get a Groq key

Create a free API key at [console.groq.com/keys](https://console.groq.com/keys).

### 3 — Deploy

1. Push this repo to GitHub.
2. Go to [app.netlify.com](https://app.netlify.com) → **Add new site → Import from GitHub**.
3. Netlify auto-detects `netlify.toml` — no build command needed.
4. **Site Settings → Environment Variables** → add:

| Variable | Description |
|---|---|
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_ANON_KEY` | Your Supabase anon/publishable key |
| `GROQ_API_KEY` | Your Groq API key |
| `GROQ_MODEL` | *(optional)* Override the default model (`llama-3.3-70b-versatile`) |

5. **Trigger deploy** — you're live.

---

## 💻 Local Development

**Option A — plain Node (no Netlify CLI)**

```bash
cp .env.example .env.local   # fill in your keys
npm install
npm start                    # http://localhost:3000
```

**Option B — Netlify Dev (matches production exactly)**

```bash
npm install -g netlify-cli
cp .env.example .env.local   # fill in your keys
npm run dev                  # http://localhost:8888
```

---

## 🛡️ Permissions

Each user has seven permission toggles the admin can flip individually or set as a site-wide default:

| Permission | What it unlocks |
|---|---|
| **AI assistant** | The Groq chat panel |
| **Mixed shuffle** | Shuffle questions across a whole section |
| **Read answers** | The "Read answers" study view |
| **Mistake log** | See and retry incorrect questions |
| **Personal notes** | Write markdown notes under topics |
| **Reset progress** | Erase their own XP and history |
| **Own content** | Create private sections and import their own questions |

Permissions are enforced both in the UI and by Postgres Row Level Security — they can't be bypassed by API calls.

---

## 📥 Importing Questions (Markdown Format)

Drag-and-drop or paste a `.md` file on the **Add questions** page. Headings that aren't questions become topics; deeper headings nest inside them.

````md
# Cloud Computing
One-line description (optional).

## Q1. Service models
**Which model gives you virtual machines?**

- A. IaaS
- B. SaaS
- C. FaaS

**Answer:** A. IaaS
**Reason:** IaaS provides raw compute — you manage the VMs.
**Remember:** "I" for Infrastructure.
````

| Format | Syntax |
|---|---|
| Multiple-choice (MCQ) | `**Answer:** B` |
| Multi-select (MSQ) | `**Answer:** A, C` |
| Short answer | `**Answer:** 443` (no options needed) |

Code blocks inside questions, options, and explanations are fully supported.

---

## 🗄️ Database Schema (overview)

| Table | Purpose |
|---|---|
| `profiles` | Role (`user`/`admin`), per-user permission overrides, XP, streak |
| `topics` | Sections and sub-sections with nested parent references |
| `questions` | Question data (JSONB), linked to a topic |
| `topic_access` | Rows granting specific users access to a `selected` section |
| `question_access` | Same, but per question |
| `progress` | Per-user, per-question attempt history |
| `notes` | Per-user, per-question text notes |
| `topic_notes` | Per-user free-form notes under a topic |
| `app_settings` | Site-wide defaults (e.g. default permissions for new accounts) |

All tables have RLS enabled. The `visible_topic_ids()` function walks the section tree recursively and returns only what the signed-in user is allowed to see.

---

## ⬆️ Upgrading from v2

Re-run `supabase/schema.sql` (it's idempotent — safe to run on existing data). Your questions, progress, notes, and XP are preserved. Existing sections become **Hidden** (admin-only) until you publish them from the Admin console → Content & access tab.

---

## 📄 License

MIT — do whatever you like with it.
