---
title: Squash merge drops branch-commit trailers — PR body is the durable cross-PR surface
date: 2026-10-01
category: workflow-patterns
issue: 9403
---

`soleur:ship` queues `gh pr merge --squash --auto` (`ship/SKILL.md` merge step).
Squash derives main's commit message from the PR title and body — trailers on
branch commits never reach `origin/main`. A `Pipeline-Cost:` trailer emitted by
`emit-review-trailer.sh`-style `--allow-empty` commits is readable only on
`git log origin/main..HEAD` **pre-merge**; after merge the key does not exist.

Caught at plan-review (#9403 plan): the brainstorm prescribed a `Pipeline-Cost:`
git trailer for cross-PR aggregation, and `soleur:engineering:review:kieran-rails-reviewer`
flagged it dead-on-arrival. Pre-merge consumers (ship's review-evidence gate
reading `Reviewed-Coverage:` with `head -1`) work fine — the trap is only
post-merge aggregation, which must read PR bodies
(`gh pr list --search "Pipeline-Tally:"`) instead.

## Session Errors

1. `gh issue create` refused twice by the filing gate: first for carrying no
   exit at all, then for a `User-Impact:` line that named no token from the
   closed `user-surface-taxonomy.txt` vocabulary (route/page/component/CLI/
   command/report/…). **Prevention:** when authoring `User-Impact:`, include a
   taxonomy word verbatim — e.g. "the `<cmd>` CLI command" or "the PR-body
   report" — and give `Fix-Size:` exact integers (`60 lines / 9 files`, not
   `~60`). The deny message does not mention the taxonomy; the vocabulary lives
   in `.claude/hooks/lib/user-surface-taxonomy.txt`.
2. A research subagent cited `plugins/soleur/scripts/emit-review-trailer.sh`;
   the file lives at `plugins/soleur/skills/review/scripts/`. **Prevention:**
   verify substrate paths against the worktree before they enter a plan
   (Phase 0.6 premise check caught this).

## Key Insight

A git trailer is a per-commit signal and survives only where the commit
survives. Pre-merge gates can consume branch trailers; anything meant to be
read after squash-merge belongs in the PR body.

## Tags

trailers, squash-merge, pr-body, aggregation, ship
