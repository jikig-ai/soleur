---
title: git-data LUKS cutover resume, 2026-10-15 re-check, rehearsal run sheet, owner chain
lane: cross-domain
brand_survival_threshold: single-user incident
tracking: "#8211"
---

# Spec: git-data cutover resume (#8211)

## Problem Statement
The 2026-10-15 resume brief is a snapshot. It needs a live re-read of the flip preconditions for both hosts, a design for the
flip-then-rollback rehearsal on both web hosts, and the owner-gated chain as exact one-step commands. Design and read only.

## Deliverables (all in this directory)
- FR1: `precondition-recheck-2026-10-15.md` (task 1).
- FR2: `rehearsal-run-sheet.md` (task 2, design only).
- FR3: `owner-command-chain.md` (task 3).

## Non-Goals
No dispatch, apply or production write. No edit to PR #10294, its worktree, `AGENTS.rules.md`, or any legal document. #9943 and #6975 are not built here.

## Rulings
- Ruled by CTO agent, 2026-10-15: #9943 does not fit one small PR; defer, not a flip precondition. One flip and one rollback dispatch cover both web hosts.
