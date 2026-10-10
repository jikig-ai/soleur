# Tasks: feat-one-shot-7256-slack-on-blocked-zot-mirror (#7256)

Plan: `knowledge-base/project/plans/2026-10-09-fix-slack-on-blocked-release-plan.md`

## Phase 1: Tests first (RED)

- [x] 1.1 In `plugins/soleur/test/reusable-release-idempotency.test.sh`, make `WF` overridable via `REUSABLE_RELEASE_WF` (test-only hook, comment it).
- [x] 1.2 Add a `python3 -I` PyYAML helper: load `$WF`, look up a step by exact name, print `if` (whitespace-collapsed), `env.<KEY>`, `continue-on-error`, `run`, and the census of steps referencing `secrets.SLACK_RELEASES_WEBHOOK_URL`; missing step or YAML error is an explicit FAIL.
- [x] 1.3 T6b: success-gate equality, blocked-gate equality (derived from the success literal), failure-email equality, census of exactly two steps plus blocked `continue-on-error` True, env-wiring equality for MIRROR_REASON, TOKEN_VERDICT, TAG, VERSION and the webhook secret.
- [x] 1.4 T7b: run the parsed blocked `run:` under the curl stub (`bash -eo pipefail`) with sentinels `zz_stage_7256` / `zz_verdict_7256`: empty webhook, full payload, plugin case (both empty, registry lines suppressed), one-var case (fallback renders), `& < >` escaped, curl failure keeps rc 0, never contains `released!`.
- [x] 1.5 Update the test header comment to mention #7256; confirm the new assertions fail (RED).

## Phase 2: Workflow, comments, ADR (GREEN)

- [x] 2.1 Insert `Post to Slack (release BLOCKED)` in `.github/workflows/reusable-release.yml` after the success Slack step and before the "CARRY THIS JOB'S OUTPUT VALUES" comment block, with the lead comment (sibling rationale, `notify-gated` duplicate, #7256).
- [x] 2.2 Rewrite the success step's `CORRECTED 2026-07-30` env paragraph (mark `CORRECTED 2026-10-09 (#7256)`) and shrink the run-block `NARROWER than it used to` comment to a pointer; no change to the success step's `if:`, env assignments or code.
- [x] 2.3 Append the one-sentence `AMENDED 2026-10-09 (#7256)` clause to the ADR-096 "AMENDED 2026-07-30" bullet.
- [x] 2.4 Run the idempotency suite (GREEN, REUSABLE_RELEASE_WF unset), `actionlint` (nothing new vs origin/main), `python3 scripts/lint-workflow-step-env-refs.py`, `shellcheck` over the new run block. Do not run the broad battery.

## Phase 3: Mutation proof (against a copy via REUSABLE_RELEASE_WF)

- [x] 3.1 Guard 1 rows 1-10 each RED; H1 RED; H2 GREEN. Note outcomes for the PR body.
- [x] 3.2 `git grep -n "does not run at all" -- .github/workflows/reusable-release.yml` returns nothing.
- [x] 3.3 Diff-scope check: no file outside the allowlist; none of the forbidden registry/inngest/skills paths.

## Phase 4: Ship

- [ ] 4.1 PR body: `Closes #7256` on its own line, mutation table, brand-survival `none` reason, disclosed `notify-gated`/`release-outcome` duplicate, normal merge queue (no agent admin-merge path).
