// Hands the (public) Supabase URL + anon key to the browser, so they live in one place: Vercel env vars.
module.exports = function handler(req, res) {
  const { SUPABASE_URL, SUPABASE_ANON_KEY } = process.env;
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return res.status(500).json({ error: "SUPABASE_URL and SUPABASE_ANON_KEY are not set" });
  }
  res.setHeader("Cache-Control", "public, max-age=300");
  res.status(200).json({ supabaseUrl: SUPABASE_URL, supabaseAnonKey: SUPABASE_ANON_KEY });
};
