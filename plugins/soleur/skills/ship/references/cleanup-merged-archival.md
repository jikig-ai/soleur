# Why `cleanup-merged` is not the KB-archival point

Loaded from ship Phase 7 Step 4's archival note. `cleanup-merged` carries an
archive step, but its own header scopes it: *"Backward-compat for legacy
pre-#2815 worktrees that created specs at the bare root. New layout commits
the spec inside the worktree (git history is the canonical archive); the
`[[ -d ]]` guard silently skips when the bare-root dir does not exist."* Two
independent reasons it cannot durably archive a modern spec dir:

1. **It usually does not run at all.** The step guards on
   `[[ -d "$GIT_ROOT/knowledge-base/project/specs/<branch>" ]]` against the
   BARE ROOT's on-disk files, and it executes *before* the "Updated main to
   latest" step. On a just-merged branch the bare root is therefore still at
   the pre-merge commit, where the spec dir does not exist — it arrives only
   with the merge being cleaned up. Guard false, silent skip. Measured on PR
   #7240: the dir is ABSENT at `5133e3cb` (main at archival time) and PRESENT
   at `933635603` (the merge commit).
2. **Even when it runs it commits nothing.** It is a plain `mv` of the bare
   root's working files, so it produces no commit and leaves the spec dir
   tracked at its LIVE path on `main`.

The archives that actually exist under `specs/archive/` were committed by
**compound's** automatic consolidation (`git mv` + commit on the feature
branch), which is the only mechanism that persists.

The practical consequence: **ship's Phase 6.45 (KB Artifact Archival) is the
in-PR archival point** — the named phase both PR arms run before any
`gh pr ready` / `gh pr merge` site, backed by the `ship-kb-archive-gate.sh`
PreToolUse hook. Compound's Step E archives eagerly when no live-path reader
remains, but a deferred archival — the legitimate choice when
`specs/<branch>/decision-challenges.md` must stay live for Phase 6 step 2.5's
Model Dissents render or the plan file's `## Operator Holds` for step 5 — no
longer strands the artifacts: Phase 6.45 runs `archive-kb.sh` AFTER those
last reads and the `git mv` rides the same PR. A follow-up PR is never
required for archival. **Why the ordering is load-bearing:** PR #7240
deferred compound's archival so Phase 6 step 2.5 could read
`decision-challenges.md`, on the strength of `cleanup-merged` archiving
post-merge — it did not, and the spec dir shipped unarchived; #9768 shipped
unarchived the same way in 2026-10.
