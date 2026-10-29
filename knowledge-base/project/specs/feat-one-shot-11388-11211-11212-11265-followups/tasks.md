# Tasks: four follow-ups (11388, 11212, 11211, 11265)

Plan: `knowledge-base/project/plans/2026-10-29-chore-alert-guard-structural-enumeration-pill-deletion-sweeper-luks-keeper-plan.md`
Decisions: `knowledge-base/project/specs/feat-one-shot-11388-11211-11212-11265-followups/decision-challenges.md`

Order inside each phase: tests first (`cq-write-failing-tests-before`).

## Phase 1 - 11388 alert-guard structural enumeration

- 1.1 Write the mutation matrix (Guard 1) as test cases in `apps/web-platform/infra/betterstack-alert-structure.test.sh` before the presence rows
  - 1.1.1 Copy `ok()`/`no()`/`assert_fixture_dir()`/instrument self-test and `mutate_red` shape from `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh`
  - 1.1.2 Source `tests/scripts/lib/hcl-effective-text.sh` from the repo root; add a `--presence-only` argument that skips the battery
- 1.2 Implement `logtail_blocks()` (strip_comments + blank_heredocs + block_of over every `*.tf` in the infra root)
- 1.3 Presence rows: census floor (19), closed attribute set (`REQUIRED_ATTRS` / `OPTIONAL_ATTRS`), no meta-arguments, one alert per exploration and name equality, no removed/moved/import naming a `logtail_` address, no override or `*.tf.json` files, provider constraint and lock-version tripwire, CI invocation pin for `apps/web-platform/test/infra/*alert*.test.sh`
- 1.4 Battery rows 1 to 12 plus harness rows (instrument self-test, neutered `strip_comments`, must-PASS non-canonical trees); instrument control on the pristine tree first
- 1.5 Regenerate the shard manifest: `python3 scripts/regenerate-shard-manifest.py --group infra --incremental --write`
- 1.6 Edit `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh`: widen census stem, add `probe2_fail` mutation row, add check_period/narrowing row, bump `PRESENCE_ROWS` / `MUT_ROWS`
- 1.7 Docs: reword the stale clause in `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`; document auto-resolve window in the runbook and as a comment in `apps/web-platform/infra/betterstack-logs-alerts.tf` (comment only)

## Phase 2 - 11212 dead pill variant

- 2.1 Create `apps/web-platform/test/components/acknowledged-pill.test.tsx` (derivePillState table, three renders, `@ts-expect-error` for `enqueue_failed`); confirm `./node_modules/.bin/tsc --noEmit` is red before the edit
- 2.2 Edit `apps/web-platform/components/dashboard/acknowledged-pill.tsx` (remove `queued`, `enqueue_failed`, the precedence comment)
- 2.3 Commit `knowledge-base/product/design/dashboard/acknowledged-pill-states.pen` and `.../screenshots/acknowledged-pill-states.png`
- 2.4 Comment on tracker 11486 about the stale Article 30 register row (g)(6) (legal record, counsel path)

## Phase 3 - 11211 self-reporting probe

- 3.1 Create `scripts/followthroughs/dispatch-recovery-sweeper-11211.test.sh` (PATH-stub curl; exit codes only 2/3/5/78)
- 3.2 Create `scripts/followthroughs/dispatch-recovery-sweeper-11211.sh` (Sentry + Supabase read-only; two buckets; header with contract, credential posture, RETIREMENT)
- 3.3 Register the suite in `scripts/test-all.sh` with a `run_suite` line
- 3.4 Ship-time, GitHub only: directive + `follow-through` label + evidence comment on 11211 (stays open)

## Phase 4 - 11265 dark-probe trigger and ADR

- 4.1 Create `scripts/followthroughs/inngest-luks-keeper-dark-11265.test.sh`, then `scripts/followthroughs/inngest-luks-keeper-dark-11265.sh` (measured rows only, 30-day threshold, 60-day look-back, exit 2/3/5/78)
- 4.2 Register the suite in `scripts/test-all.sh`
- 4.3 Append the dated addendum to `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` (no new ordinal); add the dark-probe pointer to the `Key-continuity probe (#9927 item 2)` subsection of `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` keeping the heading text
- 4.4 Ship-time, GitHub only: directive (`earliest=2026-11-29T00:00:00Z`) + `follow-through` label + comment of what remains (items a to f) on 11265 (stays open, `Ref` only)

## Phase 5 - verify and hand off

- 5.1 Run the plan's Acceptance Criteria commands; `python3 scripts/lint-guard-contract.py`; `bash plugins/soleur/test/c4-count-parity.test.sh`
- 5.2 Confirm the diff leaves `cloud-init-inngest.yml`, `inngest-cutover-flip.sh`, `inngest-host.tf`, all workflows and the lock file untouched
- 5.3 PR body: `Closes #11388`, `Closes #11212`, `Ref #11211`, `Ref #11265`, `Ref #11486`; no `Closes` for 11211 or 11265
