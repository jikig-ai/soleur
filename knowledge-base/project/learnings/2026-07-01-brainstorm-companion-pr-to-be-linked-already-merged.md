---
date: 2026-07-01
category: workflow-patterns
module: brainstorm
issue: 5754
tags: [brainstorm, premise-validation, companion-pr, greenfield-framing]
---

# Learning: a "companion PR (to be linked)" forward-reference is a premise-drift canary — grep for the artifact's existence before accepting greenfield framing

## Problem

`/soleur:go 5754` routed to brainstorm on an issue titled *"feat(sync): populate a
business-rules / domain-model register from source code"* whose body said: *"Establish a
register at `knowledge-base/engineering/architecture/domain-model.md`"* and *"Companion PR
(creates the register + the workflow gate): **to be linked**."*

Read literally, scope #1 was "create the register" — a greenfield framing. But the register
**already existed**: the companion **PR #5773 had merged the day before (2026-06-30)**, seeding
5 entities + 9 business rules + the ADR-maintenance hook. Accepting the greenfield framing would
have produced a brainstorm/spec to build an artifact that already exists, and spawned domain
leaders on a wrong factual floor.

## Solution

Caught pre-worktree, before any leader spawn, with two cheap probes:
- `git show main:knowledge-base/engineering/architecture/domain-model.md` → file exists (4694 B).
- `gh pr list --state all --search "domain-model register"` → **PR #5773 MERGED 2026-06-30**.

The register's own body confirmed the reframe: its maintenance contract text named **#5754** as
the tracker for the *remaining* work (the `/soleur:sync --domain-model` analyzer + fast-follow
enforcement gates). The brainstorm was reframed from "register format" to "the analyzer /
drift-detector" and proceeded on the correct floor.

## Key Insight

The brainstorm skill's Pre-worktree premise probe triggers on *backward*-looking staleness
phrasings (`does not yet exist`, `deferred from #N`, `blocked by #N`, `after PR #N merges`). A
**forward reference to an unlinked companion PR** ("companion PR: to be linked", "seeded under a
separate PR", "created by the companion change") is a *different* canary the existing regex misses:
the companion is filed to land in parallel and, on a fast-moving repo, routinely **merges before
the brainstorm runs**. When an issue frames work as "create X" AND cites a not-yet-linked companion
that creates X, `git show main:<X>` + `gh pr list --search "<X>"` BEFORE accepting the greenfield
framing. If X exists, the real scope is the *remainder* the issue tracks, not X itself.

## Session Errors

- **`Monitor` called without loading its deferred schema** — Recovery: dropped it; background
  agents auto-notify on completion. Prevention: don't reach for Monitor to poll harness-tracked
  background agents — they re-invoke automatically. One-off.
- **Heredoc write to a not-yet-created scratchpad dir failed** ("No such file or directory") —
  Recovery: used the Write tool (creates parent dirs). Prevention: prefer the Write tool for
  scratchpad files. One-off.

## Tags
category: workflow-patterns
module: brainstorm
