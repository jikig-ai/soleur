---
title: Instrument the waitlist→activation funnel
date: 2026-06-08
topic: waitlist-activation-funnel
issue: 5049
branch: feat-funnel-instrumentation
lane: cross-domain
brand_survival_threshold: single-user incident
related:
  - knowledge-base/project/brainstorms/2026-04-10-product-analytics-instrumentation-brainstorm.md
  - knowledge-base/project/brainstorms/2026-04-17-analytics-track-path-pii-brainstorm.md
  - knowledge-base/project/brainstorms/2026-03-23-analytics-comparison-brainstorm.md
  - knowledge-base/product/business-validation.md
---

# Brainstorm: Instrument the waitlist→activation funnel

## What We're Building

A funnel/adoption-measurement capability so the business can answer the gap
`business-validation.md` (re-validated 2026-06-08, PR #5047) names as #1:
*"zero recorded external active users; no signup / activation numbers captured."*
The verdict is PIVOT → "platform shipped; now measure adoption," and the success
metric is **"10 founders using 2+ domains for 2+ weeks."**

The brainstorm's central finding is a **scope reframe**: most of the bottom of
the funnel is *already built*. Issue #1063 (CLOSED) shipped an admin analytics
dashboard at `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/page.tsx`
whose `lib/analytics.ts::computeMetrics` already derives, per user, from the
`users` + `conversations` Supabase tables: `domainCount`, `totalSessions`,
`ttfvDays`, `errorRate`, `churning`, `daysSinceLastSession`. That is the
cohort/retention substrate. So the work is **not** the issue's proposed 6-stage
Plausible-goals funnel — it is:

1. **Extend `computeMetrics` + the admin dashboard** to render an *activation
   funnel view* (stage counts + drop-off + conversion) from existing Supabase
   columns, adding reads of `workspace_status` and (as secondary diagnostics
   only) `onboarding_completed_at`.
2. **Count top-of-funnel waitlist signups** via the **Buttondown API** (queryable,
   authoritative) and render it next to Supabase signups for an *aggregate*
   waitlist→signup conversion number.

No per-user waitlist↔auth join, no new PII store, no new Plausible props, no
events table / PostHog.

## Why This Approach

- **The activation/retention substrate already exists and is queryable.** #1063
  deliberately chose "query existing Supabase data" over an events table /
  PostHog. Re-litigating that with a parallel Plausible-goals funnel would create
  a second, weaker source of truth (no per-user cohorting, no retention) for data
  we already own. All three domain leaders agreed.
- **Plausible can't serve the read anyway.** Soleur's Plausible account is on the
  Growth plan ($9/mo) with **no Stats API access** (HTTP 402; needs Business
  $19/mo) — `2026-03-30-plausible-http-402-graceful-skip.md`. A goal-based funnel
  would be eyeball-only in the Plausible UI, conflicting with
  `hr-no-dashboard-eyeball-pull-data-yourself`. The Buttondown API, by contrast,
  is queryable.
- **The server-emission problem dissolves.** Stages 2–6 are all server-timestamped
  (`users.created_at`, `workspace_status` transitions in `server/workspace.ts`,
  invitation `accepted_at`, `conversations.created_at`) and already queryable, so
  no server-side `track()` emit is needed. Plausible would only ever have served
  stage 1, and even there the Buttondown API is the better aggregate source.
- **Aggregate-only keeps us inside the existing legal posture.** Counting
  aggregates (Buttondown total vs Supabase signup count) involves no new PII store
  and stays inside the #1063 "internal operational data" ruling. A true per-user
  join would cross a hard GDPR threshold (see Legal).
- **YAGNI at ~10 users.** Behavior already proves activation; flags and event
  pipelines add cost without answering the PIVOT question any better.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Extend Supabase `computeMetrics` + admin dashboard; reject the parallel 6-goal Plausible funnel | Substrate already shipped (#1063); avoids a second weaker source of truth |
| 2 | Waitlist count via **Buttondown API**, rendered on the admin dashboard | Queryable/automatable (Plausible Stats API is 402-blocked); aggregate-only; no new PII |
| 3 | **Aggregate-only** waitlist→signup attribution; **no** per-user join | Per-user join crosses a hard GDPR threshold and isn't worth it at n≈10 |
| 4 | **Activation = behavior**: `domainCount ≥ 2` AND active span ≥ 14 days (first→last session) | Maps directly to the success metric; uses fields `computeMetrics` already produces |
| 5 | Server-derived timestamps only; replace stage-6 client `onboarding_completed_at` with server-derived "first non-failed conversation"; keep `onboarding_completed_at`/`workspace_status` as *secondary drop-off diagnostics* | Avoids depending on a fire-and-forget client write (decision #5 / timestamp fidelity) |
| 6 | **No new Plausible props**; keep `ALLOWED_PROP_KEYS = ['path']` | Adding a prop key triggers the #2462 mandatory security review for zero gain |
| 7 | Funnel view is admin-only, behind the existing `ADMIN_USER_IDS` gate | No user-facing analytics in this iteration (consistent with #1063 decision 5) |
| 8 | Visual design | Wireframe: `knowledge-base/product/design/analytics/activation-funnel.pen` (screenshot: `knowledge-base/product/design/analytics/screenshots/01-activation-funnel-admin-analytics.png`). Matches existing `analytics-dashboard.tsx` tokens; activation stage highlighted as the success-metric card. |

## Open Questions

1. **Buttondown account selection.** Multiple Buttondown accounts exist (personal
   `deruelle` vs business `soleur`/`ops@`); the API key is the source of truth —
   verify the correct newsletter via `GET /v1/newsletters` before wiring the count
   (`2026-04-07-buttondown-onboarding-multi-account-playwright.md`). Resolve at plan time.
2. **Buttondown count granularity.** Total subscribers vs. tag-filtered
   (`pricing-waitlist`) count — the funnel wants the `pricing-waitlist`-tagged
   number. Confirm the Buttondown API exposes tag filtering at plan time.
3. **Reconciliation timing.** Waitlist count (Buttondown) and signup count
   (Supabase) are pulled from separate systems; render both with their fetch
   timestamps to avoid the divergence trap
   (`2026-03-12-competitive-analysis-cascade-data-reconciliation.md`).
4. **Active-span definition edge.** "≥14 days" = span between first and last
   non-failed session, or 14 days elapsed since signup with activity in the
   window? Pick the one that matches how the success metric will be reported.

## User-Brand Impact

- **Artifact:** the admin funnel dashboard + the Buttondown count read.
- **Vector:** (a) PII leak if any per-user identifier or email reaches Plausible /
  logs; (b) trust/purpose-limitation breach if waitlist emails are joined to
  product behavior without a lawful basis; (c) bad-data risk — a silent failure
  makes the PIVOT decision on phantom numbers.
- **Threshold:** `single-user incident`. Mitigations baked into the decisions:
  aggregate-only (no new PII store, no join), no new Plausible props (scrubber +
  allowlist intact), server-derived counts, and any silent fallback must mirror to
  Sentry (`cq-silent-fallback-must-mirror-to-sentry`).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Highest-leverage product work right now (blocks every roadmap
decision). Scope as extend-Supabase + aggregate waitlist counter; reject the
6-goal Plausible path as a redundant weaker source of truth. Aggregate attribution
is sufficient for the PIVOT decision at n≈10 — a per-user join's value isn't worth
the GDPR cost. Activation = behavior (`domainCount ≥ 2`, ≥14-day span);
`onboarding_completed_at` only as a secondary drop-off diagnostic.

### Engineering (CTO)

**Summary:** Server-side `track()` emission is unnecessary — stages 2–6 are all
server-timestamped and queryable, so decision #1 dissolves. Plausible's value
collapses to stage 1, and even there server emits would degrade unique-visitor
accuracy. Net-new work is small: extend `computeMetrics` + one aggregate waitlist
source; keep the waitlist write (if any) additive/idempotent so it can't break
Buttondown's dedup/double-opt-in. Replace client `onboarding_completed_at` with a
server-derived "first non-failed conversation" timestamp. No capability gaps.

### Legal (CLO)

**Summary:** A per-user waitlist↔auth join (Option B) crosses a hard GDPR
threshold on three grounds — purpose limitation (Art. 5(1)(b); email collected for
newsletter, not product attribution), lawful basis / profiling (Art. 4(4),
possible Art. 35 DPIA), and transparency (Arts. 13/14 + Art. 30 register;
first-PII work touched six legal docs). Aggregate-only (Option A) stays inside the
#1063 "internal operational data" ruling; a cookie-free, prop-free posture is
fine. Recommend Option A. A future per-user join is a separate consent-redesign
initiative (collect product-attribution consent at waitlist capture), not an
extension of #5049. Output is draft pending professional legal review.

## Productize Checkpoint

No new productize candidate. A weekly funnel snapshot is already covered by the
existing `server/inngest/functions/cron-weekly-analytics.ts` cadence; this work
extends a standing dashboard rather than introducing recurring task output that
needs a reusable skill.
