// Netlify Function: AI assistant endpoint.
// Keeps the Groq key on the server, only answers signed-in people whose account has the
// "AI assistant" permission, and builds a different prompt depending on which page the person is looking at.
const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";

const BASE = `You are the friendly study assistant inside "MCQ Arcade", a quiz app for revising multiple-choice, multi-select and short-answer questions. You are available on every page, and the PAGE CONTEXT below tells you what the student is looking at right now.

General rules:
- Be concise: usually under 150 words unless you are asked to write something longer. Short paragraphs, simple bullets, **bold** for key terms. No headings.
- Explain concepts in plain language, with a short example or analogy when it helps.
- You can explain topics, summarise, build revision plans, quiz the student with NEW practice questions one at a time (wait for their answer before revealing yours), and explain how the app works.
- Use the page context when it is relevant, but never claim to see data that isn't in it. If you are not sure about a fact, say so instead of guessing.
- Stay on studying and the app. If asked about something unrelated, steer back gently.`;

const IMPORT_FORMAT = `The app imports questions from markdown. Headings that are not questions become topics (a "#" heading is a topic, deeper headings nest inside it). Each question is a heading plus a body:

\`\`\`
# Topic name
Optional one-line description.

## Q1. Short title
**Question text?**

- A. First option
- B. Second option
- C. Third option
- D. Fourth option

**Answer:** B. Second option
**Reason:** Why B is right.
**Remember:** One-line memory hook.
\`\`\`

Several correct options: "**Answer:** A, C". Short answer (no options): "**Answer:** 128" (ranges like "10 to 12" and alternatives like "a / b" are accepted). When asked to write questions, always output them inside ONE fenced code block in exactly this format so they can be copied straight into the import box, and make sure every answer is actually correct.`;

const VIEW_RULES = {
  quiz: `The student is on ONE question.
- While the student has NOT answered yet: never state, confirm, deny, or hint at which option letter is correct, even if they ask directly, say they give up, or propose a guess. Instead explain the key terms, break the question into smaller parts, show how to eliminate options by reasoning (without saying which option survives), and end with ONE guiding question. If they ask for the answer, kindly decline, give a stronger hint, and tell them to submit an answer so you can explain everything afterwards. If they propose an answer, ask them to explain their reasoning rather than judging it.
- Once the student HAS answered: reveal and explain freely. Say why the correct answer is right. If they were wrong, name the likely misconception behind their choice. Briefly say why the other options fail, then offer a short memory trick.`,
  home: `The student is browsing their sections. Help them decide what to study, explain topics in the section, or quiz them verbally. Weak topics listed are ones they still get wrong.`,
  study: `The student is reading the answers to a set. Help them understand and remember them: summarise, connect ideas, create mnemonics, or quiz them on the items.`,
  log: `The student is looking at their mistake log (questions they got wrong). Help them find patterns in their errors, understand the concepts, and build a short revision plan.`,
  summary: `The student just finished a round. Walk through what they missed, name the likely misconceptions, and suggest what to do next.`,
  add: `The person is on the page for importing questions. ${IMPORT_FORMAT}`,
  admin: `The person is in the admin tools. Permissions are switched on/off per user; sections can be shared with everyone, selected users, or hidden, and a single question can be narrowed further. If they ask for questions, ${IMPORT_FORMAT}`,
  notes: `The student is on their personal notes page; the notes are in the page context. Help them tidy, summarise and organise them, spot gaps or likely mistakes (gently), and turn them into practice questions. Stay faithful to what the notes say.`,
  qedit: `The person is editing a single question. Help them word it clearly and check that the keyed answer is correct.`,
  other: `Help with whatever the student asks.`,
};

const clip = (s, n) => String(s == null ? "" : s).slice(0, n);
const list = (v) => (Array.isArray(v) ? v.map((x) => clip(x, 120)).join(", ") : clip(v, 400));

