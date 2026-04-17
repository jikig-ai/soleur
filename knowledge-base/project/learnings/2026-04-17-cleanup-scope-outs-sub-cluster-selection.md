---
date: 2026-04-17
category: workflow
module: cleanup-scope-outs
tags: [scope-outs, refactor-batching, skill-improvement]
---

# Learning: cleanup-scope-outs sub-cluster selection on large areas

## Problem

First dogfood run of `/soleur:cleanup-scope-outs` (shipped in PR #2492) against
the live Phase-3 backlog. `group-by-area.sh` returned `apps/web-platform` as the
top cluster with **9 open scope-outs**. The skill's documented behavior is to
pick the top cluster and delegate the whole thing to `/soleur:one-shot` — 9
issues was too many and too heterogeneous to fold into a single focused PR:

- #2478 billing MTD aggregate
- #2474 kb upload route extraction
- #2462 PII scrubbing (contested-design — already scoped out for design reasons)
- #2461 shared log-sanitize helper
- #2460 startPruneInterval helper
- #2459 extractClientIp JSDoc
- #2389 SelectionToolbar perf (from PR #2347)
- #2388 ChatSurface/KbChatContext architecture (from PR #2347)
- #2387 simplicity — Sheet YAGNI (from PR #2347)

These span five unrelated subsystems. A single PR touching all 9 would have
had the blast-radius profile the scope-out process was designed to avoid.

## Solution

Operator sub-selected the coherent triple **#2459 + #2460 + #2461** — all three
filed from the same review (PR #2445 analytics-track hardening, ref #2383) and
all touching `apps/web-platform/server/rate-limiter.ts` + sibling `lib/`
helpers. Delegated that subset to `/soleur:one-shot`, landed as PR #2499 in a
single clean refactor that closed all three.

**Excluded from the batch on purpose:**

- #2462 (PII scrubbing) — contested-design. Needs product/ops discussion first.
- #2474, #2478 — different subsystems (kb upload, billing).
- #2387/#2388/#2389 — from a different PR's review, different subsystem (chat
  components). Natural second batch.

## Key Insight

`group-by-area.sh` at two-segment depth is correct for small-to-medium backlogs
(the skill's `shorthand-refs.json` + `mixed-depth.json` regression tests
confirm this at ≤6 issues per top area). It breaks down when a top area has
≥7 issues from ≥3 unrelated PRs, because the skill's "pick top cluster,
delegate whole thing" flow hits operator judgment overhead.

**The winning sub-cluster selection heuristic:** group by originating PR
review (same "Ref #NNNN" in bodies). This catches the natural coherence that
second-level-directory grouping misses — three scope-outs from the same review
are almost always tight siblings regardless of which subdirectory each path
happens to live under.

## Prevention

**Routed to skill:** add a sharp edge to `cleanup-scope-outs/SKILL.md` noting
the ≥7-issue threshold and the originating-PR sub-cluster heuristic. Future
runs either (a) auto-sub-cluster by originating PR, or (b) present the grouped
sub-clusters so the operator can pick without re-reading bodies.

## Cross-references

- Skill: `plugins/soleur/skills/cleanup-scope-outs/SKILL.md`
- Reference PR: #2486 (original batched-cleanup pattern — 3 issues, tight)
- This PR: #2499 (first skill-driven batched-cleanup — also 3 issues, tight)
- Related learning: `2026-04-15-negative-space-tests-must-follow-extracted-logic.md`
  (applied during T2b migration in this PR)

## Session Errors

None detected. The pipeline (plan → deepen → work → review → ship) ran cleanly
with no tool failures, path confusion, or branch issues.
