---
title: "Tasks: fix(git-worktree) create from origin/main"
branch: feat-one-shot-3741
issue: 3741
plan: knowledge-base/project/plans/2026-05-14-fix-worktree-create-from-origin-main-plan.md
lane: single-domain
---

# Tasks: fix(git-worktree) create new worktrees from origin/main

## Phase 0 — Preconditions

- [ ] 0.1 Confirm bare-repo layout: `git rev-parse --is-bare-repository == true` from project root.
- [ ] 0.2 Confirm `--update-local-main` is not already a recognized flag: `grep -n update-local-main plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` returns empty.
- [ ] 0.3 Run pre-existing test locally to verify baseline: `bash plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` exits 0.

## Phase 1 — RED

- [ ] 1.1 Create `plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` per plan Phase 1 spec.
- [ ] 1.2 Run new test: `bash plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` — confirm AC1 fails with `fatal: refusing to fetch into branch 'refs/heads/main'`.
- [ ] 1.3 Stage with `git add` (do NOT commit yet).

## Phase 2 — GREEN

- [ ] 2.1 Add `UPDATE_LOCAL_MAIN=false` initializer alongside `YES_FLAG=false` (~line 55).
- [ ] 2.2 Extend flag-parse loop (lines 1379-1389) to recognize `--update-local-main`.
- [ ] 2.3 Add `fetch_origin_branch()` helper near `update_branch_ref()`.
- [ ] 2.4 Modify `create_worktree()` (lines 424-432) to branch on `UPDATE_LOCAL_MAIN` and pass `origin/$from_branch` to `git worktree add` in the default path.
- [ ] 2.5 Apply identical edit to `create_for_feature()` (lines 487-496).
- [ ] 2.6 Update `show_help()` to document `--update-local-main`.
- [ ] 2.7 Update `plugins/soleur/skills/git-worktree/SKILL.md` `### create` section (lines 86-107) and Sharp Edges entry (line 312).
- [ ] 2.8 Extend `scripts/test-all.sh:43` glob to also iterate `plugins/soleur/skills/*/test/*.test.sh`.
- [ ] 2.9 Re-run new test: `bash plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` — confirm all PASS.

## Phase 3 — REFACTOR

- [ ] 3.1 Re-read diff for unused locals, stale comments, dead-code paths.
- [ ] 3.2 Confirm log line `Fetching latest origin/main...` appears in default path; `Updating main...` remains only in `--update-local-main` path.
- [ ] 3.3 Confirm `update_branch_ref()` is still called by `cleanup_merged_worktrees()` (post-cleanup main advancement is preserved).

## Phase 4 — Verify ACs

- [ ] 4.1 AC1-AC10: `bash plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` passes.
- [ ] 4.2 AC10: `bash scripts/test-all.sh` passes; suite count increased by ≥2.
- [ ] 4.3 AC11: SKILL.md Sharp Edges entry amended.
- [ ] 4.4 Manual smoke: reproduce issue scenario per plan Verification Steps §4.
- [ ] 4.5 `grep -n "git fetch origin main:main" plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` shows only the `cleanup_merged_worktrees` site and the `update_branch_ref` site (both inside opt-in paths).

## Phase 5 — Ship

- [ ] 5.1 Commit: `fix(git-worktree): base new worktrees on origin/main to bypass local-main lock` with body explaining default-vs-opt-in.
- [ ] 5.2 Push to `feat-one-shot-3741`.
- [ ] 5.3 Open PR (already drafted from worktree creation step). Update body with `## Summary`, `## Changelog`, `Closes #3741`, and Test plan.
- [ ] 5.4 Apply labels: `domain/engineering`, `priority/p2-medium`, `type/feature`, `semver:patch`.
- [ ] 5.5 Mark PR ready when review passes.
