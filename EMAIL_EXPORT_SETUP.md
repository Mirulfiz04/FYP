# MEDS — Email / Export Data setup

This feature lets a user **send their MEDS data to any email address** as a
**PDF report** and/or a **CSV spreadsheet**. The email is sent from the MEDS
server (a Supabase Edge Function), so no email password ever lives in the app.

There are two places in the app:

- **Session Details → email icon** (top-right) → emails that one session.
- **Settings → Privacy & Security → Export data → "Export & email my data"**
  → emails the user's full history.

---

## 1. Update the Flutter app

A new dependency (`pdf`) was added. From the `meds_app` folder:

```bash
flutter pub get
```

That's all on the client side — the UI and services are already wired in.

---

## 2. Pick an email provider

The Edge Function can use **Resend** or **SendGrid**. Both have a free tier.
Pick one:

| | Resend (default) | SendGrid |
|---|---|---|
| Free tier | 3,000 emails/month | 100 emails/day |
| Send to **your own** email | ✅ works immediately | ✅ works after verifying 1 sender |
| Send to **anyone's** email | needs a verified **domain** | ✅ **single-sender verification is enough** |

👉 **If you don't own a domain and want to email *anyone*, use SendGrid.**
👉 **If you only need to email yourself (e.g. for a demo), Resend is fastest.**

### Get the API key

**Resend:** create a free account at resend.com → **API Keys** → create one
(starts with `re_...`). For testing you can send *from* `onboarding@resend.dev`
*to* the email you signed up with. To send to other people, add & verify a
domain under **Domains**.

**SendGrid:** create a free account → **Settings → Sender Authentication →
Single Sender Verification** → verify one email you own (e.g. your Gmail). Then
**Settings → API Keys → Create API Key** with "Mail Send" permission (starts
with `SG....`).

---

## 3. Deploy the Edge Function

The function code is in `supabase/functions/send-data-email/index.ts`.
Choose **A (Dashboard, no tools to install)** or **B (CLI)**.

### Option A — Supabase Dashboard (easiest on Windows)

1. Go to your project → **Edge Functions** → **Deploy a new function**.
2. Name it exactly **`send-data-email`**.
3. Paste the entire contents of
   `supabase/functions/send-data-email/index.ts` and click **Deploy**.

### Option B — Supabase CLI

```bash
supabase login
supabase link --project-ref vcgbfnuopsiraxhgwtgb
supabase functions deploy send-data-email
```

---

## 4. Set the server secrets

Set these in **Dashboard → Edge Functions → send-data-email → Secrets**
(or `Project Settings → Edge Functions → Secrets`). `SUPABASE_URL` and
`SUPABASE_ANON_KEY` are already provided automatically — you do **not** add
those.

### If using Resend

| Secret | Value |
|---|---|
| `EMAIL_PROVIDER` | `resend` |
| `RESEND_API_KEY` | your `re_...` key |
| `EMAIL_FROM` | `onboarding@resend.dev` (or `you@yourdomain.com` once verified) |
| `EMAIL_FROM_NAME` | `MEDS` |

### If using SendGrid

| Secret | Value |
|---|---|
| `EMAIL_PROVIDER` | `sendgrid` |
| `SENDGRID_API_KEY` | your `SG....` key |
| `EMAIL_FROM` | the **verified single-sender** email |
| `EMAIL_FROM_NAME` | `MEDS` |

CLI equivalent:

```bash
supabase secrets set EMAIL_PROVIDER=sendgrid SENDGRID_API_KEY=SG.xxxx EMAIL_FROM=you@example.com EMAIL_FROM_NAME=MEDS
```

---

## 5. Test it

1. Rebuild/run the app on your emulator/phone.
2. Open a session → tap the **email icon** → enter an email → **Send email**.
3. You should see "Data sent to …". Check the inbox (and spam folder).

---

## Troubleshooting

- **"Server email is not configured"** → a secret (`RESEND_API_KEY` /
  `SENDGRID_API_KEY`) is missing. Re-check step 4, then redeploy is not needed —
  secrets apply immediately.
- **"…the 'from' address is not verified"** → the `EMAIL_FROM` value isn't
  verified with the provider. Verify the sender (SendGrid) or domain (Resend).
- **Resend: email to others silently only reaches you** → you're still in test
  mode. Verify a domain to email arbitrary recipients.
- **"You are not signed in"** → the user must be logged in; the app sends their
  auth token automatically.
- **Nothing arrives** → check **Dashboard → Edge Functions → send-data-email →
  Logs** for the provider's error text.

---

## How it fits together

```
Flutter app                         Supabase Edge Function        Email provider
-----------                         ----------------------        --------------
DataExportService  ── builds ──▶ PDF + CSV bytes
EmailExportService ── base64 + invoke('send-data-email') ─▶ verify user JWT
                                                            build email + attach
                                                            POST ─────────────▶ Resend/SendGrid ─▶ inbox
```

Files added:
- `lib/services/data_export_service.dart` — builds the PDF + CSV.
- `lib/services/email_export_service.dart` — calls the function.
- `lib/widgets/email_export_sheet.dart` — the "Send to email" UI.
- `supabase/functions/send-data-email/index.ts` — the server that emails it.
