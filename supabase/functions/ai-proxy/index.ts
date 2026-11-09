// MEDS — AI proxy Edge Function (Claude).
//
// The Flutter app calls this with the signed-in user's JWT, a system prompt, a
// user prompt and a JSON schema. The function verifies the user, asks Claude
// for a JSON answer matching the schema, and returns it as `{ text }`.
// The Claude API key never lives in the app — it is a server-side secret.
//
// Deploy:  supabase functions deploy ai-proxy
// Secrets: supabase secrets set ANTHROPIC_API_KEY=sk-ant-...  (see AI_SETUP.md)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk@1.3.0";

// Haiku is plenty for short wellness summaries and is the cheapest model.
const MODEL = "claude-haiku-5-5";
// Any signed-in user can call this, so cap what one request can cost.
const MAX_PROMPT_CHARS = 20_000;
const MAX_TOKENS = 8000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  try {
    // --- Authenticate the caller ------------------------------------------
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing authorization." }, 401);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: userErr } = await supabase.auth.getUser();
    if (userErr || !user) return json({ error: "You are not signed in." }, 401);

    // --- Parse & validate the payload -------------------------------------
    const body = await req.json().catch(() => null);
    const system = typeof body?.system === "string" ? body.system.trim() : "";
    const prompt = typeof body?.prompt === "string" ? body.prompt.trim() : "";
    const schema = body?.schema;

    if (!system || !prompt) return json({ error: "Missing prompt." }, 400);
    if (system.length + prompt.length > MAX_PROMPT_CHARS) {
      return json({ error: "Prompt too long." }, 413);
    }
    if (typeof schema !== "object" || schema === null || Array.isArray(schema)) {
      return json({ error: "Missing response schema." }, 400);
    }

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return json({ error: "Server AI is not configured (ANTHROPIC_API_KEY)." }, 500);
    }

    // --- Ask Claude ---------------------------------------------------------
    const client = new Anthropic({ apiKey, timeout: 60_000, maxRetries: 1 });
    const msg = await client.messages.create({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system,
      messages: [{ role: "user", content: prompt }],
      output_config: {
        effort: "low", // short summaries; keeps latency and cost down
        format: { type: "json_schema", schema },
      },
    });

    if (msg.stop_reason === "refusal") {
      return json({ error: "The AI declined to answer this request." }, 502);
    }
    const text = msg.content
      .flatMap((b) => (b.type === "text" ? [b.text] : []))
      .join("");
    if (msg.stop_reason !== "end_turn" || !text) {
      return json({ error: "The AI returned an incomplete answer. Try again." }, 502);
    }

    return json({ text }, 200);
  } catch (e) {
    console.error(e);
    if (e instanceof Anthropic.APIError) {
      return json({ error: friendlyClaudeError(e.status) }, e.status === 429 ? 429 : 502);
    }
    return json({ error: (e as Error)?.message ?? "Unexpected error." }, 500);
  }
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function friendlyClaudeError(status: number | undefined): string {
  if (status === undefined) return "The server could not reach Claude. Try again shortly.";
  if (status === 401 || status === 403) {
    return "Claude rejected the server's API key (check the ANTHROPIC_API_KEY secret).";
  }
  if (status === 429) return "AI rate limit reached. Please wait a moment and try again.";
  if (status >= 500) return "The AI service is busy right now. Try again shortly.";
  return `AI request failed (Claude HTTP ${status}).`;
}
