---
feature: feat-one-shot-9299-degraded-alert-rule
issue: 9299
pr: 9302
lane: single-domain
plan: knowledge-base/project/plans/2026-09-30-feat-inngest-provision-degraded-sentry-alert-plan.md
---

# Tasks — own Sentry alert rule for degraded inngest bootstraps (#9299)

## Phase 1: Contract test first (RED)

- [ ] 1.1 `git mv` the op-contract test to
  `apps/web-platform/test/sentry-inngest-provision-alerts-op-contract.test.ts`; widen the header
  comment and describe title to both rules; extend `stripComments` to drop `//` lines too.
- [ ] 1.2 Add rows T1b, T2b, T4c, T7b; replace T3 with the partition row (each rule's stage row
  `toEqual` one `eq` row, and the two values equal the emitted warning set); switch T8 to both
  rules' stage values; update T4b to the `eq` stage condition; T1 and T1b also assert no
  `environment =` line in either block.
- [ ] 1.3 Run the vitest file and confirm T1b and T3 are RED on the unmodified `.tf`.

## Phase 2: Rules and registries (GREEN)

- [ ] 2.1 `issue-alerts.tf`: narrow the failure rule's stage row to `eq provision_attempt_failed`,
  add `depends_on = [sentry_alert.inngest_provision_degraded]` with its two-line apply-order
  comment, rewrite its comment block.
- [ ] 2.2 `issue-alerts.tf`: append `sentry_alert.inngest_provision_degraded` (frequency 33, one
  `stage eq bootstrap_done_degraded` row, `logic_type = "all"`) with its comment block.
- [ ] 2.3 `alert-reference.json`: edit the existing stage condition; add the
  `inngest-provision-degraded` entry by copying the sibling and changing name, frequency, conditions.
- [ ] 2.4 `apps/web-platform/infra/sentry/README.md`: 39 / 39 / 37 (36 in `issue-alerts.tf`) as
  separate anchored edits across wrapped lines 5-6; add `#9299` to the PR list and the historical
  paragraph.
- [ ] 2.5 Re-run the op-contract vitest (GREEN), T25 in `sentry-monitors-audit.test.sh`,
  `terraform fmt -check`, and `terraform init -backend=false && terraform validate`.
- [ ] 2.6 Run the Guard Contract mutation matrix (M1, M2, M3, M5, M6, M10, M11, H1, H1b, H2), each restore in
  `try/finally`; record the tally for the PR body (AC2).

## Phase 3: Docs the change makes false

- [ ] 3.1 Runbook `inngest-server.md`: stages-table degraded row links the new anchor; the kept
  failure heading gains the "second email is not a duplicate" read; add a sibling
  `### Reading an inngest-provision-degraded page (#9299)` before `### Replace triggers`; throttle,
  forged-page, "To quiet it" and "Not paged by any rule" (degraded POST failure) bullets.
- [ ] 3.2 ADR-257: both `Superseded 2026-09-30 (#9176)` blockquotes, each multi-line old string
  written out exactly with its own indent.
- [ ] 3.3 `model.c4`: "35 of the 37" -> "36 of the 38"; `bash scripts/regenerate-c4-model.sh`; run
  the C4 suite.
- [ ] 3.4 Append a dated `## Update 2026-09-30 (#9299)` note to the throttle learning.
- [ ] 3.5 AC8 stale-phrase grep prints nothing; markdownlint every edited markdown file.

## Phase 4: Ship

- [ ] 4.1 Re-check `frequency_minutes = 33` is unclaimed on `origin/main` and in open PRs (AC5).
- [ ] 4.2 `soleur:ship`: PR body first line states the production effect; `Closes #9299`; decision
  challenges; apply-path note (`apply-web-platform-infra.yml` also fires, expected no-op).
- [ ] 4.3 CI green (`plan_pr`: reference gate, CREATE gate lists only the new rule, 1 add /
  1 change / 0 destroy), then admin merge.
- [ ] 4.4 Post-merge: AC-post-1 (both apply runs for the merge SHA succeed; web-platform run shows
  no change) and AC-post-2 (projection diff of both live rules vs `alert-reference.json`, read-only
  `SENTRY_ISSUE_RO_TOKEN`).
