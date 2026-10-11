# Tasks: wire the feeder for betteruptime_heartbeat.inngest_server_probe (Ref #9703)

Plan: `knowledge-base/project/plans/2026-10-11-feat-inngest-probe-heartbeat-feeder-plan.md`
Scope of THIS pipeline run: Stage 1 (phases 0–6). Stage 2 (arming) and Stage 3 (cleanup) are NOT executed here.

## Phase 0: Credential prerequisite (GitHub write only)

- 0.1 Copy `BETTERSTACK_API_TOKEN_READONLY` from Doppler `prd_terraform` into a repo secret (value never printed); read back with `gh secret list`

## Phase 1: Verifier script (harness first)

- 1.1 Write `scripts/inngest-probe-heartbeat-feeder.test.sh` (stubbed `betterstack-query.sh` and `curl`; own cleanup trap; `MIN_PASSES` floor) and watch it fail
  - 1.1.1 Private `PATH`, strict two-shape curl stub with a refusal log; boundary pair 4500 s / 4501 s; one fixture per `host` / `host_name`; first-token role rule; doppler-quoting row; future-dated newest and the 300 s / 301 s pair; ±120 s skew; second heartbeat with the same name, prefix decoy, `paused` absent/null/string; URL shape variants
  - 1.1.2 Zero beat calls on every withheld path (observed in the stub call log); secret-sentinel assertions on stdout, stderr and argv
  - 1.1.3 Budget-inequality anchor (parses `period`/`grace` from `uptime-alerts.tf` and the slot from the table row selected by `workflowFile`)
- 1.2 Write `scripts/inngest-probe-heartbeat-feeder.sh` (`--selftest` placed before any env dependency, xtrace refusal, EXIT trap, shared-lib LOAD CONTRACT, query with helper stderr never relayed, newest-by-dt, 4500 s bound, funnel counts on every verdict line, API GET resolution with the read-only token and strict URL regex, paused path, single beat call site)
- 1.3 `bash scripts/inngest-probe-heartbeat-feeder.test.sh` green; committed scratch-copy mutation runs M1–M7 with a landing check (ported from the 8296 harness); `MIN_PASSES` floor + conservation check

## Phase 2: Workflow

- 2.1 `.github/workflows/scheduled-inngest-probe-heartbeat.yml` (`schedule */15` fallback + `workflow_dispatch: {}`, concurrency `cancel-in-progress: false`, `contents: read`, `|| rc=$?` capture, only marker-shaped lines echoed through `strip_log_injection`, Sentry `sentry-heartbeat` final step, gate-override header with the honest eligibility argument)

## Phase 3: Dispatch table row and Sentry monitor

- 3.1 `watchdog-dispatch-table.ts` row (15 min, shared-failure-domain eligibility argument)
- 3.2 `sentry-monitor-iac-parity.test.ts` expected slug set; `function-registry-count.test.ts` `NON_INNGEST_MONITORS`
- 3.3 `cron-monitors.tf` monitor (margin 60, max runtime 6); `cron-monitor-alerts.tf` unrouted entry (`#9703`)

## Phase 4: Manifest and parity tests

- 4.1 `heartbeat-manifest.ts` row flip to `kind: "cron"` + workflow evidence; keep `arming_pending`
- 4.2 Relax the evidence-shape arm in `heartbeat-reprovision-parity.test.ts` (shape-bound on file and pattern)
- 4.3 `inngest-server-probe-heartbeat.test.sh` section (h); keep `EXPECTED_PASSES` correct
- 4.4 `MUST_FIND` in `scripts/lib/inngest-probe-row.test.sh`

## Phase 5: Registration, docs, C4

- 5.1 `scripts/test-all.sh` `run_suite`; regenerate `suite-durations.tsv` / `suite-shard-legs.tsv`; baseline rows if required
- 5.2 Runbook `inngest-server.md`: watcher entry + durable arming procedure
- 5.3 ADR-117 amendment (third evidence class; never claim armed) and ADR-248 amendment (third row, +96 runs/day, re-measure queue)
- 5.4 `model.c4` edits (`inngestRedis` clause, `api -> github` third workflow, count-gate numbers), `bash scripts/regenerate-c4-model.sh`, `c4-count-parity.test.sh` numbers

## Phase 6: Verify and ship

- 6.0 Read-only soak: run the verifier every 5 minutes for 90 minutes under Monitor while the heartbeat is paused; every run `fresh_heartbeat_paused`; record the age series in the PR body
- 6.1 Targeted suites per the plan's Acceptance Criteria; `lint-guard-contract.py`; `lint-infra-no-human-steps.py --changed`
- 6.2 Confirm the diff touches no `uptime-alerts.tf`, `betterstack-logs-alerts.tf` or `apply-web-platform-infra.yml`; CI infra plan shows no heartbeat change
- 6.3 PR body: first line answers "does merging this alone mutate production?"; `Ref #9703` only; Changelog; ends with the Claude Code attribution line; commit trailer per repo convention
- 6.4 Comment on #9703: Sentry routing PR and Stage 3 remain tracked work

## Not in this run

- Stage 2 arming (Better Stack PATCH) — single trap-rolled-back compound command, authorized as a unit, see the plan's `## Arming Procedure`
- Stage 3a record PR (drop `arming_pending`) right after the read-back; Stage 3b cleanup PR after its mechanical gate: remove the #9703 directive first, delete the 8296 probe and its rows, route the Sentry monitor, close #9703 explicitly
