// Netlify Function: hands the (public) Supabase URL + anon key to the browser.
exports.handler = async function (event) {
  if (event.httpMethod !== "GET") {
    return { statusCode: 405, body: JSON.stringify({ error: "Use GET" }) };
  }
  const { SUPABASE_URL, SUPABASE_ANON_KEY } = process.env;
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "SUPABASE_URL and SUPABASE_ANON_KEY are not set" }),
    };
  }
  return {
    statusCode: 200,
    headers: { "Cache-Control": "public, max-age=300", "Content-Type": "application/json" },
    body: JSON.stringify({ supabaseUrl: SUPABASE_URL, supabaseAnonKey: SUPABASE_ANON_KEY }),
  };
};

