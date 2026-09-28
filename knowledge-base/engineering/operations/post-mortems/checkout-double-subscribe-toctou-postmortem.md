---
title: "POST /api/checkout double-subscribe TOCTOU — latent money-path race, found by review (near-miss)"
date: 2026-09-28
incident_pr: 9115
incident_window: "2026-04-22 → 2026-09-28 (defect latent in production; no confirmed occurrence)"
recovery_at: "2026-09-28 (PR #9115)"
suspected_change: "feat-plan-concurrency-enforcement (#2617) — embedded Checkout route, 2026-04-22"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - latent-defect
  - code-review-detection
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal data exposure; the race risks duplicate charges (money path), not disclosure"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

`POST /api/checkout` performed "already subscribed" + `stripe.checkout.sessions.create`
as two unserialized operations. Two concurrent requests (double-tab, cross-render,
direct API calls) could each pass the check and mint a Checkout Session; completing
both produced two live Stripe subscriptions and duplicate monthly charges on one
customer. The defect lived in production from embedded-checkout ship (2026-04-22)
until PR #9115. No double-subscription was reported or detected — this is a
near-miss post-mortem for a latent money-path race caught by issue triage, not by
monitoring or a customer report.

## Status

resolved — pending merge/deploy of PR #9115 at the time of writing; marker table +
fenced claim close the race server-side.

## Symptom

No observed production symptom. The report (#8918) was a code-level TOCTOU analysis:
client-side pending latches (PR #8904) suppress ordinary double-clicks but cannot
cover cross-tab or direct-API concurrency.

## Incident Timeline

- **Start time (detected):** issue #8918 filed 2026-09-24 (triage of the pending-state parent work)
- **End time (recovered):** PR #9115 merge (pending at writing)
- **Duration (MTTR):** ~4 days issue-to-fix-PR

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-09-24 | Defect analyzed and filed as #8918 during ui-action-feedback decomposition. |
| agent | 2026-09-28 | Implemented claim-table idempotency; review panel found and closed ABA fencing, delete-before-expire, and webhook-lag residuals in the fix itself. |

## Participants and Systems Involved

`POST /api/checkout` route, Stripe Checkout Sessions API, `users` table
(`subscription_status`), Stripe webhook (`checkout.session.completed`/`.expired`),
new `public.pending_checkout_sessions` claim table (migration 144).

## Detection (+ MTTD)

- **How detected:** manual code analysis during issue triage — NOT monitoring and
  NOT a customer report. A self-detection gap: nothing would have surfaced a
  double-subscription except a duplicate-charge complaint.
- **MTTD (mean time to detect):** ~5 months (2026-04-22 → 2026-09-24).

## Triggered by

latent defect — present at feature ship; no deploy triggered it.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Create/check TOCTOU lets concurrent POSTs each mint a session | route code: check-then-act with no serialization; no idempotency-key discipline between requests | none — confirmed by reading the route | confirmed |

## Resolution

PR #9115 adds `pending_checkout_sessions` (PK `user_id`) as the single
serialization point: insert-first claim, 23505 marker-hit path, fenced reclaim on
row identity (`created_at`/`session_id`), fresh-completion tombstone
(`FRESH_COMPLETION_MS` → 409 `checkout_completed`), webhook marker cleanup on
completed + expired, double-completion anomaly probe (two active subs <15min
apart → Sentry), daily 24h pg_cron retention sweep.

## Recovery verification

88/88 touched vitest cases green (claim/reuse/reclaim/fencing/error branches);
migration-shape + verify sentinel tests; CI registry sweep pending at writing.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Concurrent POSTs could each create a Stripe Checkout Session → because the
   "already subscribed" check and `sessions.create` were unserialized.
2. Why unserialized? → because the route had no shared state between the check
   and the create; client-side pending state was the only guard.
3. Why no shared state? → because server-side idempotency was never designed in;
   the in-flight model treated each POST as independent.
4. Why did the design accept that? → because the embedded-checkout flow assumed
   the UI (one Subscribe button per tab) was the concurrency boundary — and the
   API had no client-independent invariant.
5. Why was that assumption load-bearing? → because no review checklist at feature
   ship asked "can a second request interleave inside this money path?"; the
   client latch (#8904) shipped as *the* fix, letting the harder server-side
   work defer to #8918.

## Versions of Components

- **Version(s) that triggered the outage:** embedded-checkout route as shipped in #2617 (2026-04-22).
- **Version(s) that restored the service:** PR #9115 (migration 144 + route/webhook changes).

## Impact details

### Services Impacted

`POST /api/checkout` (money path); Stripe subscriptions; webhook users-row updates
(second `checkout.session.completed` would overwrite `stripe_subscription_id`).

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none observed — potential duplicate monthly charges had the race fired; no report received.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer (Soleur-as-tenant-zero): same latent exposure; no double subscription detected.
- OAuth installation owner: none.

### Revenue Impact

Potential duplicate monthly charges per affected user (unrealized — near-miss).
Had it fired: ops time for manual refund/cancel via the anomaly alert.

### Team Impact

Design review burden — the fix itself needed three hardening rounds (fencing,
expire ordering, webhook-lag tombstone, legal-doc lockstep), all caught by the
review panel before merge.

## Lessons Learned

### Where we got lucky

No customer hit the race in ~5 months of exposure — plausible because embedded
checkout had few concurrency-entry paths and short session TTLs; the bug was
found by decomposing the client-latch PR, not by a charge complaint.

### What went well

- Client-side deferral PR (#8904) explicitly scoped out the server-side fix and
  filed it (#8918) rather than claiming the race closed — the deferral made the
  residual visible.
- The review panel caught defects *in the fix* (ABA on unfenced mutations,
  delete-before-expire, >1-active-sub anomaly false-positive, missing
  `checkout.session.expired` cleanup, missing legal lockstep) before any of them
  shipped — multi-lens review earned its cost on a money path.
- Postmortem written pre-merge (gate-forced), while the analysis was still fresh.

### What went wrong

- Embedded checkout shipped with a money-path check-then-act; the "one UI
  button" assumption substituted for an API invariant.
- Nothing would have detected an actual double-subscribe before a billing
  complaint — self-detection gap, partially closed by the anomaly probe but only
  going forward.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #9135 | Enable `checkout.session.expired` on the Stripe webhook endpoint so the new marker-cleanup arm fires (credential-wall deferred). | open |
| #9126 | `email-triage-row` suite-load flake observed during this run (pre-existing, unrelated — tracked so it isn't re-diagnosed). | open |
