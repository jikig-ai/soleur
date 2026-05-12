---
title: Tasks — Full /bg-readiness concurrency hardening
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan: knowledge-base/project/plans/2026-05-12-feat-bg-readiness-concurrency-hardening-plan.md
issue: 3690
pr: 3689
sub_commits: 3
---

# Tasks: Full /bg-readiness — Soleur concurrency hardening

## Phase 0 — Setup

- [ ] 0.1 Verify on `feat-cc-agent-view-integration` worktree; `git rev-parse --git-common-dir` resolves correctly.
- [ ] 0.2 Confirm `command -v flock` returns non-empty on the dev host.
- [ ] 0.3 Read plan in full: `knowledge-base/project/plans/2026-05-12-feat-bg-readiness-concurrency-hardening-plan.md`.

## Phase 1 — Sub-commit 1: lock + lease + grace + push-on-create

### 1.1 Library

- [ ] 1.1.1 Create `.claude/hooks/lib/session-state.sh` with `acquire_lock`, `release_lock`, `acquire_lock_shared`, `acquire_lease`, `release_lease`, `is_lease_active`, `sweep_orphan_leases`, `_register_lease_release_trap`, `headless_or_stderr`. Adopt the canonical flock idiom from `agent-token-tee.sh:160-170` verbatim.
- [ ] 1.1.2 Hard-fail with operator-facing error if `command -v flock` returns false. Exit code 99 (matches exit-99 convention).
- [ ] 1.1.3 `mkdir -p` `LOCK_DIR` / `LEASE_DIR` / `LOG_DIR` at module load.
- [ ] 1.1.4 Implement `SOLEUR_DISABLE_SESSION_STATE=1` kill switch (no-op when set).

### 1.2 Library tests

- [ ] 1.2.1 Create `.claude/hooks/lib/session-state.test.sh` with tests T1-T8 from the plan.
- [ ] 1.2.2 Run locally: all 8 tests green.

### 1.3 worktree-manager.sh wiring

- [ ] 1.3.1 Source `lib/session-state.sh` at top of `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`.
- [ ] 1.3.2 `feature` subcommand: after `git worktree add`, call `sweep_orphan_leases`, then `acquire_lease "$branch" "${SOLEUR_SKILL_NAME:-unknown}" "${SOLEUR_EXPECTED_DURATION_MIN:-240}"`, then `git push -u origin "$branch"` with warn-only failure handling.
- [ ] 1.3.3 `cleanup_merged_worktrees`: wrap body in `acquire_lock cleanup-merged 30` with `trap 'release_lock cleanup-merged' RETURN`. Nested `acquire_lock fetch-prune 30` around the `git fetch --prune` call.
- [ ] 1.3.4 Insert lease-check + 10-min recent-commit grace + clock-skew abs guard before existing dirty-status guard in the reap loop.

### 1.4 Skill SKILL.md edits

- [ ] 1.4.1 `plugins/soleur/skills/one-shot/SKILL.md` — set `SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=240` on the worktree-manager invocation; add Phase Exit `release_lease`.
- [ ] 1.4.2 `plugins/soleur/skills/brainstorm/SKILL.md` — same pattern; `EXPECTED_DURATION_MIN=60`.
- [ ] 1.4.3 `plugins/soleur/skills/plan/SKILL.md` — same pattern; `EXPECTED_DURATION_MIN=60`.
- [ ] 1.4.4 `plugins/soleur/skills/work/SKILL.md` — same pattern; `EXPECTED_DURATION_MIN=240`.
- [ ] 1.4.5 `plugins/soleur/skills/drain-labeled-backlog/SKILL.md` — same pattern; `EXPECTED_DURATION_MIN=480`.

### 1.5 Reproducer test

- [ ] 1.5.1 Create `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` — 2026-04-21 reproducer per plan AC.
- [ ] 1.5.2 Run locally: test green.

### 1.6 Sub-commit 1 verification

- [ ] 1.6.1 Foreground UX snapshot diff: capture stdout+stderr of `bash worktree-manager.sh cleanup-merged` against a recorded `pre-change-trace.txt` baseline. Tolerate timestamp + ANSI diffs only.
- [ ] 1.6.2 Verify `git ls-remote origin <branch>` returns non-empty after `feature` invocation.
- [ ] 1.6.3 Commit with message `Ref #3690`.

