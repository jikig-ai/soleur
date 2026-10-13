---
title: "Convert scheduled-gdpr-gate-preflight-eval-50d to Inngest one-shot"
date: 2026-05-25
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
parent_issue: 3948
tracking_issue: 3948
tags: [tr9, inngest, gdpr-gate, one-shot, compliance]
---

# Convert gdpr-gate 50-day eval to Inngest one-shot

## What We're Building

Convert `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml` from a GHA cron-with-self-neutralization workflow to an Inngest event-triggered one-shot function. This is the final child of TR9 umbrella #3948 — and the only one classified as "CONVERT to inngest.send-triggered one-shot" (all 10 other children were recurring cron-to-cron ports).

The eval fires ONCE on 2026-06-29 09:00 UTC, counts escaped gdpr-gate Critical findings over the 50-day post-#3501 window, and posts a structured recommendation comment on issue #3516 (wire Check 10 / defer to 90-day checkpoint / skip).

## User-Brand Impact

**Threshold:** single-user incident. Operator endorsed all three failure modes:

1. **Missed eval → compliance gate decision made blind.** Sender mechanism breaks; operator doesn't learn until manually checking #3516 weeks later. Preflight Check 10 wire/skip call proceeds without empirical data.
2. **Cross-tenant data exposure via wrong eval target.** Event payload addresses wrong repo or comment-immutability pin missing → eval runs against wrong dataset. Low likelihood with Octokit auth scoping.
3. **Self-rearm loop.** Idempotency breaks; eval posts multiple noisy comments and corrupts the 90-day reschedule chain.

**CLO softening:** No statutory clock (Art. 33 72h does not apply). The 50-day eval is an internal governance milestone, not a regulatory deadline. "Re-arm if missed" is acceptable degradation — but repeated misses erode Art. 5(2) accountability posture. Disclosure on miss: internal-only.

## Why This Approach

### Premise Corrections

