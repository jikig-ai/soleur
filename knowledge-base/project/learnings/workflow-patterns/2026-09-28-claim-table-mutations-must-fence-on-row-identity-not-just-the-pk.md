---
title: Claim-table rows are locks AND state — every mutation must fence on row identity (created_at/session_id), and external mutations must precede claim release
date: 2026-09-28
feature: feat-one-shot-8918-checkout-idempotency
pr: 9115
tags: [concurrency, postgres, stripe, aba, migrations, review]
---

# Claim-table fencing: the PK serializes acquisition, not mutation

## Problem

#8918 added a `pending_checkout_sessions` marker table to serialize
`POST /api/checkout` (insert-first dedup on a `user_id` PK, 23505 routes the
loser into a marker-hit state machine — mirroring migration 030's
`processed_stripe_events`). First draft predicated marker writes on
`.eq("user_id", ...)` alone. Review (architecture + simplicity + semgrep,
independent lenses) found that this reopens the race the table exists to
close:

- A stale reclaim decision can `DELETE` a faster sibling's *fresh* claim
  mid-`sessions.create` (ABA window), freeing the slot for a second session.
- The winner's post-create `UPDATE SET session_id` can stamp its id onto a
  *successor's* marker (a new claim inserted after the stale decision).
- A request created-but-unrecorded session path can return a live,
  unrecorded session to the client.

## Solution

Two rules, applied to `apps/web-platform/app/api/checkout/route.ts`:

1. **Every marker mutation predicates on the row's identity at decision
   time**, never `user_id` alone:
   - own-claim update and release deletes fence on `user_id + created_at`
     (the fencing token returned by the claim's `RETURNING created_at`);
   - terminal/wrong-tier reclaim fences on `user_id + session_id`;
   - stale-null reclaim fences on `user_id + session_id IS NULL +
     created_at`.
   A 0-row fenced mutation is *evidence a sibling won* — `continue` the
   claim loop, never proceed to a second create. `timestamptz` round-trips
   byte-exact through PostgREST ISO-8601 serialization (µs precision),
   verified, so the fence is value-exact.

2. **External mutations precede claim release**: on different-tier reclaim,
   `sessions.expire` runs BEFORE the fenced marker `DELETE`. A failed expire
   then leaves the marker intact so the next attempt re-retrieves and
   reclaims; deleting first orphans a completable session while freeing the
   slot. The dual is also true: a request that created a session but was
   fenced out of recording it must expire that session before 409 — every
   created-but-unrecorded session is expired.

Related secondary findings folded in the same PR: stripe-node's default
timeout is ~80s (×3 with retries) so a stale-claim TTL must exceed it
(`STALE_NULL_MARKER_MS = 90_000`); a `complete` Stripe session younger than
`FRESH_COMPLETION_MS` (15min) is a just-paid customer inside the webhook-lag
window — reclaiming mints a sequential double-charge, so fresh completions
return `409 checkout_completed`; `client_secret` reuse re-verifies
`metadata.supabase_user_id` before handing back a bearer capability; and the
double-completion anomaly must compare *creation-time proximity* (two
active subs <15min apart), not `>1` count (legit paid→paid upgrades leave
the prior sub active).

## Key Insight

An insert-first dedup table closes the *acquisition* race; it does nothing
for the *decision* race. Any delete/update that follows a "should I reclaim
this?" check must re-verify the same observation inside the mutation
predicate — compare-and-delete, not check-then-act. And whenever a local
claim row tracks an external resource, the ordering is: mutate the external
system, then release the local claim. Releasing first turns a transient
external failure into a durable orphaned resource plus a freed slot — the
worst of both states.

## Session Errors

- Structural-enumeration + data-integrity-guardian subagents died on
  `[Error] Tool was rejected` (background `subagent_general` auto-denies
  unapproved tools). **Prevention:** respawn with an explicit read-only
  tool instruction set; treat the first rejection as fatal for that run.
- Idempotency RED failed on unset `STRIPE_PRICE_ID_*` env vars, not on the
  missing code. **Prevention:** tier-price fixtures must stub all four
  price env vars up front (mirror `api-checkout-tiers.test.ts` setup).
- Plan's file list missed the legal-doc lockstep gate: editing
  `server/dsar-export-allowlist.ts` triggers `enforce`, which requires
  `privacy-policy.md` + `gdpr-policy.md` + `data-protection-disclosure.md`
  + `compliance-posture.md` + `LEGAL_DOC_SHAS` repins + Eleventy mirrors in
  the SAME diff. Found by git-history review, not planning. **Prevention:**
  any plan touching the DSAR allowlist enumerates all four docs in
  Files-to-Edit; grep `pr-quality-guards.yml` for the `surface_patterns`
  list when a regulated file is in the diff.
- Ownership check initially wrapped the whole same-tier branch, breaking
  the open-but-null-client_secret 409 path (test caught it). **Prevention:**
  scope bearer-capability checks to the code path that returns the
  capability.
- QA scenario expected `401` from `/api/checkout`; prod middleware answers
  `307 → /login` upstream of the route. **Prevention:** API-verify
  scenarios should assert the invariant ("unauthenticated POST cannot
  reach the handler") not one layer's literal status code.
- Migration `143` was claimed by a sibling worktree invisible to open-PR
  probes → renumbered to 144 (2026-05-30 collision learning, honored).
- Local `test-all.sh --affected` pre-commit ran 10+ minutes on barely-
  intersecting registry suites → killed and committed with `LEFTHOOK=0`
  after the user ruled CI owns the sweep; directly-touched vitest files +
  typecheck + semgrep were still run locally as the honest signal.
  **Prevention:** the operator's guidance stands — run touched tests
  locally, let CI own the affected-set registry (mirrored there by design).
- `email-triage-row` suite-load flake, unrelated to diff — filed #9126.
