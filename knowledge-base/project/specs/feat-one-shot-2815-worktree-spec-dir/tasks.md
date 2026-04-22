# Tasks: Fix worktree spec-dir created at bare root (#2815)

Derived from: `knowledge-base/project/plans/2026-04-22-fix-worktree-spec-dir-bare-root-plan.md`

## 1. Setup

- 1.1 Confirm branch is `feat-one-shot-2815-worktree-spec-dir` (worktree already active).
- 1.2 Re-read `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` lines 393-458 and 766-778 before editing.

## 2. Core Implementation (TDD)

### 2.1 RED — failing test

- 2.1.1 Create `plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh` using the `resolve-git-root.test.sh` template.
- 2.1.2 Test setup: `set -euo pipefail`, clear `GIT_*` env vars, source `test-helpers.sh`, create `mktemp -d` bare repo with one worktree.
- 2.1.3 Test case 1: assert `<worktree_path>/knowledge-base/project/specs/feat-<name>/` EXISTS after `feature <name>`.
- 2.1.4 Test case 2: assert `<bare_root>/knowledge-base/project/specs/feat-<name>/` does NOT exist after `feature <name>`.
- 2.1.5 Test case 3: idempotency — second invocation does not error, does not create duplicate dirs.
- 2.1.6 Run `bash plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh` — verify RED (tests fail as expected).
- 2.1.7 Commit: `test(worktree): failing test for spec-dir-at-bare-root (#2815)`.

### 2.2 GREEN — minimal fix

- 2.2.1 Edit `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` line 406: change `$GIT_ROOT` → `$worktree_path` in the `spec_dir` assignment.
- 2.2.2 Edit line 439 guard: change `$GIT_ROOT/knowledge-base` → `$worktree_path/knowledge-base`.
- 2.2.3 Add inline comment at line 767 (inside `cleanup_merged_worktrees`) noting that the block still handles legacy bare-root spec dirs from pre-fix worktrees.
- 2.2.4 Run the new test — verify GREEN.
- 2.2.5 Run sibling `.test.sh` files in `plugins/soleur/test/` — verify no regressions.
- 2.2.6 Commit: `fix(worktree): create spec dir inside worktree, not bare root (#2815)`.

## 3. Testing

- 3.1 Manual smoke test: from bare root, run `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes feature smoke-test-2815`. Verify `<worktree_path>/knowledge-base/project/specs/feat-smoke-test-2815/` exists and `<bare_root>/knowledge-base/project/specs/feat-smoke-test-2815/` does NOT.
- 3.2 Clean up the smoke-test worktree: `git worktree remove .worktrees/feat-smoke-test-2815 --force && git branch -D feat-smoke-test-2815`.

## 4. Ship

- 4.1 Run `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-22-fix-worktree-spec-dir-bare-root-plan.md knowledge-base/project/specs/feat-one-shot-2815-worktree-spec-dir/tasks.md` (target specific paths, per `cq-markdownlint-fix-target-specific-paths`).
- 4.2 Run `skill: soleur:compound` to capture any session learnings.
- 4.3 Use `/ship` with `semver:patch` label.
- 4.4 PR body: include `Closes #2815` (in body, not title, per `wg-use-closes-n-in-pr-body-not-title-to`).
- 4.5 After merge, confirm `cleanup_merged_worktrees` archives gracefully — no errors on next run.
