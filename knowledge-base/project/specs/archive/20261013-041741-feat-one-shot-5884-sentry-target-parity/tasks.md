---
title: Tasks — Extend terraform -target parity guard to cover apply-sentry-infra.yml
issue: 5884
branch: feat-one-shot-5884-sentry-target-parity
lane: single-domain
plan: knowledge-base/project/plans/2026-07-02-chore-extend-terraform-target-parity-sentry-plan.md
---

# Tasks — #5884 Sentry `-target` parity guard

Derived from `2026-07-02-chore-extend-terraform-target-parity-sentry-plan.md`.
Note: no `spec.md` exists for this branch; lane classified `single-domain`
(unambiguous engineering test-infra change).

## Phase 1 — RED: Sentry parity describe block (test first)

- [x] 1.1 In `plugins/soleur/test/terraform-target-parity.test.ts`, add module-scope
      constants `SENTRY_INFRA_DIR`, `SENTRY_WORKFLOW`, `SENTRY_MIN_RESOURCES` (60), and
      the frozen `SENTRY_IMPORT_ONLY_EXCLUSIONS` set (the 4 `auth_*` placeholder addresses).
- [x] 1.2 Add `listSentryTfFiles()` walker over `SENTRY_INFRA_DIR` (`*.tf`, sorted).
- [x] 1.3 Add the `describe("terraform -target parity — Sentry infra … (#5884)")` block
      reusing `stripComments` / `extractAllResources` (filtered to `sentry_` prefix) /
      `extractAllTargets`, with tests: non-vacuity floor, parity (`uncovered === []`),
      #5875 regression anchor, import-only-excluded assertion, synthetic-miss non-vacuity.
- [x] 1.4 Run `bun test plugins/soleur/test/terraform-target-parity.test.ts` from the
      **worktree** path — confirm the parity test FAILS reporting
      `["sentry_issue_alert.github_webhook_founder_ambiguous"]` (RED).

## Phase 2 — GREEN: register the missing apply-created alert

- [x] 2.1 Re-grep `-target=sentry_issue_alert.sandbox_startup_failure` + `-no-color` in
      `.github/workflows/apply-sentry-infra.yml` to locate the insertion point (don't
      trust line numbers).
- [x] 2.2 Insert `-target=sentry_issue_alert.github_webhook_founder_ambiguous \` inside
      the backslash-continued `terraform plan` command, before `-no-color` (no adjacent
      comment — mid-continuation comment → exit 127).
- [x] 2.3 Verify the `terraform apply` step reuses saved `tfplan` (does not re-declare
      its own `-target` list); if it does, add the same line there.
- [x] 2.4 Re-run the test → all Sentry-block tests GREEN.

## Phase 3 — Regression + docs

- [x] 3.1 Run the full `terraform-target-parity.test.ts` suite + broader plugin bun-test
      surface; confirm no sibling regression.
- [ ] 3.2 PR body: `## Changelog` + `semver:patch` + `Closes #5884` + note the guard
      surfaced & fixed a live inert alert (`github_webhook_founder_ambiguous`).

## Post-merge (automatable, no SSH)

- [ ] P.1 Confirm the new bun test is green in CI (`ci.yml` / `infra-validation.yml`).
- [ ] P.2 Confirm `github_webhook_founder_ambiguous` is a live Sentry rule via
      `bash apps/web-platform/scripts/sentry-monitors-audit.sh` (read-only) or Sentry
      API; if the apply didn't auto-fire, `gh workflow run apply-sentry-infra.yml`.

## Acceptance Criteria (see plan for full list)

- Sentry parity test returns `[]` uncovered; ≥ 5 assertions in the #5884 block.
- `github_webhook_founder_ambiguous` `-target` line present exactly once, in the plan block.
- `SENTRY_IMPORT_ONLY_EXCLUSIONS` = exactly the 4 `auth_*` names, documented frozen.
- Synthetic-fixture non-vacuity + #5875 regression anchor pass.
