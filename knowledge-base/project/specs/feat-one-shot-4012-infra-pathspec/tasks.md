---
title: "Tasks: fix(ci) infra-validation pathspec glob silently skips nested infra-only diffs"
date: 2026-05-18
branch: feat-one-shot-4012-infra-pathspec
lane: single-domain
issue: 4012
plan: knowledge-base/project/plans/2026-05-18-fix-infra-validation-pathspec-glob-plan.md
status: planned
---

# Tasks: infra-validation pathspec glob fix (#4012)

Derived from `knowledge-base/project/plans/2026-05-18-fix-infra-validation-pathspec-glob-plan.md` (deepened on 2026-05-18). Implementation order is dependency-driven: test FIRST (RED), then workflow rewrite (GREEN), then comment refactor (REFACTOR), then ship.

## Phase 0 — Preconditions

- [ ] **0.1** Verify CWD is the worktree: `cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-4012-infra-pathspec && pwd` must match exactly. (Bash CWD non-persistence guard.)
- [ ] **0.2** Re-run the reproduction at HEAD: `git diff --name-only 7e6f6726^..7e6f6726 -- 'apps/*/infra/' 'infra/'` returns empty. Confirms bug still present.
- [ ] **0.3** Pick detection form: Option A (`:(glob)apps/*/infra/**` `:(glob)infra/*/**`) OR Option B (drop pathspec, `grep -E '^(apps/[^/]+/infra|infra/[^/]+)/' | ... || true`). Default = Option B per simplicity lean; final choice reviewed by `soleur:plan-review` panel (DHH / Kieran / Simplicity).
- [ ] **0.4** Confirm test location is locked: `plugins/soleur/test/infra-validation-detect.test.sh` (only directory auto-walked by `scripts/test-all.sh`).

## Phase 1 — Implement detection-form rewrite (TDD)

### 1.1 RED — write failing test

- [ ] **1.1.1** Create `plugins/soleur/test/infra-validation-detect.test.sh` using `plugins/soleur/test/auto-close-scanner.test.sh` as the template (same `set -euo pipefail`, same `source "$SCRIPT_DIR/test-helpers.sh"`, same `assert_*` vocabulary).
- [ ] **1.1.2** Define a shell function `detect_infra_dirs()` that reads `stdin` (synthetic `git diff --name-only` output) and emits the matrix JSON. Initial body = the CURRENT broken pipeline shape (`git diff -- 'apps/*/infra/' 'infra/'` family) re-expressed to operate on stdin instead of invoking `git`.
- [ ] **1.1.3** Write seven test scenarios (numbered per AC5):
  - 1. `apps/<x>/infra/` direct child → `["apps/web-platform/infra"]`
  - 2. `apps/<x>/infra/` single-ancestor nested → `["apps/web-platform/infra"]`
  - 3. `apps/<x>/infra/` deep-nested → `["apps/web-platform/infra"]`
  - 4. `infra/<x>/` direct child → `["infra/github"]`
  - 5. `infra/<x>/` deep-nested → `["infra/github"]`
  - 6. Mixed + non-infra controls → `["apps/cla-evidence/infra","apps/web-platform/infra","infra/github"]`
  - 7. Empty / zero-match → `[]`
- [ ] **1.1.4** Run `bash plugins/soleur/test/infra-validation-detect.test.sh` — scenarios 2/3/4/5/6 FAIL (expected RED). Scenarios 1 and 7 may pass depending on the broken-pipeline shape; document the asymmetry in the test output.

### 1.2 GREEN — replace pipeline body

- [ ] **1.2.1** Update `detect_infra_dirs()` body to use the Phase 0.3 chosen form.
  - **Option A body:** `git_diff_output | grep_via_pathspec :(glob)apps/*/infra/** :(glob)infra/*/** | sed_collapse | sort_u | jq_to_array` — but since the function operates on stdin, this is `grep -E '^(apps/[^/]+/infra|infra/[^/]+)/'` (the pathspec→regex translation per learning `2026-05-09`).
  - **Option B body:** identical — `grep -E '^(apps/[^/]+/infra|infra/[^/]+)/' || true | sed -E 's|^(apps/[^/]+/infra)/.*|\1|; s|^(infra/[^/]+)/.*|\1|' | sort -u | jq -R -s -c 'split("\n") | map(select(. != ""))'`.
  - Note: the test function necessarily uses Option-B shape because it operates on stdin (no git invocation). The WORKFLOW receives the corresponding form (Option A or B) — the test's `detect_infra_dirs()` is the canonical equivalence baseline either way.
- [ ] **1.2.2** Run the test — all seven scenarios pass (GREEN).

### 1.2b GREEN equivalence check

