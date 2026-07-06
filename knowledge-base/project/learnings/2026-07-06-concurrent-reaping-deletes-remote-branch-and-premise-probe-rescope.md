# Learning: Concurrent worktree reaping can delete the REMOTE branch too; and a deferred issue's soak gate is a Phase-0 re-scope signal

## Problem

Two things happened during the `/soleur:go 6038` → brainstorm session on 2026-07-06:

1. **Worktree AND remote branch reaped within ~1 minute of creation, despite a session lease.**
   `worktree-manager.sh feature harness-auto-edit-safety-policy` completed successfully — full
   checkout, deps installed, and the branch pushed with remote tracking set up
   (`branch '...' set up to track 'origin/...'`) and the lease acquired
   (`Worktree leased; release on session exit`). Seconds later the immediate `cd` into the worktree
   failed (`No such file or directory`), `git worktree list` did not show it, and BOTH
   `git branch --list 'feat-harness*'` (local) AND `git ls-remote --heads origin feat-harness-...`
   (remote) returned empty. The `git worktree list` output had visibly churned mid-session
   (different sibling worktrees than at session start), confirming an aggressive concurrent-session
   cleanup was running.

2. **A deferred issue's re-evaluation gate was un-meetable — caught at Phase 0.** `#6038`'s body
   listed ALL-must-hold re-evaluation criteria, criterion 1 being "≥1 month of #6037 digests."
   The Phase 0 premise probe found #6037 had shipped *the day before* (2026-07-05, PR #6036), so
   criterion 1 could not clear before ~2026-08-05, and criteria 2 (ADR) + 3 (owner) were unmet.

## Solution

1. **Reaping:** re-ran `worktree-manager.sh feature`, verified existence *in the same command*
   (`ls -d <path>` + `git worktree list | grep`), and immediately ran `worktree-manager.sh draft-pr`
   to push + open the draft PR (#6101) before any file writes. It survived the second time. Then
   committed + pushed each artifact (brainstorm doc, spec) as soon as it was written rather than
   batching, to minimize the exposure window.

2. **Premise gate:** surfaced the un-meetable gate to the operator via `AskUserQuestion` instead of
   creating a worktree and spawning leaders for a build that violates the issue's own gate. Operator
   chose to do the soak-*independent* prerequisites (ADR + semantic-weakening detector + owner);
   the build stays deferred under #6038. New tracking issue #6103 for the prereq bundle.

## Key Insight

- **Concurrent reaping on this repo can delete the REMOTE branch, not just the local worktree dir.**
  The existing `2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md` learning covers the
  local-dir wipe; this session shows the reaper also ran `git push origin --delete <branch>` (or an
  equivalent) on an unmerged, freshly-pushed, *leased* branch. The session lease
  (`SOLEUR_SKILL_NAME` + `SOLEUR_EXPECTED_DURATION_MIN`) did not protect it. Practical mitigation:
  after `worktree-manager.sh feature`, **verify the worktree exists in the same breath, run
  `draft-pr` immediately, and commit+push each artifact as written** — treat the window between
  creation and first push as hostile. If a worktree vanishes, re-create rather than trying to
  `git worktree prune`/recover — the branch may be gone from origin too.

- **A deferred issue whose re-evaluation criteria include a soak/observation window is a Phase-0
  re-scope signal, not a build.** When `#N`'s prerequisite shipped very recently, a "≥1 month"
  (or any elapsed-time) criterion is categorically un-meetable — check `gh issue view <prereq>
  --json closedAt` before creating a worktree. The productive move is to split out the
  soak-*independent* criteria (ADRs, owner assignments, gap-closures) into their own issue and do
  those now, leaving the build deferred. Matches
  `2026-06-29-brainstorm-soak-gated-tracker-item-and-grep-helper-sig-before-accepting-obstacle.md`.

## Session Errors

- **Concurrent-session worktree + remote-branch reaping despite lease.**
  Recovery: recreate worktree, verify-in-same-command, immediate `draft-pr`, commit+push per
  artifact. Prevention: none mechanical yet — candidate follow-up is to harden the reaper's
  lease-respect for freshly-pushed unmerged branches (it currently appears to delete remotes it
  should skip). Documented here rather than filed as a separate issue because the root cause lives
  in the cleanup-merged/reaper path shared with the existing 2026-04-21 learning; consolidate there
  if it recurs.
- **#6038 premise mismatch** — NOT a defect; the Phase 0 premise probe worked as designed and
  produced a correct re-scope. Prevention: already covered by the go/brainstorm premise-probe steps.

## Tags
category: workflow-patterns
module: git-worktree, brainstorm, soleur-go
