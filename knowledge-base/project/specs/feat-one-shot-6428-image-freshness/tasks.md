---
title: "Tasks — pre-swap image freshness assertion (#6428)"
plan: knowledge-base/project/plans/2026-09-28-feat-pre-swap-image-freshness-assertion-plan.md
branch: feat-one-shot-6428-image-freshness
lane: single-domain
---

# Tasks — pre-swap image freshness assertion (#6428)

## 1. Setup
- [x] 1.1 Worktree `feat-one-shot-6428-image-freshness` off `origin/main` (ec19040203).
- [x] 1.2 Re-verify research claims against the current tree (plan §Premise Validation).

## 2. RED
- [x] 2.1 Docker mock `.Config.Env` handler before the mode case (non-inngest refs; seams `MOCK_IMAGE_BUILD_VERSION`, `MOCK_IMAGE_ENV_EXTRA`, `MOCK_IMAGE_INSPECT_FAIL`, `MOCK_FRESHNESS_INSPECT_FILE`).
- [x] 2.2 `run_6428` harness + rows F1-F9 in `ci-deploy.test.sh`; floor 342 → 355.
- [x] 2.3 Confirm F1 RED on the unmodified script (deploy reached the swap).

## 3. GREEN
- [x] 3.1 `image_freshness_event` + `verify_image_freshness` in `ci-deploy.sh`.
- [x] 3.2 Call site after the `VERIFIED_REF` block, before the stale-canary cleanup.
- [x] 3.3 Suite 355/355; `lint-shell-capture-exit` 0 new findings.

## 4. Alert IaC
- [x] 4.1 `sentry_alert.image_freshness_mismatch` (freq 28, value 0, op eq image-freshness).
- [x] 4.2 `alert-reference.json` entry.
- [x] 4.3 `sentry-image-freshness-alert-op-contract.test.ts`.

## 5. Verification
- [ ] 5.1 Mutation matrix M1-M10 each reddens a row.
- [ ] 5.2 CI green on the PR head (incl. Sentry `plan_pr` reference gate).
- [ ] 5.3 Post-merge: apply-deploy-pipeline-fix + apply-sentry-infra succeed; a web-1 deploy logs `IMAGE_FRESHNESS: ok` in Better Stack; release served.
