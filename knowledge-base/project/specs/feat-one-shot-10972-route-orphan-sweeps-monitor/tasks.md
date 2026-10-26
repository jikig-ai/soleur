# Tasks: route the scheduled-orphan-sweeps Sentry monitor (#10972)

Plan: `knowledge-base/project/plans/2026-10-26-chore-route-orphan-sweeps-sentry-monitor-plan.md`. Draft PR: #11154. PR body uses `Ref #10972`, `Ref #9927`, `Ref #10112` only.

## Phase 1 - Route the monitor (tests first)

- 1.1 Run the routing-parity suite for a baseline: `cd apps/web-platform && npx vitest run test/server/inngest/sentry-cron-monitor-routing-parity.test.ts` (24 of 24 at plan time).
- 1.2 In `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`: delete the `scheduled_orphan_sweeps` entry and its comment block from `local.cron_monitor_alert_unrouted` (3 entries remain).
- 1.3 Insert `sentry_cron_monitor.scheduled_orphan_sweeps.id,` into `monitor_ids` between `scheduled_oauth_probe` and `scheduled_plausible_goals` (63 to 64 elements).
- 1.4 In `cron-monitors.tf`: update the comment above `resource "sentry_cron_monitor" "scheduled_orphan_sweeps"` to the routed state.
- 1.5 Verify: parity suite 24 of 24, `terraform fmt -check -recursive apps/web-platform/infra/sentry`, `bash plugins/soleur/test/c4-count-parity.test.sh`.

## Phase 2 - alert-reference.json from the CI artifact

- 2.1 Commit Phase 1 alone, push, let `plan_pr` of `apply-sentry-infra.yml` run (reference gate red once is expected).
- 2.2 `gh run download <run-id> -n sentry-alert-reference-expected-<run-id>` into the scratch directory; compare with `jq` (print counts and booleans only): exactly one added id in `cron-monitor-failure.detectorIds`.
- 2.3 Copy over `apps/web-platform/infra/sentry/alert-reference.json`, commit separately, push, wait for the reference gate to go green.
- 2.4 Invariants: canonical (`jq -S . f | diff -q - f`), `detectorIds` sorted, count 64.
- 2.5 If the artifact is absent: stop with `Blocked: detector id needs a Sentry token read` (the apply forensics artifact exists only for failed applies, so there is no fallback).

## Phase 3 - Follow-through probe and enrollment

