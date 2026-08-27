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

<!-- ADDENDUM-2026-08-26 START -->

## Addendum — 2026-08-26: the endpoint used above is being retired

**This is an annotation, not a correction.** Everything above is a true record of what was
run on 2026-06-29 and what it returned. The verdict, reasoning, coverage branch and Art. 30
record are unchanged and are not reopened by this note.

**What changed.** `GET /v1/projects/{ref}/analytics/endpoints/logs.all` — the endpoint named
in Step 2 and used for Steps 2 and 3 — is deprecated, with vendor-announced removal on
**2026-09-23**. The replacement is the unified
`GET /v1/projects/{ref}/analytics/endpoints/logs`, which exposes one stream with a `source`
column instead of one endpoint per log table.

**The dialect changed too.** The replacement takes **ClickHouse** SQL, not BigQuery. A query
copied forward unchanged returns HTTP 200 with `result: null` and a `Backend error!` string —
which reads as an empty result to any caller checking status and row count. The working form
is a filter on the `source` column:

```sql
select count(*) as c from logs where source = 'postgres_logs'
```

**Both timestamp bounds are mandatory on the replacement.** `iso_timestamp_start` **and**
`iso_timestamp_end` must be sent on every request. Omitting them returns a deterministic
HTTP 200 `Backend error!` — reproduced minutes apart, so it is not the transient variant.
This is worth stating flatly because **the endpoint's own OpenAPI description promises the
opposite**: it says that if both are omitted, only the last minute of logs is queried. The
deprecated endpoint honours that sentence; the replacement does not. An agent copying the SQL
above without the bounds will hit the error and misread it as a dialect problem.

**Do not hand-write this query.** Use the helper, which sends both bounds, validates the
source against what the project actually emits, and returns a coverage verdict rather than a
bare row count:

```bash
doppler run -p soleur -c prd -- \
  scripts/supabase-logs-query.sh --source postgres_logs --since <window>
```

- Tool runbook: `knowledge-base/engineering/operations/runbooks/supabase-log-query.md`
- The procedure this record documents now has a durable home:
  `knowledge-base/engineering/operations/runbooks/breach-access-log-investigation.md`
  (promoted from the `GATE G-ESCALATE` blockquote in the 2026-06-29 lockdown plan; it
  reproduces the five steps above, with Steps 2 and 3 executing the helper).
- Measured behaviour of both endpoints — dialect, the mandatory bounds, the unenforced
  documented 24-hour cap, the non-monotonic window truncation, and the `edge_logs`
  instrumentation gap — is recorded in
  `knowledge-base/project/specs/feat-one-shot-supabase-analytics-logs-endpoint-migration/phase-0-endpoint-evidence.md`.
  Cite that file; do not restate its figures.

**Retention posture.** The "~1–2 days" horizon in Step 2 was the measurement of 2026-06-29.
Re-measured 2026-08-26, the aggregate retained span is materially longer. This does **not**
recover the 2026-06 window and does **not** disturb the INCONCLUSIVE verdict: `edge_logs` —
the source Step 3 rests on — produced **zero rows across the entire 30-day live period**, so
its zero is an instrumentation gap, not evidence of no traffic. A longer retained span over a
source that never emits adds nothing. See the evidence file, §Confirmed from the plan
(finding E).

**Sibling records carrying the same addendum:**

- `knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md`
- `knowledge-base/project/learnings/post-mortems/inngest-prd-rls-disabled-exposure-postmortem.md`

An advisory guard, `scripts/lint-supabase-deprecated-endpoints.sh`, censuses references to the
retired endpoint. It is advisory only — not merge-blocking — so a red result is a finding to
read, never a gate that will stop a merge.

<!-- ADDENDUM-2026-08-26 END -->