## Phase 2 — Sub-commit 2: headless stderr capture

### 2.1 Hook edits

- [ ] 2.1.1 `.claude/hooks/pre-merge-rebase.sh` — source `lib/session-state.sh`; replace 4 `>&2` warns (lines 110, 137, 147, 153 — re-grep for exact lines at edit time, they drift) with `headless_or_stderr warn "<message>"`.
- [ ] 2.1.2 `.claude/hooks/lib/log-rotation.sh:159` — convert to `headless_or_stderr warn "..."`.
- [ ] 2.1.3 `.claude/hooks/lib/incidents.sh:236` — convert to `headless_or_stderr warn "..."`.

### 2.2 Verification

- [ ] 2.2.1 `bash .claude/hooks/pre-merge-rebase.test.sh` passes after refactor.
- [ ] 2.2.2 Headless reproducer: invoke pre-merge-rebase with `</dev/null > /tmp/stdout 2> /tmp/stderr` AND `CLAUDECODE=1`; assert stderr empty, log file written.
- [ ] 2.2.3 Foreground reproducer: invoke same with TTY (`script -q`); assert stderr written, log file unchanged.
- [ ] 2.2.4 Commit with message `Ref #3690`.

## Phase 3 — Sub-commit 3: skill-side merge-main lock + HEADLESS_MODE boolean + smoke

### 3.1 Merge-main lock in 4 skills

- [ ] 3.1.1 `plugins/soleur/skills/schedule/SKILL.md` — wrap `gh pr merge --auto` invocation in `acquire_lock merge-main 600` / `release_lock merge-main`.
- [ ] 3.1.2 `plugins/soleur/skills/product-roadmap/SKILL.md` — same.
- [ ] 3.1.3 `plugins/soleur/skills/ship/SKILL.md` — same.
- [ ] 3.1.4 `plugins/soleur/skills/merge-pr/SKILL.md` — same.

### 3.2 Rebase-main lock in hook

- [ ] 3.2.1 `.claude/hooks/pre-merge-rebase.sh` — wrap the `git rebase origin/main` call in `acquire_lock rebase-main 60`.

### 3.3 HEADLESS_MODE export

- [ ] 3.3.1 `.claude/hooks/session-rules-loader.sh` — add boolean `HEADLESS_MODE` export at top (after `set -e` block, before sidecar reads).

### 3.4 Tests

- [ ] 3.4.1 Create `plugins/soleur/test/concurrent-ship.test.sh` — 2 background `acquire_lock merge-main` invocations; assert serialization via timestamp file.
- [ ] 3.4.2 HEADLESS_MODE classification test: invoke `session-rules-loader.sh` with `</dev/null + CLAUDECODE=1`; assert `HEADLESS_MODE=1`. With TTY + `CLAUDECODE=1`; assert `HEADLESS_MODE=0`.
- [ ] 3.4.3 Run plan-review again on the implementation diff (not the plan) before finalizing.
- [ ] 3.4.4 Commit with message `Closes #3690`.

### 3.5 Mark PR ready

- [ ] 3.5.1 `gh pr ready 3689`.
- [ ] 3.5.2 Per `wg-after-marking-a-pr-ready-run-gh-pr-merge`: `gh pr merge --auto --squash 3689`.

## Phase 4 — Post-merge (operator)

- [ ] 4.1 Production smoke: `claude --bg /soleur:one-shot <test-issue>` 3× concurrent from one terminal. All 3 complete distinct PRs.
- [ ] 4.2 Verify `git worktree list` count equals pre-smoke count.
- [ ] 4.3 Tail `${GIT_COMMON_DIR}/soleur-logs/` and confirm structured logs are parseable.
- [ ] 4.4 Capture screen recording or terminal log for the issue.
- [ ] 4.5 Comment on #3690 with the 3 PR URLs.
- [ ] 4.6 `gh issue close 3690 --comment "smoke verified"`.
- [ ] 4.7 Run `/soleur:compound` to capture any learnings from implementation surprises.