- 3.1 (RED) Write `scripts/followthroughs/orphan-sweeps-relook-10972.test.sh` first: the 14 matrix rows (clean 0; empty 3; missed 1; timeout plus a second bad row 1; error 1; bad row after the pinned end 0; truncation 3; non-array 3; ok-count floor 28 -> 27 rows 3; pin violation 3; token unusable 3; xtrace 78; run before NOT_BEFORE 2; 401 fixture with a token-shaped body prints nothing from the body 3), the harness and boundary rows (in_progress ignored; exactly 100 rows with the oldest before the window start passes the guard), and a nonzero executed-row count assertion.
- 3.2 (GREEN) Write `scripts/followthroughs/orphan-sweeps-relook-10972.sh` as a delta on `community-monitor-checkin-soak-5728.sh`: slug `scheduled-orphan-sweeps`, `per_page=100`, window literals 2026-10-26T06:00:00Z to 2026-11-09T06:00:00Z plus `NOT_BEFORE` = the window end (exit 2 before it), `--max-time 30 --proto '=https'`, no response body in any output, exit 1 on missed/timeout/error, exit 0 only with no bad row and ok count >= 28, exit 3 for read/integrity failures, exit 78 under xtrace. Header: credential posture, permanence of exit 1, `RETIREMENT:` line (suite, `run_suite` line, four manifest files, audit-baseline row if any, the `follow-through` label on #10972).
- 3.3 `shellcheck` both scripts; run `scripts/lint-followthrough-varq-ban.sh`, `scripts/lint-shell-trace-credential-refusal.py`, `scripts/lint-orphan-test-suites.sh`; add the `run_suite` line to `scripts/test-all.sh`; `python3 scripts/regenerate-shard-manifest.py --incremental --write`.
- 3.4 Dry-run on real data with a throwaway scratch tracker (label `follow-through`, same `script=` and `secrets=`, `earliest=<now>`): `gh workflow run scheduled-followthrough-sweeper.yml --ref feat-one-shot-10972-route-orphan-sweeps-monitor -f dry_run=true`; read the scratch tracker's `exit=` line and tail; confirm `per_page=100` behaviour and row count; close the scratch issue.
- 3.5 Enroll #10972 at Phase 6 step 6 (after both slots read ok, right before arming the merge): label `follow-through` plus the unfenced directive (`earliest=2026-11-09T00:00:00Z`, `secrets=SENTRY_ACTIONS_RO_TOKEN`). Use the convention's untracked main-checkout copy only if the directive gate says the script does not exist, then remove it.
- 3.6 File the deferral issue for the two stale "unrouted until #10972" comments in `scheduled-terraform-drift.yml` (milestone Post-MVP / Later; trigger: next real edit to that workflow; anchor: "its Sentry monitor is unrouted until").

## Phase 4 - Prose

- 4.1 `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`: orphan-sweeps paragraph and the "once routed" triage row to the routed state, dated 2026-10-26. ADR-241 is not edited.

## Phase 5 - Gate, review, PR body

- 5.1 Local affected gate (`plugins/soleur/scripts/affected-tests.sh`) to rc 0; rc 6 is not a pass.
- 5.2 `soleur:review`.
- 5.3 PR body with dated "Measured" and "Not measured" lists; infra-validation red on main noted as unrelated.
- 5.4 Do not sync a BEHIND queue PR by hand; `plugins/soleur/scripts/ci-head-verdict.sh verdict 11154`.

## Phase 6 - Time-gated merge gate (hold ready and merge)

- 6.0 Before ending this run: post ONE state record on draft PR #11154 (branch, Phase 1/2 commit SHAs, plan_pr run ids and headSha, scratch issue number and any untracked-copy path, evidence so far, "waiting on slots 2026-10-26T18:00Z and 2026-10-27T06:00Z"); arm one-time wakes (about 18:05Z and 06:05Z) if the harness offers a scheduler; emit the end-of-work resume prompt; put the post-merge checklist in the PR body.
- 6.0b Authenticate each slot run (head branch main, workflow path, the dispatcher login seen on run 40277293413, start within about 15 minutes of the slot, head SHA an ancestor of origin/main); every authentic run in the window must pass; post each slot's run id and read lines on #11154.
- 6.1 After 2026-10-26T18:00Z: `gh run list --workflow scheduled-terraform-drift.yml --created ">=2026-10-26T17:30:00Z" ...`; every `*-orphan-sweep` job `success`, aggregator check-in step `success`, aggregator email step `skipped`; log lines `STATUS: ok` and `sentry-heartbeat: http_code=202`.
- 6.2 After 2026-10-27T06:00Z: same reads for that slot.
- 6.3 Any miss (slot B is a hard gate): stop, do not mark ready, report `Blocked: <reason>` and post it on #11154 and #10972.
- 6.4 Both ok: pre-ready sync check (diff origin/main for the Sentry tree and the projection jq since the last push; if changed, merge main in, re-derive the sorted position, push, wait for plan_pr green), enroll #10972, mark ready, arm the merge through the queue (no hand sync of a queued PR).

## Phase 7 - Post-merge read-back

- 7.1 Merge SHA from `gh pr view 11154 --json mergeCommit`; earliest push-event apply run on main containing it (a cancelled run: read its successor; no run: look for `[skip-sentry-apply]`); bounded `Monitor` wait if running; match the fidelity step by prefix; judge by step conclusions: `Terraform apply` `success` and `sentry_alert live fidelity` `success` (not `skipped`). Otherwise `Blocked: apply did not converge`, no hand apply.
- 7.2 Comment on #10972 with the measured facts and dates; leave it open for the sweeper.