1. **"inngest.send-as-trigger pattern doesn't exist"** — FALSE. `agent-on-spawn-requested.ts`, `cfo-on-payment-failed.ts`, `github-on-event.ts`, `workspace-reconcile-on-push.ts` are all event-only triggered. What's novel is *delayed* dispatch via `ts` field.
2. **4th sender option missed:** `inngest.send({ ts: <future-epoch> })` — Inngest's native delayed-event API. SDK type verified: `apps/web-platform/node_modules/inngest/types.d.ts:537` exposes `ts?: number` on `EventPayload`.
3. **Handler is pure-TS** — task spec (comment #4415647777) is 4 deterministic steps (grep incidents.log → `gh pr list` filter → 3-branch decision tree → post comment). No agent reasoning needed. PR #4412 `cron-strategy-review.ts` is the handler template.

### Sender Architecture Options Evaluated

| Option | Brand-survival | TR9 purity | Idempotency | Observability | Cross-year |
|--------|---------------|------------|-------------|---------------|------------|
| (a) GHA curl `inn.gs/e` | LOW | FAIL | LOW | OK | OK (D3) |
| (b) Inngest recurring sender | MED | OK | HIGH RISK | OK | Hard |
| (c) Cloudflare Worker | LOW | FAIL (new infra) | MED | New sink | OK |
| **(d) `inngest.send({ ts })` at merge** | **HIGH** | **PASS** | **HIGH** | Event log + Sentry | Trivial |

**Chosen: Option (d)** — Inngest native `inngest.send({ ts: 1751187600000 })` via a one-shot arming script at merge time.

### Handler Shape

Single file `oneshot-gdpr-gate-50d-eval.ts` mirroring `cron-strategy-review.ts` structure (~300 LOC):
- Registered on `{ event: "oneshot/gdpr-gate-50d-eval.fire" }` only — NO `{ cron }` entry
- D3 date guard: `new Date().toISOString().slice(0,10) === "2026-06-29"` — else abort
- D5 comment-immutability pin: re-fetch comment #4415647777 via Octokit, assert `user.login === "deruelle"` AND `created_at === "2026-05-10T15:27:18Z"` AND `created_at === updated_at`
- `step.run` blocks: mint-installation-token → setup-workspace → eval-check → sentry-heartbeat
- Sentry heartbeat slug: `oneshot-gdpr-gate-50d-eval`

### Sender Shape

One-shot script `scripts/arm-gdpr-gate-50d-eval.ts`:
- Inserts `cron_run_ledger` row keyed `gdpr-gate-eval-50d-2026-06-29` (UNIQUE constraint; exits 1 on dup = no re-arm)
- D5 at send-time: validates comment exists and is unedited BEFORE dispatching event
- Calls `inngest.send({ name: "oneshot/gdpr-gate-50d-eval.fire", id: "gdpr-gate-50d-eval-2026-06-29-v1", ts: 1751187600000, data: { issue: 3516, comment_id: 4415647777, expectedAuthor: "deruelle", expectedCreatedAt: "2026-05-10T15:27:18Z" } })`
- Operator runs once at merge time: `pnpm tsx scripts/arm-gdpr-gate-50d-eval.ts`
- Captures returned event_id → stores in ledger row metadata + echoes to terminal

### Sentry Observability (Two Monitors)

1. **`gdpr-gate-eval-50d-armed`** — arming verification. Confirms event_id was queued. Add to `apply-sentry-infra.yml` -target= allowlist.
2. **`oneshot-gdpr-gate-50d-eval`** — handler scheduled check-in expecting heartbeat at 2026-06-29T10:00Z; alerts if no check-in by 11:00Z. Pages operator on silent dispatch failure.

### D-Layer Defense Mapping (GHA → Inngest)

| GHA Defense | Inngest Equivalent | Placement |
|------------|-------------------|-----------|
| D1 (idempotency precheck) | Inngest event `id` dedupe + `cron_run_ledger` UNIQUE | Send-time + handler |
| D2 (repo/issue state) | Octokit assertions inside handler | Handler |
| D3 (date guard) | `new Date().toISOString().slice(0,10) === "2026-06-29"` | Handler |
| D4 (self-neutralization) | N/A — event consumed once, no cron to remove | Innate |
| D5 (comment-immutability pin) | Re-fetch + assert `created_at === updated_at` | Both |
| Post-fire verification | N/A — no workflow file to verify removal | Innate |

### Sequence

```
  T=merge              T=2026-06-29 09:00Z              T+handler
   │                         │                              │
operator → scripts/arm-..ts
   │  1. INSERT cron_run_ledger (UNIQUE guard)
   │  2. D5 send-time check (comment unedited)
   │  3. inngest.send({ ts, id, name, data })
   │  4. Store event_id in ledger + echo
   │                         │
   │                         ▼
   │                  Inngest dispatcher fires event at ts
   │                         │
   │                         ▼
   │                  oneshot-gdpr-gate-50d-eval handler:
   │                    step 1: D3 date guard
   │                    step 2: D5 comment-immutability pin
   │                    step 3: grep incidents.log + gh pr list
   │                    step 4: 3-branch decision → post comment
   │                    step 5: Sentry heartbeat (ok | error)
   │                         │
   ▼                         ▼
PR #4461                Sentry monitor alerts operator
(event_id               if no check-in by 2026-06-29T10:00Z
 audit trail)
```

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Sender mechanism | `inngest.send({ ts })` via one-shot script | TR9 purity (no GHA cron); native SDK support; operator-invoked once at merge |
| Handler template | PR-6 pure-TS Octokit (no claude-eval spawn) | Task is 4 deterministic steps; no agent reasoning |
| Arming idempotency | `cron_run_ledger` UNIQUE + Inngest event `id` dedupe + D3 handler guard | Triple-layer: DB constraint + event dedupe + calendar assertion |
| D5 placement | Send-time AND handler-time per CLO | Tampered comment between send and fire is caught at handler; binding snapshot at send is evidence trail |
| Sentry monitors | Two: arming + handler scheduled check-in | Belt-and-suspenders; operator learns of BOTH arming failure and dispatch failure |
| TTL verification | Block merge on Inngest tier confirmation for 50d+ `ts` delays | CTO flag: free-tier retention may not cover 50 days. Fallback: GHA cron at T-7d (2026-06-22) calls `inngest.send` with 7-day delay |
| Productize | Defer | N=1 (CPO). Re-evaluate after second deferred-decision eval is filed |
| GHA workflow deletion | Same PR | Per TR9 I-13 hygiene: delete in same commit Inngest function lands |

## Open Questions

1. **[LOAD-BEARING] Inngest `ts` TTL for 50-day delays.** Does our Inngest tier support `ts` delays of ≥60 days? Verify via Inngest support/dashboard before merge. If NOT supported → hybrid fallback: keep a GHA workflow with cron `0 9 22 6 *` (T-7d) whose sole job is `inngest.send({ ts: 2026-06-29T09:00Z })` with a 7-day delay window.
2. **`cron_run_ledger` schema fit.** ADR-033 defines this table for jitter-guard (columns: `function_name`, `last_run_at`, `run_count`). Using it for arming idempotency is a semantic stretch — the arming script needs a `metadata` column to store the returned `event_id`. Options: (a) add `metadata jsonb` column in this PR's migration, (b) use a separate `oneshot_arming_log` table, (c) store `event_id` in PR description only (CTO's simpler approach) and skip DB arming.
3. **`inngest events get <event_id>`** — does this work for future-dated events on our tier? CTO recommended this for armed-state verification post-dispatch. Inngest docs don't document a "list pending events" API; only per-event-id lookup is mentioned.
4. **90-day reschedule chain.** If the 50-day eval finds 0-2 escapes, the handler must re-arm a 90-day checkpoint for 2026-08-10. Does this use the same `inngest.send({ ts })` primitive (recursive arming)? Or file a `/soleur:schedule create --once` (which routes back to GHA)?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Recommends Option (d) with manual `inngest send` CLI at merge-time. Verified `ts?: number` exists in SDK types. Flags 50-day TTL as the single biggest unverified assumption. Handler is ~300 LOC mirroring `cron-strategy-review.ts`. No capability gaps — all substrate primitives (Octokit, Sentry crons, `generateInstallationToken`) already established by PR-2 through PR-10. Estimates effort: hours, not days.

