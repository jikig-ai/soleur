---
title: Net-issue-flow / cost-of-filing discipline must fire at the filing site, not only at /ship
date: 2026-05-29
category: workflow-patterns
tags: [backlog, deferred-scope-out, net-issue-flow, cost-of-filing, ship, work, follow-ups]
related_prs: [4452, 4580, 4613]
---

# Learning: net-flow gate belongs at the filing site (/work), not only at /ship Phase 5.5

## Problem

PR #4580 (#4579) filed **4** follow-up issues for **1** closed issue (net +3 backlog
growth): an ADR, a sibling-upstream PR-G tracker, a drill-down-UI feature, and a
discovered latent bug. This is the exact backlog-accretion pattern PR #4452 fixed earlier
the same week via (a) the mechanical cost-of-filing auto-flip (≤30 lines AND ≤2 files → fix
inline) and (b) `/ship` Phase 5.5 **Net-Issue-Flow Surfacing** (display Closing/Filing/Net
before merge so the operator can pivot).

Both safety nets missed, for two structural reasons:

1. **The filings happened in `/work` Phase 4** (Post-Merge Section Self-Audit + deferral
   tracking), which is BEFORE `/ship` Phase 5.5 runs. The surfacing is a ship-time advisory;
   it cannot catch filings made during `/work`.
2. **`/ship` was hand-rolled.** The agent executed ship's phases as targeted bash instead of
   invoking `/soleur:ship`, so Phase 5.5's Net-Issue-Flow Surfacing never executed at all.

The mechanical auto-flip would not have flipped any of the 4 to inline (none were ≤30-line
review findings), but the **surfacing** would have made the agent confront "+3 from one PR"
and consolidate — which is exactly what happened once the operator asked. 3 of the 4
(ADR + PR-G upstream + drill-down) consolidated into a single tracker (#4613); the net
should have been +1 (one consolidated feature tracker + the one genuine discovered bug).

## Solution

Add a **Follow-up Filing Net-Flow Gate** to `/work` Phase 4 (the site where follow-ups are
actually filed), mirroring `/ship` Phase 5.5 + `review/SKILL.md` §CONCUR:

1. Cost-of-filing per candidate (≤30 lines AND ≤2 files → inline).
2. Consolidate deferred-FEATURE follow-ups from the same PR into ONE `post-MVP follow-ups`
   tracker; keep discovered **bugs** separate (never bury a possible-P1 bug in a tracker).
3. Surface `Closing / Filing / Net` BEFORE filing; if Net > 0, justify each filing.

This is the `/work`-side mirror so the discipline fires at the filing site regardless of
whether `/ship` runs or is hand-rolled.

## Key Insight

A gate that only fires at the *merge boundary* (ship) is bypassed by (a) work done before
the boundary and (b) hand-rolling the boundary. When a discipline must hold for an action
(filing a follow-up), enforce it **at the moment the action is taken**, in every skill that
takes it — not only at the last pipeline stage. The mirror pattern already exists in this
repo (SENSITIVE_PATH_RE triple-SSOT across plan/work/ship; the operator-step gate at both
/work Phase 4 and /ship Phase 5.5) — net-flow surfacing was the one that lived in only one
place.

**Corollary on consolidation:** N deferred-feature follow-ups from one PR → one tracker with
a checklist. A genuine discovered defect (different subsystem, possibly P1) is NOT a
deferred scope-out — it keeps its own issue so triage/priority stays visible.

## Tags
category: workflow-patterns
module: skills/work
