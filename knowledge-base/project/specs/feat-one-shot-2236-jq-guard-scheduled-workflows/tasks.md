# Tasks: fix(ci) jq -e guard on scheduled LinkedIn and CF token checks

**Issue:** #2236
**Plan:** `knowledge-base/project/plans/2026-04-15-fix-ci-jq-guard-scheduled-workflows-plan.md`
**Branch:** `feat-one-shot-2236-jq-guard-scheduled-workflows`

## Phase 1: Setup

- [x] 1.1 Read issue #2236 and PR #2226 canonical pattern.
- [x] 1.2 Read both affected workflow files and identify injection points.
- [x] 1.3 Verify `actionlint` is installed (`/home/jean/.local/bin/actionlint` v1.7.7).
- [x] 1.4 Confirm worktree + branch are correct.

## Phase 2: Core Implementation

- [ ] 2.1 Edit `.github/workflows/scheduled-linkedin-token-check.yml`:
  - [ ] 2.1.1 Insert `jq -e . /tmp/li-response.json` guard between the HTTP 2xx block and the `$(jq -r '.name // "unknown"' ...)` call (around line 92-93).
  - [ ] 2.1.2 Warning log mentions "LinkedIn API returned non-JSON body on HTTP $HTTP_CODE".
  - [ ] 2.1.3 Guard body uses `exit 0` (single-shot, not a retry loop).
  - [ ] 2.1.4 Comment references AGENTS.md rule `cq-ci-steps-polling-json-endpoints-under` and issues `#2214, #2236`.
- [ ] 2.2 Edit `.github/workflows/scheduled-cf-token-expiry-check.yml`:
  - [ ] 2.2.1 Insert `jq -e . "$TMPFILE"` guard between the HTTP 2xx block and the `EXPIRES_AT=$(jq -r ...)` call (around line 61-64).
  - [ ] 2.2.2 Warning log mentions "Cloudflare API returned non-JSON body on HTTP $HTTP_CODE".
  - [ ] 2.2.3 Guard body uses `exit 0`.
  - [ ] 2.2.4 Comment references AGENTS.md rule + issues.

## Phase 3: Local Validation

- [ ] 3.1 Run `actionlint .github/workflows/scheduled-linkedin-token-check.yml` — must be clean.
- [ ] 3.2 Run `actionlint .github/workflows/scheduled-cf-token-expiry-check.yml` — must be clean.
- [ ] 3.3 Execute the 5 shell sanity cases from plan §Test Scenarios 2 (valid JSON, HTML, plaintext, null, empty) — all 5 must print their pass line.
- [ ] 3.4 Re-read both workflow files after editing to verify intended diffs (no stray whitespace, guard placed correctly).

## Phase 4: Commit & Push

- [ ] 4.1 Run `skill: soleur:compound` (per AGENTS.md `wg-before-every-commit-run-compound-skill`).
- [ ] 4.2 Stage changes: `git add .github/workflows/scheduled-linkedin-token-check.yml .github/workflows/scheduled-cf-token-expiry-check.yml`.
- [ ] 4.3 Commit: `fix(ci): guard jq -e on scheduled linkedin/cf token checks`. Body should reference `#2214` and `Closes #2236`.
- [ ] 4.4 Push branch.

## Phase 5: End-to-End Verification

- [ ] 5.1 `gh workflow run scheduled-linkedin-token-check.yml --ref feat-one-shot-2236-jq-guard-scheduled-workflows`.
- [ ] 5.2 `gh workflow run scheduled-cf-token-expiry-check.yml --ref feat-one-shot-2236-jq-guard-scheduled-workflows`.
- [ ] 5.3 Poll both runs via Monitor tool until complete. Both must conclude `success`.
- [ ] 5.4 Neither run should create a spurious action-required issue.

## Phase 6: Review & Ship

- [ ] 6.1 Run `skill: soleur:plan-review` on the plan file (pre-push already done during plan skill — re-run only if plan changes).
- [ ] 6.2 Push + spawn review agents (DHH, Kieran, simplicity) per `rf-before-spawning-review-agents-push-the`.
- [ ] 6.3 Address review findings inline.
- [ ] 6.4 Run `skill: soleur:ship` (handles compound, semver label, PR body with `Closes #2236`).

## Phase 7: Post-Merge

- [ ] 7.1 Run `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`.
- [ ] 7.2 Dispatch both workflows on `main` (per `wg-after-merging-a-pr-that-adds-or-modifies`); verify green.
- [ ] 7.3 Confirm issue #2236 auto-closed.
