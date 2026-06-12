# Learning: hook tests pass on a feature-branch worktree but can fail only on main-CI (CWD-dependent gate masking)

## Problem

PR #5193 (#5192) merged green on its feature branch — local `bash scripts/test-all.sh` (scripts shard) reported **104/104** — but turned **main red**: the post-merge CI re-run on `main` reported **103/104**, with `guardrails.test.sh` fixtures AC1/AC3/AC4 failing.

## Root cause

The new commit-body false-positive fixtures use real `git commit` commands as the hook input. `guardrails.sh` has an ORTHOGONAL gate — `block-commit-on-main` — that resolves the branch from the hook's **process CWD** (`git rev-parse --abbrev-ref HEAD`). The test helper `decision_of` ran the hook from the test's CWD:

- On a **feature-branch worktree** (every local `/work` and `/ship` run): branch ≠ main → `block-commit-on-main` no-ops → the `require-milestone`/`block-stash` gate under test is exercised → fixtures pass.
- On **`main`** (post-merge CI runs on the merged commit, i.e. the `main` branch): `block-commit-on-main` denies the commit → masks the gate under test → the `<none>` (allow) assertions get `deny` → fail.

The sibling hooks' new fixtures (cla, ship-unpushed, follow-through) build self-contained git repos and pass `cwd` in the payload, so they were branch-independent; only `guardrails.test.sh` relied on the ambient process CWD.

## Solution

Run the hook from the non-git `$tmp` CWD in `decision_of` so branch resolution is empty → `block-commit-on-main` no-ops → the gate under test is isolated and the fixture is branch/environment-independent (PR #5209). Verified 16/16 on a feature branch AND a simulated committed-`main` CWD.

## Key Insight

**Local hook-test verification has a permanent feature-branch blind spot.** `/work` and `/ship` always run from a `feat-*`/`fix-*` worktree, so any hook test whose outcome depends on a CWD/branch-resolved gate (`block-commit-on-main`, `git worktree list` counts, `symbolic-ref HEAD`) passes locally and can fail ONLY on main-CI — which runs on the merged `main` commit. The 104/104 local pass is not authoritative for these tests.

Two mitigations, both cheap:
1. **Test-author side:** a hook test must isolate the gate it exercises from sibling CWD/branch-dependent gates — run the hook from a controlled CWD (non-git tmp, or a self-contained repo on a pinned non-main branch with `cwd` in the payload), never the ambient process CWD.
2. **Verification side:** before merging a `.claude/hooks/*.test.sh` change, run the suite once from a simulated `main`-branch CWD (`cd $(mktemp -d) && git init -b main && git commit --allow-empty …`, then run the suite from there). This reproduces what post-merge CI sees.

## Session Errors

1. **Local 104/104 → main 103/104 (post-merge red).** Recovery: traced the failing CI suite (`gh run view <id> --log | grep test-scripts`), reproduced with a committed-`main` CWD, isolated `decision_of` from `block-commit-on-main`, shipped forward-fix #5209. Prevention: the two mitigations above — the verification-side "run from simulated main-CWD" check is the one that would have caught this pre-merge.
2. **Monitor died with "Unable to read current working directory."** Recovery: the post-merge worktree reap deleted the monitor's CWD; re-ran subsequent monitors from the bare repo root. Prevention: run post-merge Monitor/poll loops from the bare repo root, never from the worktree that cleanup-merged will reap.

## Tags
category: test-failures
module: .claude/hooks
