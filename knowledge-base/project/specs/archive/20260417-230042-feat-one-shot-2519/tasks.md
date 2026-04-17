# Tasks — feat-one-shot-2519

**Plan:** `knowledge-base/project/plans/2026-04-17-fix-verify-deploy-step-timeout-plan.md`
**Issue:** #2519
**Branch:** `feat-one-shot-2519`

## 1. Setup

- 1.1 Confirm working directory: `.worktrees/feat-one-shot-2519/`.
- 1.2 Re-read `.github/workflows/web-platform-release.yml:100-102` to confirm current values before editing.

## 2. Core Implementation

- 2.1 Edit `.github/workflows/web-platform-release.yml`:
  - 2.1.1 Update the comment above the env vars to reference `#2519`, document raising the ceiling from 120s to 300s, and note alignment with the downstream health-check step's 300s window.
  - 2.1.2 Change `STATUS_POLL_MAX_ATTEMPTS: 24` to `STATUS_POLL_MAX_ATTEMPTS: 60`.
  - 2.1.3 Leave `STATUS_POLL_INTERVAL_S: 5` unchanged (preserves fail-fast granularity for early non-zero exits).

## 3. Validation

- 3.1 Run `actionlint` on the workflow file (lefthook pre-push enforces this automatically; also run it explicitly before commit).
- 3.2 If `yamllint` is configured in lefthook, confirm it passes.
- 3.3 Confirm the error message at line 162 still renders correctly — it already uses `$((STATUS_POLL_MAX_ATTEMPTS * STATUS_POLL_INTERVAL_S))` and will auto-update from "120s" to "300s" with no code edit.
- 3.4 No unit tests added (infrastructure-only change — exempt from TDD gate per AGENTS.md `cq-write-failing-tests-before`).

## 4. Ship

- 4.1 Commit with message including `Closes #2519` in the PR body (per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`).
- 4.2 Apply labels: `type/bug`, `priority/p2-medium`.
- 4.3 Open PR; run review, QA (N/A — no UI), compound, ship pipeline.

## 5. Post-Merge Verification (per AGENTS.md `wg-after-a-pr-merges-to-main-verify-all`)

- 5.1 Watch the release workflow run triggered by the merge of this PR.
- 5.2 Confirm the `Verify deploy script completion` step exits 0 with `ci-deploy.sh completed successfully for v$VERSION` within the new 300s ceiling.
- 5.3 Confirm the downstream `Verify deploy health and version` step also passes (sanity check, unrelated to this change).
- 5.4 If the next organic release doesn't happen within a reasonable window, do NOT trigger `gh workflow run web-platform-release.yml` synthetically — this workflow requires real release inputs. Instead, rely on the first natural trigger and note the PR's outcome at that point.
