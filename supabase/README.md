# PinWise backend (Supabase)

Hosted AI proxy + per-user usage quota for the PinWise iOS app. The app never holds a provider API
key — it calls the `ai-chat` Edge Function with a Supabase JWT; the function enforces the quota,
injects the safety guardrails server-side, and streams the model response back.

## One-time setup (Phase 0)

```bash
# From the repo root, with the Supabase CLI installed (brew install supabase/tap/supabase):
supabase init                 # if not already initialized (generates config.toml)
supabase link --project-ref <your-project-ref>

# Apply the schema:
supabase db push              # runs migrations/0001_ai_backend.sql

# In the Supabase dashboard → Authentication → Providers:
#   • enable Apple  (Services ID + key, so signInWithIdToken works)
#   • enable Anonymous sign-ins  (guests get a small quota)

# Edge Function secrets (NEVER commit these):
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase secrets set AI_PROVIDER=anthropic
# optional overrides:
supabase secrets set AI_MODEL=claude-haiku-4-5   # default pick; use claude-sonnet-4-6 for the stronger runner-up
supabase secrets set FREE_DAILY_LIMIT=15
supabase secrets set PRO_DAILY_LIMIT=500

# Deploy:
supabase functions deploy ai-chat
```

Then put the project URL + anon (publishable) key into the iOS app — see `AppConfig.swift`
(`supabaseURL`, `supabaseAnonKey`). The anon key is safe to ship; RLS protects the data.

## Local test

```bash
supabase start
supabase functions serve ai-chat --env-file ./supabase/.env.local   # ANTHROPIC_API_KEY etc.

# Get a JWT for a test user (dashboard → Auth, or the CLI), then:
curl -N -X POST http://localhost:54321/functions/v1/ai-chat \
  -H "Authorization: Bearer <jwt>" -H "content-type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is BPC-157?"}],"context":""}'
# Expect: a stream of `data: {"type":"delta",...}` frames ending in `data: {"type":"done"}`.
# Exceed FREE_DAILY_LIMIT messages in a day → HTTP 429 {"error":"limit_reached",...}.
```

## Layout

- `migrations/0001_ai_backend.sql` — `profiles` (tier) + `ai_usage` (daily quota) + RLS + auto-profile trigger + `increment_ai_usage`.
- `functions/ai-chat/index.ts` — auth, quota, guardrails, SSE streaming, usage tally.
- `functions/ai-chat/providers/` — provider-agnostic adapter; `anthropic.ts` is the default. Add a
  sibling adapter + a `case` in `index.ts`'s `provider()` to swap models.

## Security invariants

- `profiles.tier` and `ai_usage` are **never** client-writable (RLS has no write policy); the
  service-role Edge Function is the only writer. Clients can't fake quota or grant themselves `pro`.
- The provider key lives only in Edge Function secrets. Grep the built iOS app to confirm it's absent.
- Guardrails are injected in `index.ts`, not the app — they can't be stripped by a modified client.
