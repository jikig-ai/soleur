---
title: "Tasks: age-guarded stale git-lock sweep in worktree tooling"
branch: feat-one-shot-stale-git-lock-sweep
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-01-fix-stale-git-lock-sweep-worktree-plan.md
brand_survival_threshold: single-user incident
---

# Tasks — Stale git-lock sweep (worktree self-heal)

Derived from
[2026-07-01-fix-stale-git-lock-sweep-worktree-plan.md](../../plans/2026-07-01-fix-stale-git-lock-sweep-worktree-plan.md).

## Phase 1 — Test first (RED)

- [x] 1.1 Create `plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh`
  following the structure of the sibling `create-from-origin-main.test.sh`
  (bare-repo + linked-worktree setup, `PASS`/`FAIL` counters, `exit 1` on any fail,
  `mktemp -d` + EXIT-trap cleanup).
- [x] 1.2 In setup: stand up a bare repo + linked worktree, `cd` into the worktree,
  `source` the manager script (its `BASH_SOURCE`/`$0` guard at :1490 supports
  sourcing without running `main`), and resolve `git_dir` the same way
  `ensure_bare_config` does.
- [x] 1.3 Assertions (see plan Test Scenarios):
  - [x] AC1 aged `config.lock` (`touch -d '120 seconds ago'`) → removed by
    `sweep_stale_git_locks "$git_dir" 60`.
  - [x] AC2 fresh `config.worktree.lock` (`touch`) → preserved.
  - [x] AC3 aged `HEAD.lock` removed + fresh `index.lock` preserved in one run.
  - [x] AC4 future-dated lock (`touch -d '+120 seconds'`) → preserved (clock-skew).
  - [x] AC5 black-box: aged `config.lock` planted, `bash "$WM" --yes cleanup-merged`
    run as a subprocess → lock gone (proves wiring through `ensure_bare_config`).
  - [x] AC6 after a sweep with a fresh lock present, a real
    `git config --file "$git_dir/config" test.key val` still succeeds.
  - [x] AC7 no-op when no lock present → exit 0, no error (`set -e` / empty-set guard).
- [x] 1.4 Run the new test; confirm it FAILS (function does not yet exist).

## Phase 2 — Implement (GREEN)

- [x] 2.1 Add `sweep_stale_git_locks()` to
  `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (near
  `ensure_bare_config`, ~line 124). Signature `sweep_stale_git_locks <git_dir>
  [threshold_secs=60]`.
- [x] 2.2 Iterate the fixed lock set `config.lock config.worktree.lock index.lock
  HEAD.lock` in `$git_dir`; for each present file, `mtime=$(stat -c %Y … 2>/dev/null)
  || continue`; compute `age=$(( now - mtime ))`; remove only when
  `if (( age >= threshold ))` (nested in `if` for `set -e` safety), with `rm -f …
  2>/dev/null` guarded by `if`. Echo `Swept N stale git lock file(s) …` when
  `swept > 0`. Add a one-line comment noting the GNU `stat -c` assumption.
- [x] 2.3 Call `sweep_stale_git_locks "$git_dir"` inside `ensure_bare_config()`
  immediately after `git_dir` is resolved (after :137) and BEFORE the first
  `git config --file "$shared_config" core.repositoryformatversion 1` write (:144).
- [x] 2.4 Do NOT add a second call site in `cleanup_merged_worktrees` (it routes
  through `ensure_bare_config` at :888 — covered transitively).
- [x] 2.5 Do NOT touch the bwrap/tenant-isolation layer
  (`agent-runner-sandbox-config.ts`, seccomp profile, vendored SDK) — scope boundary
  owned by `feat-harden-agent-sandbox-5875`.

## Phase 3 — Verify

- [x] 3.1 `bash plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh`
  passes (all ACs green).
- [x] 3.2 `bash -n plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  passes; `shellcheck` clean if available.
- [x] 3.3 Sibling tests still pass: `create-from-origin-main.test.sh`,
  `lease-protects-active.test.sh`, `no-repo-fail-loud.test.sh`.
- [x] 3.4 `bash scripts/test-all.sh` discovers and runs the new test (via the
  `plugins/soleur/skills/*/test/*.test.sh` glob).
- [x] 3.5 Confirm `git status` shows only `worktree-manager.sh` + the new test
  changed (scope boundary respected).
