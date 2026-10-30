---
module: System
date: 2026-10-21
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "git log on this branch shows a Devin-authored commit (96b243a740) interleaved between pipeline-phase commits"
  - "during the review phase a parallel session was live-editing the worktree (SKILL.md link polish, README count sync, baseline regen, test-affected-paths.sh)"
  - "at compound time the worktree still carries the sibling's uncommitted edits for issue #10759 (emit_tpl rewrite, run_hook append, guards.tsv v2 row)"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [worktree, sibling-session, concurrent-writers, staging]
synced_to: [review, plan]
---

# Learning: A sibling session can own commits on your branch — stage only the paths your phase owns

## Problem

This branch (`feat-one-shot-10404-verification-scaffold`) was written by more
than one pipeline session. Commit `96b243a740` — the phase 1–3 implementation
(audit corpus + `guards.tsv` + templates + generator) — is Devin-authored and
landed between this pipeline's own commits. During `soleur:review`, the
sibling was still live-editing the worktree (SKILL.md link polish, README
count sync, baseline regen, `test-affected-paths.sh` affected-map). And at
compound time `git status` still shows the sibling's uncommitted `emit_tpl` /
`run_hook` / `guards.tsv` edits addressing #10759 — a file I needed to note a
residual for but must not commit.

The danger shape: any phase that runs `git add -A` or stages a whole file
*adopts* the sibling's in-flight work under its own commit message — mixing
authors, scopes and readiness in one commit, and (worse) potentially
committing half-finished edits the sibling intended to keep working.

## Solution

The review phase did it right and the pattern generalizes:

- `git log origin/<branch>..HEAD` and `git status --short` before any commit —
  a commit or dirty path your phase did not produce means a sibling owns it.
- Stage ONLY the paths your phase owns (explicit pathspecs), and leave foreign
  unstaged edits in place for their owner to land.
- When your own fix must touch a file a sibling has dirty, prefer filing the
  finding (on the issue the sibling is working — here #10759) over entangling
  your hunk into their unstaged diff: `git add` on that file would stage both.

## Key Insight

**In the fleet model a worktree is a shared mutable surface, not a private
scratch.** Branch authorship is plural by construction — "my branch" names the
PR, not the set of writers. Every commit step is implicitly a merge step, so
it owes the same discipline: know which hunks are yours, stage by pathspec,
and treat an unexpected dirty file as somebody's in-flight work rather than as
unattributed drift.

## Session Errors

1. **Compound-phase staging hazard recognized, not hit** — `git status`
   showed two sibling-dirty files before any commit; all staging below uses
   explicit pathspecs. **Prevention:** the three-command ownership check
   (`git log origin/<branch>..HEAD`, `git status --short`, `gh pr view
   --json headRefOid`) before every commit on a shared worktree.
2. **`decision-challenges.md` non-canonical table** (forwarded, plan phase) —
   5-col header + stray rows; the ruling gate's `@BADHEADER`/`@STRAY`
   classes. Recovery: `b33c34d2c4`. **Prevention:** rows append INSIDE the
   canonical `| Item | Class | Ruling |` table; run
   `technical-ruling-gate.sh --branch` before returning the plan.
3. **`$WORK` leak partial-fix claim** — "all exit paths" covered only
   post-arm exits; pre-trap `--dry-run`/`--uninstall`/die paths still leak.
   Recovery: filed on #10759 rather than editing the sibling-dirty file.
   **Prevention:** see sibling learning
   `2026-10-21-mktemp-cleanup-armed-late-leaks-every-early-exit.md`.

## Tags

category: workflow-issues
module: plugins/soleur, .worktrees
