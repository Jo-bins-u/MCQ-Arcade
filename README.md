# MCQ Arcade v3.2

Nested quiz sections, accounts that sync across browsers (Supabase), a **study assistant docked on every page** (Groq), and an **admin console** where you decide who can see which topics and what each person is allowed to do.

```
public/index.html     the whole front end
api/chat.js           assistant endpoint (holds your Groq key, checks the user's permission)
api/config.js         passes the public Supabase URL + key to the browser
supabase/schema.sql   tables, security rules and admin functions (fresh install OR upgrade from v2)
```

## 1. Supabase (database + login)

1. Create a project at supabase.com.
2. **SQL Editor → New query**, paste `supabase/schema.sql`, **Run**. It is safe to run again later, and if you already have v2 data it is upgraded in place (see *Upgrading* below).
3. **Project Settings → API**: copy the **Project URL** and the **anon / publishable key**.
4. **Authentication → Providers → Email** is on by default. For personal use you can turn off **Confirm email** so sign-up logs you in at once. If you keep it on, set **Authentication → URL Configuration → Site URL** to your Vercel address.

## 2. Groq (assistant)

Create a key at console.groq.com/keys. Default model: `llama-3.3-70b-versatile` (override with `GROQ_MODEL`).

## 3. Deploy on Vercel

Push to GitHub, import in Vercel (framework **Other**, no build command), and add `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GROQ_API_KEY` (and optionally `GROQ_MODEL`). Local run: copy `.env.example` to `.env.local`, then `npm install && npm start`.

> **Sign up yourself first.** The first account created becomes the admin. Everyone after that is a normal user. (To hand the role to someone else later, use the Users tab in the Admin console.)

## Admin console

Admins see an **Admin console** button on the home page.

**Users tab.** Every account, with seven switches each: *AI assistant, Mixed shuffle, Read answers, Mistake log, Personal notes, Reset progress, Own content* (create private sections and import their own questions). You can also make someone an admin or disable their account. Changes apply the next time that person loads or returns to the tab.

**Content & access tab.** The section tree, with a badge on each:
- **Everyone**: any signed-in user can open it.
- **Selected users**: only the people you tick. Tick *also apply to sections inside* to cascade.
- **Hidden**: admins only (a draft).

Open **Questions** on a section to narrow one question (*same as section / selected users / hidden*), edit it, delete it, or add a single question by hand. A sub-section is only reachable if every section above it is too.

**Defaults & data tab.** The permissions new accounts start with (and a button to apply them to everyone), plus a delete-everything danger zone.

All of this is enforced by the database (Row Level Security), not just hidden in the UI. A user can't read content you haven't shared, and the assistant endpoint refuses people whose AI switch is off.

## Code in questions

Questions, options and explanations can contain code. Use single backticks for inline code and a fenced block for snippets:

````md
### Q1. Trace
What is printed?

```python
def f(n):
    return n ** 2 // 2

print(f(4))
```

- A. 8
- B. 16
- C. 4
- D. 2

**Answer:** A
**Reason:** `4 ** 2` is 16 and `16 // 2` is 8.
````

Inline code shows as a monospace chip, and fenced blocks show as a dark snippet with indentation kept and light syntax colouring (the language after the opening fence is optional; Python's `//` is never treated as a comment). Options that are obviously code, like `[(0, 0), (0, 1)]`, get monospace automatically. The importer, the question editor and the Read-answers view all keep code exactly as written.

Questions imported before this version lost their code indentation. Re-import them (or fix them with **Edit** in the Admin console) to get proper snippets.

## Notes under every topic

Every topic card (and section page) has a **Notes** button. Write as many notes as you like for that topic; light formatting works (`**bold**`, `- bullets`, `` `code` ``). Notes are private to each person and need the *Personal notes* permission.

They all come together in two places:
- the **My notes** page (top bar), grouped by topic, with live search, **Copy all** and **Download .md**;
- a **Your notes** card on the dashboard showing the latest three, with a count.

The assistant can read the notes on those pages, so you can ask it to summarise them, find gaps, or turn them into practice questions.

## Look and feel

A top bar with Dashboard, My notes and Mistakes (plus Admin for admins) and an account menu; a friendly greeting with a progress ring and one-tap "Review tricky" / "Surprise me" buttons; colour-coded topic cards; encouraging wording after each answer. Light and dark mode follow your device.

## Importing a markdown file, topic by topic

**Add questions** (admin console or home) accepts one or more `.md` files (click or drag-and-drop) and/or pasted text. Any heading that is not a question becomes a **topic**; deeper headings nest inside it; each question is filed under the nearest topic above it:

```md
# Cloud Computing
One-line description (optional).

## Service models
### Q1. Models
**Which model gives you virtual machines?**

- A. IaaS
- B. SaaS
- C. FaaS

**Answer:** A. IaaS
**Reason:** Why A is right.
**Remember:** One-line memory hook.

# Ethical Hacking
## Q1. Ports
**Default HTTPS port?**
**Answer:** 443
```

MCQ, MSQ (`**Answer:** A, C`) and short answers (no options) all work. Duplicates are skipped and headings with no questions inside them (intro text, contents) are ignored. Press **Check questions** to preview exactly which sections will be created, then choose who can open them (everyone, selected users, or a hidden draft). Existing sections with the same name are reused. Files without topic headings can still be split into sets of 15 or put in one topic, as before.

## The assistant

A chat panel docks to the right of every page and pushes the content over rather than covering it (drag its left edge to resize; on phones it slides over as a drawer). It always knows where you are:

| Page | What it can do |
|---|---|
| A question | Hints only until you answer, then full explanations |
| Home / a section | Study plans, quick quizzes, explain a topic, what to revise next |
| Read answers, Mistake log, Results | Summaries, patterns in your mistakes, memory tricks |
| Add questions / Admin | Explains the import format and writes questions you can copy in one click |

## Upgrading from v2

Run the new `supabase/schema.sql` once (it also adds the notes table; running it again is always safe). Your questions, progress, notes and XP are kept. The oldest account becomes the admin, and all existing sections become **hidden** (visible only to their owner and to admins) until you share them from **Content & access**. Re-deploy the app files, and you're done.

## Notes

- Progress, notes, XP and the mistake log are always private to each person, even for content you share.
- Each section or question is owned by whoever created it. People with the *Own content* permission can only manage their own private sections.
- XP gains are capped per request on the server. The assistant has no per-user rate limit, so use Disable or the AI switch if someone overuses it.
