---
title: "Brainstorm: write-mostly artifact diagnosis blocks premature automation"
date: 2026-05-12
category: workflow-patterns
tags: [brainstorm, tech-debt, ledger, lifecycle, automation, falsifiable-test]
issue: 2723
related_issue: 3650
severity: medium
---

# Learning: Write-mostly artifact diagnosis blocks premature automation

## Problem

Issue #2723 framed a `tech-debt-tracker` as a "scheduled agent maintaining a persistent ledger with trending — closes review-time-only gap." The framing implied two capability gaps: no persistent ledger and no trending. Spawning a triad (CPO + CLO + CTO) on the premise as written would have produced internally-coherent recommendations for *the wrong product*.

Two things were actually true:

1. **A ledger already existed** at `knowledge-base/project/learnings/technical-debt/` with 11 entries and structured YAML frontmatter (`severity`, `component`, `tags`, etc.), populated reactively by `/soleur:compound` after fixes ship.
2. **The ledger was write-mostly.** Zero entries had a resolution marker; `gh issue list --search "tech-debt in:title" --state closed` returned empty. Three months of entries, zero closures.

## Solution

Two patterns paired:

**Pattern 1 — Grep KB for prior art before accepting feature framing.** Before spawning research/leader agents on a feature request, run `find knowledge-base/project/{brainstorms,specs,learnings} -type f -iname "*<keyword>*"`. If the claimed gap already exists in some form, reframe the brainstorm as "given the existing artifact X, what's actually missing?" rather than "research this topic cold." The Phase 1.1 pre-research check in `soleur:brainstorm` already mandates this for brainstorms/specs — extend the same check to `learnings/` and feature-request bodies.

**Pattern 2 — Write-mostly artifact diagnosis.** When an existing ledger, queue, or backlog has zero closures over a long window (months), it is a falsifiable signal that adding a tool which produces *more entries* will compound the backlog, not the knowledge. The load-bearing prerequisite is a **closure mechanic**, not more production. In this case: ship a lifecycle skill (status + linked_issue, ~1d) FIRST, then wait 60 days. If closures emerge, automation is unblocked with evidence. If no closures emerge, the automation gets killed (correct outcome — saves the cost of building a tool nobody uses).

Outcome on this brainstorm: #2723 reframed to lifecycle prereq (Spec A); scheduled scanner split out to #3650 with explicit ALL-must-hold re-evaluation criteria (≥3 closures in 60d AND cloud platform T1 shipped or velocity-drag retro AND ≥1 linked_issue-closing-PR).

## Key Insight

A "capability gap" claim in a feature request is *unverified evidence*. The brainstorm's job at Phase 1.1 is to convert the claim into either:
- **Confirmed gap with grep evidence** (proceed to design), or
- **Refuted premise** (reframe; usually the real gap is one layer down — lifecycle, not creation; closure, not detection; triage, not aggregation).

When the artifact already exists, the next question is always "is it actually used?" An unused artifact + a tool that produces more of it = a compounding bug surface, not a compounding knowledge surface. The cheap test is **build the closure loop first** and let the evidence decide whether the production loop is worth building.

## Session Errors

- **`gh api .../contents/engineering/tech-debt-tracker` returned 404.** Wrong upstream path assumed from the issue body's slug. Real upstream path is `engineering/skills/tech-debt-tracker/`. **Recovery:** switched to recursive tree search (`gh api .../git/trees/main?recursive=1 --jq '.tree[] | select(.path | test("tech.debt"; "i")) | .path'`) which surfaced all matching paths in one call. **Prevention:** when fetching contents from a third-party repo via `gh api`, default to the recursive tree search first to discover the real path layout — `/contents/<guessed-path>` is a 404 trap if the upstream layout differs from what an issue body implies.

## Tags
category: workflow-patterns
module: plugins/soleur/skills/brainstorm