- [ ] **1.2b.1** Run the pathspec→regex equivalence check from plan Phase 1.2b on commit `7e6f6726`:
  ```bash
  EXPECTED=$(git diff --name-only 7e6f6726^..7e6f6726 | grep -E '^(apps/[^/]+/infra|infra/[^/]+)/' | sed -E 's|^(apps/[^/]+/infra)/.*|\1|; s|^(infra/[^/]+)/.*|\1|' | sort -u)
  ACTUAL=$(git diff --name-only 7e6f6726^..7e6f6726 | detect_infra_dirs)
  diff -u <(echo "$EXPECTED") <(echo "$ACTUAL")
  ```
- [ ] **1.2b.2** Both ACTUAL and EXPECTED resolve to `apps/web-platform/infra`. Exit 0.

### 1.3 REFACTOR — update workflow and comments

- [ ] **1.3.1** Edit `.github/workflows/infra-validation.yml` lines 41-57. Replace the `git diff --name-only -- 'apps/*/infra/' 'infra/' | sed ... | sort -u | jq ...` one-liner with the byte-identical-to-test `detect_infra_dirs()` shape (whether inlined in `run:` or extracted to a small helper — implementer choice; Phase 0.3 form decides).
- [ ] **1.3.2** Rewrite the comment block at lines 41-47 to describe the new detection form. Preserve load-bearing claims: "two pathspec families covered", "sed anchors on the single-ancestor directory", "deep-nested paths collapse correctly".
- [ ] **1.3.3** Run `actionlint .github/workflows/infra-validation.yml` — clean.
- [ ] **1.3.4** Extract the `run:` block's shell body to a temp file (`mktemp` + write the run-body) and run `bash -n` on the temp file. Clean (per the YAML-as-bash parse-error learning).

## Phase 2 — Wire and verify locally

- [ ] **2.1** Run `bun run test` — confirm output contains `--- plugins/soleur/test/infra-validation-detect.test.sh ---` followed by `[ok]`.
- [ ] **2.2** Run `bash plugins/soleur/test/infra-validation-detect.test.sh` standalone — passes.
- [ ] **2.3** Run `actionlint .github/workflows/infra-validation.yml` — clean.

## Phase 3 — PR-body evidence

- [ ] **3.1** Capture the BEFORE reproduction: `git diff --name-only 7e6f6726^..7e6f6726 -- 'apps/*/infra/' 'infra/'` (empty).
- [ ] **3.2** Capture the AFTER reproduction: same `git diff` with the new pathspec form (returns 2 files).
- [ ] **3.3** Capture the Option B collapse pipeline output (returns `["apps/web-platform/infra"]`).
- [ ] **3.4** Paste all three blocks into the PR body's "Verification Replay" section so a reviewer can replay in 10 seconds.

## Phase 4 — Ship

- [ ] **4.1** Commit. Conventional commit message:
  ```
  fix(ci): infra-validation pathspec glob silently skips nested infra-only diffs (#4012)
  ```
- [ ] **4.2** Push to `feat-one-shot-4012-infra-pathspec`.
- [ ] **4.3** Open PR with `Closes #4012` in body (NOT title — per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] **4.4** Multi-agent plan-review (DHH / Kieran / Simplicity / pattern-recognition / architecture-strategist) — typically inline at `soleur:work` via `soleur:plan-review` step.
- [ ] **4.5** Merge via `gh pr merge --squash --auto`.

## Phase 5 — Post-merge verification (operator)

- [ ] **5.1** Wait for the next infra-touching PR on `main` (or for `apply-deploy-pipeline-fix.yml` / `apply-sentry-infra.yml` to trigger a follow-up infra edit). When it opens:
  ```bash
  gh run list --workflow=infra-validation.yml --limit 5 --json status,conclusion,event,headBranch,databaseId
  gh run view <id> --json jobs | jq -r '.jobs[].name'
  ```
- [ ] **5.2** Confirm `validate (apps/web-platform/infra)` (or sibling) appears in the job list — NOT skipped. If skipped, re-open #4012 with the failing PR number and the empty matrix output as evidence.
- [ ] **5.3** Issue #4012 auto-closes on merge (handled by `Closes #4012`).

## Compound learning capture (post-merge)

- [ ] **6.1** Write a learning file under `knowledge-base/project/learnings/integration-issues/` capturing: (a) git pathspec `*` does not cross `/` (trailing-slash form is single-component); (b) `:(glob)` magic OR a shell-level `grep -E` filter are the two safe forms; (c) matrix-zero in GitHub Actions returns `success` and hides this defect — always wire a fixture test for any pathspec-driven matrix detection; (d) sibling class to lefthook gobwas-glob `**` (learning `2026-03-21-lefthook-gobwas-glob-double-star.md`). Filename: directory + descriptive slug only — date is picked at write-time. Cross-link from `2026-03-21-lefthook-gobwas-glob-double-star.md` if appropriate.
