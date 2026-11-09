// MEDS — "send my data to an email" Edge Function.
//
// The Flutter app calls this with the signed-in user's JWT and a list of
// base64 attachments (PDF report + CSV). The function verifies the user, then
// hands the email to an email provider (Resend by default, or SendGrid).
// No email credentials ever live in the app — they are server-side secrets.
//
// Deploy:  supabase functions deploy send-data-email
// Secrets: see EMAIL_EXPORT_SETUP.md
//
// deno-lint-ignore-file no-explicit-any

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface Attachment {
  filename: string;
  mimeType?: string;
  contentBase64: string;
}

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
    if (!body) return json({ error: "Invalid request body." }, 400);

    const to = String(body.to ?? "").trim();
    const subject = String(body.subject ?? "MEDS data export");
    const message = String(body.message ?? "");
    const attachments: Attachment[] = Array.isArray(body.attachments)
      ? body.attachments
      : [];

    if (!isEmail(to)) return json({ error: "Invalid recipient email." }, 400);
    if (attachments.length === 0) {
      return json({ error: "No attachments to send." }, 400);
    }

    // Guard against oversized payloads (~15 MB of raw attachment bytes).
    const totalBytes = attachments.reduce(
      (n, a) => n + Math.floor((a.contentBase64?.length ?? 0) * 0.75),
      0,
    );
    if (totalBytes > 15 * 1024 * 1024) {
      return json({ error: "Attachments too large (max 15 MB)." }, 413);
    }

    // --- Send --------------------------------------------------------------
    const html = buildHtml(user.email ?? "a MEDS user", message);
    const provider = (Deno.env.get("EMAIL_PROVIDER") ?? "resend").toLowerCase();

    if (provider === "sendgrid") {
      await sendWithSendgrid(to, subject, html, attachments);
    } else {
      await sendWithResend(to, subject, html, attachments);
    }

    return json({ ok: true, sentTo: to }, 200);
  } catch (e) {
    return json({ error: (e as Error)?.message ?? "Unexpected error." }, 500);
  }
});

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

async function sendWithResend(
  to: string,
  subject: string,
  html: string,
  attachments: Attachment[],
) {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) throw new Error("Server email is not configured (RESEND_API_KEY).");

  const email = Deno.env.get("EMAIL_FROM") ?? "onboarding@resend.dev";
  const name = Deno.env.get("EMAIL_FROM_NAME") ?? "MEDS";

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: `${name} <${email}>`,
      to: [to],
      subject,
      html,
      attachments: attachments.map((a) => ({
        filename: a.filename,
        content: a.contentBase64, // Resend accepts base64 here
      })),
    }),
  });

  if (!res.ok) {
    const detail = await res.text();
    throw new Error(friendlyProviderError("Resend", res.status, detail));
  }
}

async function sendWithSendgrid(
  to: string,
  subject: string,
  html: string,
  attachments: Attachment[],
) {
  const key = Deno.env.get("SENDGRID_API_KEY");
  if (!key) throw new Error("Server email is not configured (SENDGRID_API_KEY).");

  const email = Deno.env.get("EMAIL_FROM");
  if (!email) {
    throw new Error("EMAIL_FROM must be a SendGrid-verified sender address.");
  }
  const name = Deno.env.get("EMAIL_FROM_NAME") ?? "MEDS";

  const res = await fetch("https://api.sendgrid.com/v3/mail/send", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      personalizations: [{ to: [{ email: to }] }],
      from: { email, name },
      subject,
      content: [{ type: "text/html", value: html }],
      attachments: attachments.map((a) => ({
        filename: a.filename,
        type: a.mimeType ?? "application/octet-stream",
        content: a.contentBase64,
        disposition: "attachment",
      })),
    }),
  });

  if (!res.ok) {
    const detail = await res.text();
    throw new Error(friendlyProviderError("SendGrid", res.status, detail));
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isEmail(v: string): boolean {
  return /^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$/.test(v);
}

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function buildHtml(senderEmail: string, message: string): string {
  const note = message.trim().length > 0
    ? `<p style="margin:0 0 16px;padding:12px 14px;background:#f4f6fb;border-radius:10px;color:#1b2333;">${
      escapeHtml(message)
    }</p>`
    : "";
  return `
  <div style="font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;max-width:560px;margin:0 auto;color:#1b2333;">
    <div style="display:flex;align-items:center;gap:8px;margin-bottom:12px;">
      <span style="width:12px;height:12px;border-radius:50%;background:#00a84b;display:inline-block;"></span>
      <strong style="color:#00a84b;font-size:16px;">MEDS</strong>
    </div>
    <h2 style="margin:0 0 8px;font-size:19px;">Your MEDS data export</h2>
    ${note}
    <p style="margin:0 0 16px;line-height:1.5;">
      The attached files were exported from MEDS by <strong>${
    escapeHtml(senderEmail)
  }</strong>.
      You'll find a PDF report and/or a CSV spreadsheet of the emotion &amp;
      heart-rate readings attached to this email.
    </p>
    <p style="margin:0;color:#7a8699;font-size:12px;line-height:1.5;">
      MEDS (Multimodal Emotional Detection System) supports personal wellness
      self-awareness. It is not a medical device and does not provide a
      diagnosis.
    </p>
  </div>`;
}

function escapeHtml(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function friendlyProviderError(
  provider: string,
  status: number,
  detail: string,
): string {
  // Surface the most common misconfiguration clearly.
  if (status === 401 || status === 403) {
    return `${provider} rejected the API key (check the secret and its permissions).`;
  }
  if (status === 422 || status === 400) {
    return `${provider} rejected the request — usually the "from" address is not verified. ${detail}`;
  }
  return `${provider} error (${status}): ${detail}`;
}
