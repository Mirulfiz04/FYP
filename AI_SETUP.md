# MEDS — AI (Claude) setup

The AI features (session summaries, insights, admin AI trends and reports) use
**Claude**. The app never holds an API key: it calls the Supabase Edge Function
**`ai-proxy`**, which keeps the key as a server secret and calls Claude
(model `claude-haiku-5-5`, set at the top of the function).

## 1. Get a Claude API key

Create a key at <https://platform.claude.com> → **API Keys** (starts with
`sk-ant-...`). Set a monthly spend limit under **Billing → Limits**: any
signed-in MEDS user can trigger AI requests.

## 2. Deploy the Edge Function

The code is in `supabase/functions/ai-proxy/index.ts`.

**Dashboard:** project → **Edge Functions** → **Deploy a new function** → name
it exactly **`ai-proxy`** → paste the whole file → **Deploy**.

**CLI:**

```bash
supabase login
supabase link --project-ref vcgbfnuopsiraxhgwtgb
supabase functions deploy ai-proxy
```

## 3. Set the secret

```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
```

(or Dashboard → **Edge Functions → Secrets**). `SUPABASE_URL` and
`SUPABASE_ANON_KEY` are provided automatically.

## 4. Check it works

```bash
flutter pub get
flutter analyze
flutter test test/ai_service_test.dart
```

Then sign in, run a session, and open its AI summary. If it fails, the error
from the function is shown in the app; details are under **Edge Functions →
ai-proxy → Logs**.

## Old Gemini key

The app no longer uses Gemini. Revoke any Gemini key that was ever pasted into
`lib/services/ai_config.dart` (Google AI Studio → API keys), since a key that
was in an APK or a commit should be treated as leaked.
