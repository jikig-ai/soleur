---
title: "tasks: stabilize apps/web-platform suite (#4128)"
date: 2026-05-20
issue: 4128
lane: single-domain
plan: knowledge-base/project/plans/2026-05-20-fix-web-platform-suite-flake-and-cc-persist-usage-leak-plan.md
---

# Tasks — feat-one-shot-web-platform-tests-4128

Derived from the finalized plan: [2026-05-20-fix-web-platform-suite-flake-and-cc-persist-usage-leak-plan.md](../../plans/2026-05-20-fix-web-platform-suite-flake-and-cc-persist-usage-leak-plan.md)

## 1. Setup

### 1.1. Worktree check

- 1.1.1. Confirm pwd is `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-web-platform-tests-4128`.
- 1.1.2. Confirm branch is `feat-one-shot-web-platform-tests-4128`.
- 1.1.3. Run `git status --short` — must be clean before starting (the empirical-validation patches applied during deepen-plan were reverted).

### 1.2. Baseline repro

- 1.2.1. Run `cd apps/web-platform && doppler run -p soleur -c dev -- npx vitest run test/cc-dispatcher.test.ts --reporter=basic` — expect 41/42 (T-W4-basic-off failure) confirming the deterministic class.
- 1.2.2. Run full suite once `cd apps/web-platform && doppler run -p soleur -c dev -- npm test` — expect 5-10 `Test timed out in 5000ms` failures + 1 T-W4-basic-off failure confirming the flake class. Log path: `/tmp/webplat-pre-fix.log`.

## 2. Core Implementation

### 2.1. RED — capture failing baseline

- 2.1.1. Before any edits, ensure the baseline is captured (Phase 1.2). The failing tests ARE the RED state.

### 2.2. GREEN — apply both fixes

- 2.2.1. Edit `apps/web-platform/vitest.config.ts`. Add `testTimeout: 16_000` and `hookTimeout: 20_000` at the top-level `test: {...}` block, immediately after `exclude: [...]`, BEFORE `projects: [...]`. Include the verbatim comment block from the plan's Files-to-Edit diff (citing #4128 + measured runtimes).
- 2.2.2. Edit `apps/web-platform/test/cc-dispatcher.test.ts`. Add `vi.stubEnv("CC_PERSIST_USAGE", "")` in the `beforeEach` block immediately after the existing `vi.unstubAllEnvs()` call at line 135. Include the verbatim comment block from the plan's Files-to-Edit diff (citing #4128 + Doppler-dev rationale).

### 2.3. GREEN — verify

- 2.3.1. Re-run `cd apps/web-platform && doppler run -p soleur -c dev -- npx vitest run test/cc-dispatcher.test.ts` — expect 42/42 pass.
- 2.3.2. Run `cd apps/web-platform && doppler run -p soleur -c dev -- npm test` three consecutive times. For each run, grep stderr for `Test timed out in` — must be zero occurrences in all 3 runs. Grep for `T-W4-basic-off` failures — must be zero occurrences in all 3 runs. Document each run's `Test Files ... passed` line in the PR body.
- 2.3.3. Treat any single-run ECONNREFUSED-on-127.0.0.1:3000 failure as PRE-EXISTING (per AC9). Do NOT fold it into this PR. The tracking-issue task at 2.5 handles it.

### 2.4. REFACTOR (none)

- 2.4.1. The diff is minimal-surface (~16 added lines across 2 files). No refactor needed.

### 2.5. Post-merge automation (executed at /work, not deferred to operator)

- 2.5.1. Create the ECONNREFUSED tracking issue via `gh issue create`. Body cites the 2026-05-15 learning, the deepen-plan run-2 stderr excerpt, and proposes a follow-up investigation surface (likely a Next.js dev-server-spawn race in tests that hit `127.0.0.1:3000`).
- 2.5.2. Label: `code-review` (already used for the parent #4128).

## 3. Testing & Verification

### 3.1. Test-type checks

- 3.1.1. `cd apps/web-platform && npx tsc --noEmit` — zero errors (guards against `vitest.config.ts` syntax drift since the file is TS).
- 3.1.2. `cd apps/web-platform && doppler run -p soleur -c dev -- npx vitest run test/cc-dispatcher.test.ts` — 42/42 pass (per AC4).
- 3.1.3. `cd apps/web-platform && doppler run -p soleur -c dev -- npm test` — 3 consecutive runs as described in 2.3.2.

### 3.2. Diff scope check

- 3.2.1. `git diff --name-only origin/main...HEAD` returns exactly 2 paths: `apps/web-platform/vitest.config.ts` and `apps/web-platform/test/cc-dispatcher.test.ts`.
- 3.2.2. `git diff --stat origin/main...HEAD` shows additions ≤ 25 lines total across the 2 files (per the plan's minimal-surface invariant).

### 3.3. Lifecycle gates

- 3.3.1. Compound: run `skill: soleur:compound` before commit (workflow gate `wg-before-every-commit-run-compound-skill`). Capture the new "vitest-unstub-does-not-clear-process-inherited-env-vars" learning if compound surfaces it; otherwise write it manually under `knowledge-base/project/learnings/test-failures/<topic>.md` with no hardcoded date in `tasks.md` per AGENTS.md sharp-edge.
- 3.3.2. Commit using `commit-commands:commit` skill OR a single `git commit` with `Closes #4128`.
- 3.3.3. Open PR via `gh pr create`. Body includes 3-run AC5 evidence + a `## Changelog` section.
- 3.3.4. Multi-agent review per `/soleur:review` (or post-implementation as part of one-shot).
- 3.3.5. Mark ready + auto-merge: `gh pr merge <N> --squash --auto` (per `wg-after-marking-a-pr-ready-run-gh-pr-merge`).
- 3.3.6. Poll until merged; run `cleanup-merged`.

## 4. Out of Scope (do NOT expand)

- ECONNREFUSED-on-127.0.0.1:3000 transient flake class — tracked separately via 2.5.1.
- Any non-#4128 test failure observed during AC5 runs — file as separate `code-review` issues, do NOT fold in.
- Codifying the Doppler env-leak pattern as an AGENTS.md rule — too narrow for the rule cap, captured in a learning file instead (3.3.1).
- Reverting `pool: "forks"` or `isolate: true` — both are load-bearing defenses from PR #4097; the timeout fix is ADDITIVE.

## Dependencies

None. Plan can be executed in linear sequence; no parallel paths.

## References

- Plan: [2026-05-20-fix-web-platform-suite-flake-and-cc-persist-usage-leak-plan.md](../../plans/2026-05-20-fix-web-platform-suite-flake-and-cc-persist-usage-leak-plan.md)
- Issue: https://github.com/jikigai/soleur/issues/4128
- Prior stabilization: https://github.com/jikigai/soleur/pull/4097
