---
title: Waitlist→activation funnel instrumentation
feature: feat-funnel-instrumentation
issue: 5049
date: 2026-06-08
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-06-08-waitlist-activation-funnel-brainstorm.md
wireframe: knowledge-base/product/design/analytics/activation-funnel.pen
---

# Spec: Waitlist→activation funnel instrumentation

## Problem Statement

`business-validation.md` (re-validated 2026-06-08) names the #1 gap: "zero recorded
external active users; no signup/activation numbers captured." Verdict: PIVOT →
"measure adoption." Success metric: **10 founders using 2+ domains for 2+ weeks.**
The activation/retention substrate already exists (admin dashboard #1063 over
`users`+`conversations`), but there is no funnel view and no top-of-funnel waitlist
measurement. This feature surfaces an aggregate funnel so the PIVOT/monetization
decision rests on real numbers.

## Goals

- Render an **activation funnel** (stage counts, drop-off %, conversion) on the
  existing admin analytics dashboard, derived from existing Supabase columns.
- Define and compute **activation** = `domainCount ≥ 2` AND active span ≥ 14 days.
- Show an **aggregate** waitlist→signup conversion using a Buttondown-API waitlist
  count vs. the Supabase signup count.

## Non-Goals

- No parallel 6-goal Plausible funnel (decision: query Supabase, per #1063).
- No per-user waitlist↔auth identity join (crosses a GDPR threshold; aggregate-only).
- No new server-side `track()` emission path (stages 2–6 are server-timestamped & queryable).
- No new Plausible allowlisted prop keys (keep `ALLOWED_PROP_KEYS = ['path']`).
- No events table / PostHog (deferred per #1063; revisit at scale).
- No user-facing analytics (admin-only this iteration).

## Functional Requirements

- **FR1.** Extend `apps/web-platform/lib/analytics.ts::computeMetrics` to derive
  per-stage funnel counts: signed up (`users.created_at`), workspace ready
  (`workspace_status = 'ready'`), first non-failed conversation (server-derived
  from `conversations`), activated (`domainCount ≥ 2` AND active span ≥ 14 days).
  → wireframe activation-funnel.pen.
- **FR2.** Render a funnel section on
  `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/page.tsx` /
  `components/analytics/analytics-dashboard.tsx`, above the existing per-user
  table, matching existing tokens. Highlight the "Activated" stage as the success
  metric. → wireframe activation-funnel.pen.
- **FR3.** _[DEFERRED to #5071 during plan-review 2026-06-08]_ Aggregate
  waitlist→signup conversion via a Buttondown count. Removed from this PR: it does
  not gate the success metric, the `BUTTONDOWN_API_KEY` provider already exists
  (premise correction), and the read carries PII-transit risk. See plan §Deferred.
- **FR4.** Show `onboarding_completed_at` as a secondary drop-off diagnostic, not
  the activation gate.

## Technical Requirements

- **TR1.** Activation timestamps are server-derived; do not depend on the
  client-set `onboarding_completed_at` for the gate.
- **TR2.** Buttondown count read must be non-blocking and fail-soft; any silent
  fallback mirrors to Sentry (`cq-silent-fallback-must-mirror-to-sentry`). Render
  a clear "unavailable" state rather than a wrong number.
- **TR3.** Verify the correct Buttondown newsletter account via `GET /v1/newsletters`
  before wiring the count (multi-account hazard).
- **TR4.** No new PII reaches Plausible/logs; allowlist + scrubber unchanged.
- **TR5.** Funnel view gated by existing `ADMIN_USER_IDS` check (fail-closed).
- **TR6.** Render both counts with their fetch timestamps to avoid cross-system
  reconciliation drift.

## Gates

- `/soleur:gdpr-gate` on the diff/plan (aggregate-only; confirm no per-user join, no
  new PII store, allowlist intact).
- Phase 3.55 wireframe: committed (`activation-funnel.pen`).

## Open Questions (carry to plan)

1. Buttondown account + tag-filter API support for `pricing-waitlist` count.
2. Whether "Signed up" base == aggregate "App signups" count (wireframe assumed equal).
3. Active-span definition edge (span between first/last session vs. elapsed-since-signup).
4. Drop-off % relative to previous stage vs. top-of-funnel.

## Domain Review (carry-forward)

- **CPO:** extend Supabase; aggregate-only; activation = behavior; big YAGNI list.
- **CTO:** server emission dissolves; net-new = funnel extension + Buttondown count;
  keep waitlist write (if any) additive/idempotent; no capability gaps.
- **CLO:** per-user join crosses GDPR threshold (Art. 5(1)(b), 4(4), 35, 30);
  aggregate-only stays inside #1063 ruling. Draft — professional legal review pending.
