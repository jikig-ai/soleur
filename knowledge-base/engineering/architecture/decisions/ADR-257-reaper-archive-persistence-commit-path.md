---
title: "ADR-257: Reaper archive writes persist via the checkout's commit path; deferred on non-committable checkouts"
status: Accepted
date: 2026-09-28
supersedes: []
amends: []
tags: [git-worktree, reaper, persistence, kb-archival, machinery]
---

# ADR-257: Reaper archive writes persist via the checkout's commit path; deferred on non-committable checkouts

## Status

Accepted — 2026-09-28. Delivers #9127.

## Context

`cleanup_merged_worktrees` in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
archived knowledge-base artifacts — the reaped feature's spec dir plus its
brainstorm and plan files (`archive_kb_files`) — with plain `mv`. On a checkout
where those artifacts are **tracked** (a non-bare clone parked on `main`, e.g.
the Concierge agent workspace of ADR-099, or an operator's plain clone), each
reap left unstaged deletions plus untracked `archive/` copies. The same
function's SOLEUR-GUARD-MAINRESET block then read that state as stale debris
and ran `git reset --hard HEAD`, which restored the moved tracked files to
their live paths while the untracked `archive/` copies persisted — a live spec
dir AND an archive twin, forever, for every reaped feature.

On the bare repo root the same class exists by a different mechanism:
`sync_bare_files` materializes HEAD via `checkout-index`, so a mirror file
moved on disk is re-materialized at its live path while the archive copy
survives.

The defect class is that **reaper archive writes had no persistence owner**.
Plain `mv` produces a worktree mutation that nothing commits, and every
mechanism that restores tracked state (`reset --hard`, `checkout-index`)
reverts the tracked half asymmetrically. Verified in production: three live
spec dirs coexisted with `specs/archive/` twins, diverged into complementary
halves as sessions kept writing post-resurrection. The existing test suite
could not see the class because its fixtures were untracked files, where `mv`
is tracking-agnostic.

## Decision

Every reap archive write persists via the checkout's own commit path, or is
not made at all. One chokepoint — `reap_archive_persist` in
`worktree-manager.sh` — routes all three archive sites (the spec-dir block and
both `archive_kb_files` call sites) through a single classification:

1. **Untracked artifact** → plain `mv`, unchanged. No resurrection mechanism
   applies to untracked paths; the `[[ -e archive_path ]]` no-clobber guard
   stays.
2. **Tracked artifact + committable checkout** (a non-`main`/`master`,
   non-detached branch of a non-bare checkout) → `git mv` (a staged index
   rename), then ONE pathspec-scoped `git commit` per reaped branch —
   `chore(archive-kb): persist reap archive for <slug>` — recording only that
   branch's archive-move paths. The pathspec is the boundary that keeps a
   session's unrelated staged work out of the commit. The commit rides the
   existing sanctioned feature-branch commit→PR→merge flow (`chore: initialize`
   precedent); no new write authority is created. On commit failure the staged
   payload is left and `SOLEUR_REAP_ARCHIVE_STAGED` is emitted, so the
   session's own commits still carry it; `LEFTHOOK=0` is never used.
3. **Tracked artifact + non-committable checkout** (`main`/`master`, detached
   `HEAD`, unborn HEAD, a merge in progress, or the bare root) → **no move at
   all**. `SOLEUR_REAP_ARCHIVE_DEFERRED slug=<s> reason=<main-checkout|detached|
   unborn|merge-in-progress|bare|git-mv-failed|outside-git-root|
   unsafe-destination>` is emitted and the live files stay in place. No worktree
   mutation is produced, so nothing exists for a later reset or mirror-sync to
   asymmetrically revert — the defect is removed at the producer, not patched
   downstream. Archival defers to a reap that runs in a committable context —
   and the committable context is specifically a **non-bare** checkout on a
   feature branch. On the bare-repo dev topology (the primary Soleur
   environment) even session worktrees resolve `IS_BARE=true` with `GIT_ROOT`
   at the bare root, so DEFERRED is the permanent steady state there — the
   spec stays live and the marker plus the follow-through probe keep the
   population visible. The sanctioned unstick is a manual `git mv` + commit
   on a non-bare feature-branch checkout (running `archive-kb.sh` on
   `main`/detached would re-create a staged-but-unpersisted rename — the same
   defect by hand).

Committability is probed ONCE per run before the reap loop by
`_reap_archive_classify` (`IS_BARE`, `rev-parse --abbrev-ref HEAD`, and a
`MERGE_HEAD` check); `_reap_archive_commit` re-reads `HEAD` at commit time and
requires equality with the probed branch — a concurrent `git checkout` mid-loop
degrades to STAGED rather than landing the chore commit on whatever branch is
current. Each artifact's tracked-ness is probed per file under
`GIT_LITERAL_PATHSPECS=1` (`ls-files --error-unmatch` on a worktree; `ls-tree
HEAD` on the bare root, whose on-disk mirror is untracked-from-disk but tracked
in HEAD), so a committed filename containing `*`, `?`, or `[]` cannot glob-widen
the probe or the scoped commit. A failed `git mv` never falls back to plain
`mv` — that would re-create the unpersisted mutation — and emits DEFERRED
`reason=git-mv-failed` so the arm is observable, not warn-only.

The three stranded spec twins produced before this fix were deduped in the same
PR by union-merging live-only files into each archive twin (they had diverged;
blind `git rm -r` would have lost `tasks.md`, `upstream-asks.md`,
`decision-challenges.md`, `phase-0-measurement.md`, `migration-checklist.md`).

## Alternatives considered

- **(a) A sanctioned auto-commit on `main`** — rejected. The `CI Required` /
  `CLA Required` rulesets gate `~DEFAULT_BRANCH` with `required_status_checks`,
  so a pushed commit can never reach `main` (the merge route is PR-only), and a
  never-pushed local commit diverges `main` from `origin/main` the moment origin
  advances — breaking `git pull --ff-only` in this very function's own tail,
  permanently. A hook carve-out for commits-on-main is a constitutional policy
  exception wholly disproportionate to a janitorial move.
- **(b) Dirty-check classifies reap-produced dirt as non-stale** — rejected. It
  never persists: nothing lands the move in history, `git status` stays
  permanently dirty, the live dirs remain tracked on `origin/main` for every
  other checkout, and partitioning reap-dirt from real debris requires per-path
  surgery the dirty-check does not have. A mitigation of the symptom on one
  checkout, not a fix for "no persistence owner".
- **Auto chore-branch + PR inside the reaper on `main`** — deferred. Functionally
  complete but heavyweight: branch lifecycle + push + `gh pr create` + auto-merge,
  CLA/CI dependencies inside a session-start path. Revisit only if the
  DEFERRED marker proves archival never lands in practice (the
  `reaper-archive-stranded-spec-9113.sh` follow-through probe counts the
  residual twin population).
- **Retire reaper KB archival entirely now** — out of scope. Plans and
  brainstorms still depend on archive moves for INDEX de-indexing (ADR-174's
  exclusion is scoped to `project/specs/` only); #7400 owns the retirement
  question. This fix makes the remaining archive writes safe while that
  decision lands.

## Consequences

- Positive: a reaper archive move can never again be manufactured into a twin;
  every tracked-archive decision is observable at the decision point via the
  COMMITTED / STAGED / DEFERRED markers; the chokepoint makes a fourth archive
  site that bypasses the rule self-evident in review (and census-tested).
- Negative / accepted: on a checkout that never runs committable sessions,
  DEFERRED archival can wait indefinitely — the spec stays live (the pre-defect
  state), and the marker plus the follow-through probe keep it visible. A
  reaper `chore(archive-kb)` commit lands on whichever feature branch the
  session is on when cleanup-merged runs in a worktree — expected and
  sanctioned (it rides the normal PR flow).
- Guard: `plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh`
  exercises all three arms plus the commit-failure (STAGED) and mixed-batch
  paths, with tracked fixtures that close the untracked-fixture blind spot the
  original suite had.
