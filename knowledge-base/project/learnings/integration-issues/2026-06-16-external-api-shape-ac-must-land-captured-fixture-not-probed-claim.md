---
category: integration-issues
module: inngest/sentry
date: 2026-06-16
tags: [sentry, external-api, live-probe, review, acceptance-criteria, fixtures]
related:
  - knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md
  - knowledge-base/project/learnings/2026-06-15-id-shape-guard-test-fixture-blast-radius-and-syntactic-sast.md
---

# An external-API-shape AC ticked "live-probed" must land the captured response as a fixture — review must re-probe, not trust the claim

## Problem

PR #5434 added a `sentry-issue-rate` Inngest named-check that computes an issue's
events/day over a window and (optionally) auto-closes the report issue when the
rate drops below a threshold. The plan flagged the Sentry issue-stats schema as
"undocumented/ambiguous → /work MUST live-probe." The implementation shipped:

- endpoint `GET …/issues/{id}/stats/?stat=14d`
- parsed as a top-level array of **daily** `[unixSeconds, count]` buckets
- `computeRatePerDay` summed the last `ceil(window_hours/24)` buckets ÷ days

with a code comment "verified by the live Phase-0 probe" and the plan AC ticked
`[x] /work Phase 2 live-probed … and documented which … returns a sum-able shape`.

Four independent review agents (data-integrity P1, code-quality P2, test-design
Gap, agent-native P3) all flagged the bucket shape/resolution as an unverified
external-API contract — none could find the captured response in the diff. A
review-phase **live re-probe** against `jikigai-eu.sentry.io` showed the claim was
wrong on two axes:

1. `/issues/{id}/stats/?stat=14d` returns **24 HOURLY buckets** (3600s spacing)
   covering ~1 day — NOT 14 daily buckets. So a 72h window summed the last 3
   *hourly* buckets and divided by 3 "days" → ~24× rate understatement →
   spurious PASS → **wrong auto-close** of a still-firing issue.
2. The correct daily source is the **issue-DETAIL** GET `…/issues/{id}/` →
   `.stats["30d"]` (a 31-element DAILY series, 86400s spacing). The `/stats/`
   sub-resource cannot express a multi-day daily rate at all.

A ticked "live-probed" AC and a confident code comment were indistinguishable
from an unverified assumption, because no captured response landed in the diff.

## Solution

Resolved at review time (`hr-no-dashboard-eyeball-pull-data-yourself`): pulled
the real shapes via `doppler … SENTRY_ISSUE_RW_TOKEN` + `curl` and reconciled:

- read daily buckets from `…/issues/{id}/` `.stats["30d"]` (not `/stats/?stat=…`)
- `computeRatePerDay` rounds the window to whole days and shares the integer
  day-count between numerator and denominator (no fractional-day inflation)
- `window_hours` bounded `[24,168]` (was `[1,168]` — sub-day windows can't be
  honoured at daily resolution)
- added a test seeded with the REAL captured `.stats["30d"]` last-7 daily series,
  a dilution-guard test (wide in-bounds window stays FAIL), and the previously
  untested fail-closed branches (missing-id, unexpected shape, close-PATCH-fails).

## Key Insight

When a plan defers an external-API shape to a "/work will live-probe" AC, the
**probe's captured response MUST land in the diff as a test fixture** — a ticked
AC + a "verified by probe" comment is not evidence; it is a claim. The review
gate for any PR whose behavior depends on an external response shape (stats
buckets, webhook payloads, list-vs-object envelopes, hourly-vs-daily resolution)
is: **re-probe the real endpoint and assert the parser matches the captured
bytes** — never trust the implementer's "probed" annotation. Cheapest gate: grep
the diff for a captured-response fixture; if the only "evidence" is prose, the
contract is unverified. Generalizes
[[2026-05-18-supabase-custom-access-token-hook-discriminator]] (probe validated
ONE caller) and the review-catalogue "Plan-time empirical-probe assumptions vs
actual caller surfaces" — here the probe wasn't even faithfully captured.

## Session Errors

1. **Sentry stats endpoint shape shipped wrong, AC ticked "live-probed".**
   `/issues/{id}/stats/?stat=14d` parsed as daily buckets; real shape is 24
   hourly buckets; correct daily source is issue-detail `.stats["30d"]`.
   — Recovery: review-phase live re-probe + endpoint switch + whole-day math +
   real captured fixture + dilution/fail-closed tests (41→63 targeted tests).
   — Prevention: external-API-shape ACs must land the captured response as a
   fixture; review must independently re-probe rather than trust the "probed"
   annotation. Routed to `review` and `plan` skill sharp edges this session.
2. **(one-off)** Benign authoring-time hooks (IaC-routing gate, SSH-discoverability
   false-match) — resolved during authoring; no recurrence vector.