function item(it) {
  const out = [`  Q: ${clip(it.q, 400)}`];
  if (Array.isArray(it.options) && it.options.length) out.push(`  Options: ${it.options.slice(0, 8).map((o, i) => `${String.fromCharCode(65 + i)}) ${clip(o, 160)}`).join(" | ")}`);
  if (it.answer != null) out.push(`  Answer: ${clip(it.answer, 300)}`);
  if (it.yourAnswer != null) out.push(`  Student answered: ${clip(it.yourAnswer, 300)}`);
  if (it.why) out.push(`  Explanation: ${clip(it.why, 400)}`);
  return out.join("\n");
}

function contextBlock(c = {}) {
  const view = Object.keys(VIEW_RULES).includes(c.view) ? c.view : "other";
  const lines = [`Page: ${view}`, `Signed-in role: ${c.role === "admin" ? "admin" : "student"}`];
  if (view === "quiz") {
    lines.push(`Topic: ${clip(c.topic, 200)}`, `Question type: ${clip(c.type, 10)}`, `Question: ${clip(c.question, 2000)}`);
    if (Array.isArray(c.options) && c.options.length) {
      lines.push("Options:");
      c.options.slice(0, 10).forEach((o) => lines.push(`  ${clip(o.key, 2)}) ${clip(o.text, 400)}`));
    }
    if (c.answered) {
      // Only an answered question gets the solution. Unanswered requests never see it, even if the client sent it.
      lines.push(
        "Student status: HAS ANSWERED.",
        `Student's answer: ${list(c.studentAnswer)}`,
        `Correct answer: ${list(c.correct)}`,
        `Student was ${c.wasCorrect ? "correct" : "incorrect"}.`,
        `Official explanation: ${clip(c.explanation, 1500) || "(none provided)"}`
      );
    } else {
      lines.push("Student status: has NOT answered yet. Do not reveal the answer.");
    }
  } else if (view === "home") {
    lines.push(`Location: ${clip(c.where, 200)}`);
    if (c.stats) lines.push(`Stats: ${clip(JSON.stringify(c.stats), 300)}`);
    if (Array.isArray(c.subtopics) && c.subtopics.length) lines.push(`Sub-topics: ${c.subtopics.slice(0, 30).map((x) => clip(x, 80)).join("; ")}`);
    if (Array.isArray(c.weak) && c.weak.length) lines.push(`Weakest topics: ${c.weak.slice(0, 6).map((x) => clip(x, 100)).join("; ")}`);
    if (Array.isArray(c.sample) && c.sample.length) lines.push("Some questions in scope (stems only):", ...c.sample.slice(0, 14).map((q) => `  - ${clip(q, 200)}`));
  } else if (view === "notes") {
    if (c.topic) lines.push(`Topic: ${clip(c.topic, 200)}`);
    const ns = Array.isArray(c.items) ? c.items.slice(0, 25) : [];
    lines.push(ns.length ? "Student's notes:" : "The student has no notes here yet.");
    ns.forEach((n) => lines.push(`  - [${clip(n.topic, 100)}] ${clip(n.body, 600)}`));
  } else if (view === "study" || view === "log" || view === "summary") {
    if (c.topic) lines.push(`Topic: ${clip(c.topic, 200)}`);
    if (c.title) lines.push(`Round: ${clip(c.title, 120)}`);
    if (c.total != null) lines.push(`Score: ${Number(c.right) || 0} of ${Number(c.total) || 0}`);
    if (c.stillWrong != null) lines.push(`Still wrong: ${Number(c.stillWrong) || 0}, fixed: ${Number(c.fixed) || 0}`);
    if (Array.isArray(c.items) && c.items.length) lines.push("Items:", ...c.items.slice(0, 12).map(item));
  }
  return lines.join("\n");
}