### Legal (CLO)

**Summary:** Wire D1–D5 in the Inngest port; D5 enforced at BOTH send-time AND handler-time. No statutory deadline — the 50-day eval is an internal governance milestone (not Art. 33 72h). Brand-survival framing softens to "brand-discipline." Eval itself is GDPR-quiescent (reads telemetry counts + PR titles, no PII). Disclosure on miss: internal-only. Repeated misses erode Art. 5(2) accountability posture.

### Product (CPO)

**Summary:** Option (d) preserves User-Brand Impact because the operator discovers TR9 substrate via the same `cron-*.ts` glob that 10 prior PRs trained muscle-memory on. Recommends one-shot arming script with `cron_run_ledger` UNIQUE constraint (not boot-time). Sentry should monitor the arming (not just the fire). Productize candidate (`/soleur:schedule --once --inngest`) deferred — N=1 is not a pattern.

## Capability Gaps

None. All substrate primitives exist:
- `inngest` SDK with `ts` support (verified `types.d.ts:537`)
- `cron-strategy-review.ts` as pure-TS Octokit handler template
- `generateInstallationToken` + `createProbeOctokit` for GH App auth (per `hr-github-app-auth-not-pat`)
- Sentry crons + `apply-sentry-infra.yml` allowlist (11 entries; 13 after this PR)
- `cron_run_ledger` table (ADR-033 primitive; schema-fit TBD — see Open Question #2)
