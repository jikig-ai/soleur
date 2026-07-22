---
title: A fixed-/tmp → mktemp sweep must ECHO the path, or it breaks cross-Bash-call recovery
date: 2026-07-18
category: best-practices
tags: [scratch-path, mktemp, worktree-isolation, review, sweep, guard]
pr: 6486
issue: 6486
---

# Learning: converting a fixed `/tmp` path to `$(mktemp)` silently breaks cross-Bash-call recovery unless you echo the path

## Problem

PR #6486 added a guard (`plugins/soleur/test/scratch-path-collision.test.ts`) that flags
agent-facing guidance prescribing a **literal `/tmp/…` scratch path** — such a path is a pure
function of its name, so every concurrent worktree writes the SAME file and clobbers/misreads
each other (ADR-009 amendment: "a worktree isolates the working tree, NOT process-level
scratch; `/tmp` is one namespace shared by every worktree").

The obvious fix for each flagged site is `v=$(mktemp); … "$v"`. But a **fixed literal path was
durable across separate Bash tool calls** (a constant string survives because separate calls
re-type it), whereas a `mktemp` shell variable is **not** — separate Bash tool invocations do
not inherit env, so `$v` is empty in any later call. The sweep in this PR converted three sites
without adding the recovery mechanism:

- `review/SKILL.md` (**P1**): `bak=$(mktemp); cp <file> "$bak"` is a **restore source** the same
  passage mandates using in a SEPARATE Bash call. Unechoed, the restore runs `cp "" <file>` (or
  aborts on `set -u`) → the mutated file is never restored → the exact silent-total data loss the
  prophylactic exists to prevent (#6415/#6454).
- `ship/SKILL.md` (P2): `body=$(mktemp)` read by a later `--body-file` call and an awk
  precondition gate ~90 lines down (separate steps) → `--body-file ""`.
- `merge-pr/SKILL.md` (P2): `ours/theirs=$(mktemp)` written, then Read/Write tool steps need the
  literal paths that were never surfaced.

Two independent review agents (code-quality-analyst, pattern-recognition-specialist) converged
on this class; the green guard test could not see it (it only checks for literal `/tmp` strings,
not whether the replacement variable survives to its readers).

## Solution

When a sweep replaces a fixed `/tmp/foo` with `v=$(mktemp)`, decide the artifact's **consumer
scope**:

- Consumed inside ONE Bash call → `mktemp` + quoted `"$v"`, no echo needed.
- Consumed by a LATER, separate Bash/Read/Write call → `mktemp` **and `echo "V=$v"`** so the path
  is recoverable from the transcript, plus a one-line note that a separate call does not inherit
  the var. (This is exactly what the guard's own failure message prescribes: "capture a unique
  path and echo it so it stays findable.")
- A restore SOURCE (a `.bak` used by a later restore) is the highest-stakes case — echo is
  mandatory, and a colliding/empty path is silent-total loss, not a clobbered log.

The pre-existing sites that were swept correctly (`plan`, `qa`, `work`, `incident/dry-run.sh`,
`preflight` re-deriving `$(git rev-parse --git-dir)`) all did exactly this. The three regressed
sites just omitted it.

## Key Insight

A guard that forbids literal `/tmp` paths pushes authors toward `mktemp`, which **trades a
collision hazard for a cross-call-recovery hazard**. The fix is not "mktemp" — it is "mktemp
**and echo the path** whenever a later separate call must find it." A green guard proves the
literal is gone; it does NOT prove the replacement variable reaches its reader.

Two adjacent guard-authoring insights from the same PR:

- **Broadening a matcher requires re-sweeping — including after a merge.** Pivoting the guard
  from write-verb-anchored to literal-path-anchored (catching reads: `cat`, `rm`, `--body-file`,
  bare prose) surfaced offenders the write-verb version was blind to, AND merging `origin/main`
  pulled in NEW `/tmp` sites (`plan/.doppler`, `agent-browser`, `feature-video`) that had to be
  re-swept/waived. Re-run the guard after every merge, not just at authoring time.
- **Every member of a hand-tuned regex char-class needs a fixture, or it is decorative.** The
  class `[A-Za-z0-9_.<>${}*/-]` included `_`, but no fixture pinned it — dropping `_` stayed
  GREEN while `/tmp/_lock` (a leaf starting with `_`) was missed entirely. And a lookbehind that
  over-excludes (`(?<![\w${}])` excluding `{`) hid brace-expansion `{/tmp/a,/tmp/b}` — the first
  element `/tmp/a` is a real literal write. Tightened to `(?<![\w}])` + added `_`/brace fixtures.

## Session Errors

- **`git stash list` blocked by `hr-never-git-stash-in-worktrees`** — Recovery: re-ran the
  compound command without it. Prevention: already hook-enforced; the block fired correctly. The
  read-only `git stash list` is denied too, so probe stashes via `git rev-parse --verify --quiet
  refs/stash` instead.
- **`./node_modules/.bin/bun` → rc=127** — bun is installed at `~/.bun/bin/bun` (on PATH), not in
  the repo's `node_modules/.bin`. Recovery: invoked `bun test` directly. Prevention: use bare
  `bun` for this repo's bun-test suites (contrast: vitest IS pinned in `node_modules/.bin`).
- **Resumed a prior session's uncommitted, incomplete redesign that was RED (17 guard offenders)**
  — Recovery: ran the test FIRST to confirm RED before extending, per "resumed artifacts are
  UNVERIFIED." Prevention: on resume, always run the affected test before treating uncommitted
  work as done.
- **Sweep reintroduced the PR's own failure class at 3 sites (mktemp path unechoed)** — Recovery:
  fixed inline after two review agents converged. Prevention: this learning + the guard message
  already prescribing the echo.
- Forwarded from `session-state.md`: plan-write blocked by `iac-plan-write-guard.sh` (negating
  trigger tokens matched the bare-token grep); plan v1 widened the char-class but left the anchor
  redirect-only (rewritten after review); one count `16` was wrong, corrected to `18` by
  re-enumeration.
