# GATE G-ESCALATE — actual-access investigation (Phase 0, blocking)

**Project:** soleur-inngest-prd (`pigsfuxruiopinouvjwy`, eu-west-1)
**Finding:** `rls_disabled_in_public` (14 tables), advisor-dated 2026-06-22
**Investigated:** 2026-06-29 (read-only, via Supabase Management API; PAT from Doppler `soleur/prd_terraform`)
**Exposure window anchor:** project `created_at` = **2026-06-17T13:03:22Z** → remediation 2026-06-29 (~12 days)

## Verdict: INCONCLUSIVE (no positive access evidence; full-window log coverage not available) — NOT a hard STOP

Per the task escalation rule, the hard STOP → CLO / GDPR Art. 33 72h clock fires only on **evidence of
actual unauthorized access**. No such evidence was found. Edge-log retention is shorter than the exposure
window, so a "zero hits" cannot be certified across the full window → verdict is **INCONCLUSIVE, not clean**.
The residual-window determination is routed to the CLO (Art. 30 record below). Remediation proceeds in parallel.

## Step 1 — Key-exposure check (anon AND service_role) — CLEAN

| Check | Result |
|---|---|
| Project ref `pigsfuxruiopinouvjwy` in client-reachable code (`app/`,`components/`,`public/`,`.env.example`,`NEXT_PUBLIC`) | **none** — only in infra/ops/docs (`inngest.tf`, `variables.tf`, `scheduled-inngest-health.yml`, runbook, expenses, a plan) |
| Inngest **anon** key value in current tree | **0 hits** |
| Inngest **service_role** key value in current tree | **0 hits** |
| Inngest anon key in full git history (pickaxe `-S`) | **0 commits** |
| Inngest service_role key in full git history | **0 commits** |
| Client-shipped `NEXT_PUBLIC_SUPABASE_URL`/`ANON_KEY` point at / equal the inngest project | **no** (they point at the web-platform project) |
| Server `SUPABASE_SERVICE_ROLE_KEY` equals inngest service_role | **no** |
| `INNGEST_POSTGRES_URI` points at inngest ref | yes — expected (server-side session-pooler connection, role `postgres`) |

**Conclusion:** the inngest project's anon publishable key and service_role key were **never published in a
client bundle and never committed**. The realistic exploitation vector (anon key + project URL) requires a key
the public never had; it lives only in the dashboard/Doppler. service_role (which bypasses RLS entirely) is
likewise unexposed → no rotation required, though rotation remains available as defense-in-depth.

## Step 2 — Log-retention horizon

- Log endpoint (`/analytics/endpoints/logs.all`) confirmed **functional**: `postgres_logs` returns recent rows
  (e.g. `relation "realtime.subscription" does not exist` at ~2026-06-28).
- **Retained window ≈ last 1–2 days** — far shorter than the ~12-day exposure window. The 2026-06-17 → ~2026-06-27
  slice is **NOT covered** by retained logs. Per the gate, a partial-window "zero hits" is absence-of-evidence,
  not evidence-of-absence.

## Step 3 — Access-log analysis (anon REST + GraphQL)

- `edge_logs` (every HTTP request to PostgREST/`/rest/v1/*` + pg_graphql `/graphql/v1`): **0 rows** over the full
  query window AND over the last 24h (raw, unaggregated). The anon HTTP surface shows **zero traffic** in the
  retained window — consistent with the surface being dormant (Inngest uses the session pooler, not REST).
- `auth_logs`: **0 rows**.

## Step 4 — Coverage branch

- Positive evidence of unauthorized anon/service_role access → **none**. (→ no hard STOP, no Art. 33 clock started.)
- Full-window clean → **cannot certify** (retention < window).
- **Logs do NOT cover the full window → verdict INCONCLUSIVE.** Covered window: ~last 1–2 days (clean, zero anon
  HTTP). Uncovered: 2026-06-17 → ~2026-06-27. Residual-window decision routed to CLO (Art. 30 note below).

## Step 5 — Key rotation

Not required: neither the anon nor service_role key was exposed. Lockdown (RLS + grant revoke) is the remediation;
rotation is held in reserve as optional defense-in-depth.

## Art. 30 record (reachability-only, remediated; coverage-limited)

A misconfiguration (`rls_disabled_in_public` + anon/authenticated DML grants) made tables that **can embed personal
data** (event payloads, step I/O, `account_id`/`workspace_id`) **reachable in principle** by anyone holding the
inngest anon key. **No evidence of actual unauthorized access** was found; the anon/service_role keys were never
published or committed, and the retained edge logs show zero anon HTTP traffic. **Access-log coverage is limited to
~the last 1–2 days** (Supabase tier retention) and therefore cannot certify the full 2026-06-17 → 2026-06-29 window
clean. Remediated 2026-06-29 by enabling RLS (no policies) + revoking anon/authenticated grants + revoking the
recurrence-causing default privileges. CLO to confirm whether the inconclusive residual window, given the
never-published key, warrants any further notification action or is a "reachability-only, remediated, no notifiable
breach" record.
