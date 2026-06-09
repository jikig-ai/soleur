---
title: Before instrumenting an analytics funnel, check the substrate exists AND the proposed tool can serve the read-back
date: 2026-06-08
category: workflow-patterns
tags: [brainstorm, analytics, funnel, plausible, supabase, yagni, scope-reframe, prior-art]
severity: medium
resolved: true
issue: 5049
---

# Learning: Funnel-instrumentation brainstorms should reframe on two cheap checks before accepting the stated scope

## Problem

Issue #5049 asked to "instrument the waitlist→activation funnel" and proposed a
concrete 6-stage **Plausible-goals** funnel with five open design decisions
(server-side emission path, identity join, props, Plausible-vs-store, timestamp
fidelity). Taken at face value, the hardest decision (server-side `track()`
emission for stages that fire server-side) would have driven a multi-stage
engineering effort.

## Solution

Two cheap brainstorm-time checks dissolved most of the stated scope:

1. **Does the measurement substrate already exist?** Issue #1063 (CLOSED) had
   already shipped an admin analytics dashboard whose
   `lib/analytics.ts::computeMetrics` derives the per-user cohort/retention metrics
   from the `users` + `conversations` Supabase tables. Stages 2–6 are all
   server-timestamped and already queryable — so the "server-side emission"
   decision **dissolves entirely**: you query Supabase, you don't emit events.

2. **Can the proposed tool serve the read-back?** Soleur's Plausible account is on
   the Growth plan ($9/mo) with **no Stats API** (HTTP 402;
   `2026-03-30-plausible-http-402-graceful-skip.md`). A goal-based funnel would be
   eyeball-only in the Plausible UI, conflicting with
   `hr-no-dashboard-eyeball-pull-data-yourself`. The thing you can actually query
   (Buttondown API, your own Supabase) should be the source of truth.

The CPO+CLO+CTO triad then unanimously rejected a per-user waitlist↔auth join on
GDPR grounds (purpose limitation Art. 5(1)(b), profiling Art. 4(4), possible Art.
35 DPIA) in favor of aggregate-only. Net result: the work shrank from a 6-goal
event pipeline to "extend an existing dashboard's query + read one aggregate count."

## Key Insight

When a brainstorm is framed as "instrument X with tool T," two greps beat
accepting the framing:
- **Substrate check:** does the data already exist server-side and queryable
  (a prior shipped dashboard, existing timestamped columns)? If yes, an event
  pipeline is usually a second, weaker source of truth for data you already own.
- **Read-back check:** can tool T be *queried programmatically* on the current
  plan, or only viewed in its UI? A write-only analytics surface you can't pull
  back fails `hr-no-dashboard-eyeball-pull-data-yourself` and shouldn't be the
  funnel's source of truth.

Both pieces existed as separate learnings; the compounding move is running both
checks at brainstorm time to dissolve an issue's *stated* scope before any plan
is written.

## Session Errors

None detected. Premise probe (PR #5047 merged, business-validation.md present)
confirmed before worktree creation; all four background agents returned cleanly;
artifacts committed and pushed without retry.

## Related

- [#5049](https://github.com/jikig-ai/soleur/issues/5049) — parent issue
- `knowledge-base/project/learnings/2026-04-10-query-existing-data-before-building-analytics-pipelines.md` — substrate-check precedent
- `knowledge-base/project/learnings/2026-03-30-plausible-http-402-graceful-skip.md` — Plausible Growth plan has no Stats API
- `knowledge-base/project/brainstorms/2026-06-08-waitlist-activation-funnel-brainstorm.md` — this brainstorm

## Tags

category: workflow-patterns
module: brainstorm
tags: [brainstorm, analytics, funnel, plausible, supabase, yagni, scope-reframe]
severity: medium
resolved: true