exports.handler = async function (event) {
  const headers = { "Cache-Control": "no-store", "Content-Type": "application/json" };

  if (event.httpMethod !== "POST") {
    return { statusCode: 405, headers, body: JSON.stringify({ error: "Use POST" }) };
  }

  const { GROQ_API_KEY, SUPABASE_URL, SUPABASE_ANON_KEY, GROQ_MODEL } = process.env;
  if (!GROQ_API_KEY || !SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: "Server is missing GROQ_API_KEY, SUPABASE_URL or SUPABASE_ANON_KEY." }) };
  }
  const base = SUPABASE_URL.replace(/\/$/, "");

  // 1) Must be signed in.
  const token = ((event.headers && (event.headers.authorization || event.headers.Authorization)) || "").replace(/^Bearer\s+/i, "");
  if (!token) return { statusCode: 401, headers, body: JSON.stringify({ error: "Please sign in first." }) };

  const sbHeaders = { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${token}` };
  try {
    const u = await fetch(`${base}/auth/v1/user`, { headers: sbHeaders });
    if (!u.ok) return { statusCode: 401, headers, body: JSON.stringify({ error: "Your session expired. Sign in again." }) };
  } catch {
    return { statusCode: 502, headers, body: JSON.stringify({ error: "Couldn't verify your session." }) };
  }

  // 2) The admin must have left the AI assistant switched on for this account.
  try {
    const p = await fetch(`${base}/rest/v1/rpc/has_perm`, {
      method: "POST",
      headers: { ...sbHeaders, "Content-Type": "application/json" },
      body: JSON.stringify({ p: "tutor" }),
    });
    if (!p.ok) return { statusCode: 502, headers, body: JSON.stringify({ error: "Couldn't check your permissions. Run the latest supabase/schema.sql." }) };
    if ((await p.json()) !== true) return { statusCode: 403, headers, body: JSON.stringify({ error: "The assistant is turned off for your account. Ask your admin." }) };
  } catch {
    return { statusCode: 502, headers, body: JSON.stringify({ error: "Couldn't check your permissions." }) };
  }

  let body = {};
  try { body = JSON.parse(event.body || "{}"); } catch { body = {}; }

  const msgs = (Array.isArray(body.messages) ? body.messages : [])
    .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .slice(-12)
    .map((m) => ({ role: m.role, content: clip(m.content, 1500) }));
  if (!msgs.length || msgs[msgs.length - 1].role !== "user") {
    return { statusCode: 400, headers, body: JSON.stringify({ error: "No question to answer." }) };
  }

  const ctx = body.context || {};
  const view = Object.keys(VIEW_RULES).includes(ctx.view) ? ctx.view : "other";
  const system = `${BASE}\n\n--- HOW TO HELP ON THIS PAGE ---\n${VIEW_RULES[view]}\n\n--- PAGE CONTEXT ---\n${contextBlock(ctx)}`;

  try {
    const r = await fetch(GROQ_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${GROQ_API_KEY}` },
      body: JSON.stringify({
        model: GROQ_MODEL || "llama-3.3-70b-versatile",
        temperature: 0.4,
        max_tokens: view === "add" || view === "admin" ? 1400 : 700,
        messages: [{ role: "system", content: system }, ...msgs],
      }),
    });
    if (!r.ok) {
      const raw = await r.text();
      console.error("Groq error", r.status, raw);
      let why = "";
      try { why = JSON.parse(raw).error.message || ""; } catch { why = raw; }
      return {
        statusCode: 502,
        headers,
        body: JSON.stringify({
          error: r.status === 429
            ? "The assistant is busy right now. Try again in a minute."
            : `Groq returned an error (${r.status}): ${clip(why, 200)}`,
        }),
      };
    }
    const j = await r.json();
    const reply = j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content;
    if (!reply) return { statusCode: 502, headers, body: JSON.stringify({ error: "The assistant sent an empty reply." }) };
    return { statusCode: 200, headers, body: JSON.stringify({ reply: reply.trim() }) };
  } catch (e) {
    console.error(e);
    return { statusCode: 502, headers, body: JSON.stringify({ error: "Couldn't reach the assistant service." }) };
  }
};

