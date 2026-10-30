# Tasks — fix-observable-deadman-11631 (Ref #11631)

Plan: `knowledge-base/project/plans/2026-10-30-fix-deadman-heartbeats-fed-from-archive-plan.md`

Constraints for every task: one PR; do not merge; do not arm auto-merge; do not unpause heartbeats, resolve Better Stack
incidents, dispatch any workflow, or make any Hetzner/Doppler/Better Stack write; PR body uses `Ref #11631`.

## Phase 0 — Read-only measurement (skip with a recorded reason if no read credential)

- 0.1 HARD GATE: run each target's SQL (single-quoted) through `scripts/betterstack-query.sh`; expect `n >= 1`; capture the
  real one-line answer shapes (incl. empty window) as suite fixtures; cite the `host_name` / `_SYSTEMD_UNIT` writers. If
  not runnable: PR body says "predicate UNPROVEN against live" and the PR stays draft.
- 0.2 Measure archive freshness lag (`now() - max(dt)` over the `s3Cluster` arm); widen grace only if lag > 2 h.
- 0.3 Record 27 h archive-scan latency; add an implied `raw LIKE` pre-filter only if > 30 s.
- 0.4 Re-measure watchdog `workflow_dispatch` gaps + queue; widen luks grace to 7200 only if beat-to-beat max > 6500 s.
- 0.5 One-time verbatim-move check of each predicate against the deleted locals; record in the PR body.

## Phase 1 — RED first

- 1.1 Write `apps/web-platform/test/infra/deadman-heartbeat-feeder.test.sh` (fake tree, private PATH, stub curl, python
  SQL-subset evaluator stub for `betterstack-query.sh`, synthesized fixtures only).
  - 1.1.1 Fixtures: luks 26 h beats / 28 h withholds / empty / web-2 / verify-job row without `_SYSTEMD_UNIT` / future-dated / FAIL row.
  - 1.1.2 Fixtures: cost 20 h beats / 26 h withholds / null cost / `_DAILY` / BYOK / credit-probe arm.
  - 1.1.3 SQL pins: `s3Cluster`, `_row_type = 1`, both-arm window, never `--no-archive`; no `/fail`; single `curl` beat site.
  - 1.1.4 Heartbeat faults, hygiene (xtrace 78, seam in CI, trap remap), predicate and emitter pins moved from the retired alert tests.
  - 1.1.5 Guard 3 sentinel (no alert above 900 s; allowlist `claude_cost_daily_burn`, `inngest_luks_wrong_volume`) and Guard 4 wiring parity.
  - 1.1.6 Mutation battery (Guards 1-4) with landing assertions and must-PASS rows.
- 1.2 Confirm RED for the right reason (feeder missing).

## Phase 2 — Feeder, workflow, Sentry monitor, watchdog row

- 2.1 `scripts/deadman-heartbeat-feeder.sh <target> | --selftest` (target table, raw SQL, `stale_row` second chokepoint,
  exact-name heartbeat lookup, single `beat_once`, EXIT-trap contract).
- 2.2 `.github/workflows/scheduled-deadman-heartbeat-feeder.yml` (gate-override header, triggers exactly schedule + dispatch,
  concurrency group, loop over both targets, marker-line discipline, `sentry-heartbeat` step).
- 2.3 `apps/web-platform/infra/sentry/cron-monitors.tf` monitor + `cron-monitor-alerts.tf` unrouted label.
- 2.4 `apps/web-platform/server/watchdog-dispatch-table.ts` row (CTO-ruled) + `sentry-monitor-iac-parity.test.ts` slug set.
- 2.5 `.github/workflows/infra-validation.yml` steps (feeder suite, ceiling sentinel) and `paths:` entries.
- 2.5.1 `function-registry-count.test.ts` `NON_INNGEST_MONITORS`; `sentry-monitors-audit.test.sh` / `.sh` / `sentry/README.md`
  monitor count 25 -> 26; `scripts/lib/test-affected-paths.sh` `AFFECTED_*` array.
- 2.5.2 `apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh` (Guard 3; comment/heredoc-lexed parser).
- 2.6 Feeder suite GREEN.

## Phase 3 — Terraform, apply targets, census

- 3.1 `uptime-alerts.tf`: two heartbeats (copy of `inngest_server_probe`).
- 3.2 `betterstack-logs-alerts.tf`: delete the four resources, three locals, #8706 section comment; touch two comment lines only.
- 3.3 `apply-web-platform-infra.yml`: keep four destroy `-target`s, add two heartbeat `-target`s.
- 3.4 `tests/scripts/test-infra-privileged-tier-census.sh`: `INTENDED_DESTROYS` rows (`#11631`).
- 3.5 `workspaces-luks.tf` comment at ~229.
- 3.6 `terraform fmt -check` and `terraform validate`.

## Phase 4 — Manifest and test rewrites

- 4.1 `heartbeat-manifest.ts`: two rows with `arming_pending`; rewrite the old-alert comment and `exempt_reason` clause.
- 4.2 `luks-monitor-install.test.sh`: Guard 1 rewrite and mutant re-pointing/moves.
- 4.3 `inngest-step-524-alert.test.sh`: drop capture-dark expectations, keep burn.
- 4.4 Comment sweep (`betterstack-send-failed-alert-mutation.test.sh:270`, repo-wide old-name grep).
- 4.5 Run `heartbeat-reprovision-parity.test.ts`, `heartbeat-live-reconcile.test.ts`, `sentry-monitor-iac-parity.test.ts`.

## Phase 5 — Docs, C4, ADRs

- 5.1 Runbook edits (6604 section + bullet + close line; betterstack-log-query standing alarms; inngest-server watchdog list + probe-heartbeat note).
- 5.2 Dated ADR amendments: 218 and 248 only (117, 119 and the post-mortem stay historical).
- 5.3 `model.c4` counts (C1 20, C2 14, C4 26, C5 15) and prose; `bash scripts/regenerate-c4-model.sh`; run both C4 suites.

## Phase 6 — Verify and open the PR

- 6.1 Run every Acceptance Criteria command (incl. `actionlint`, `terraform-target-parity.test.ts`, `sentry-monitors-audit.test.sh`,
  `function-registry-count` vitest, `lint-orphan-test-suites.sh`, the count-based old-name sweep).
- 6.2 Diff-scope check (no `luks-monitor.*`, `server.tf`, `cloud-init*`, `workspaces-luks-provision.sh`, inngest feeder).
- 6.3 `git add` the A6 draft by explicit path (unchanged, `draft-unsigned`).
- 6.4 Create the two follow-up issues (key-continuity reuse; remove retained `-target` lines + census rows after first apply).
- 6.5 PR body first line: "Merging this runs the push-triggered `apply-web-platform-infra.yml`: 2 creates, 4 deletes, needs `[ack-destroy]`"; then `Ref #11631`, owner-gated appendix (merge note `[ack-destroy]`, post-apply read-only checks, arm block with
  read-back, incident-resolve commands), Phase 0 measurements. Do not merge; do not arm auto-merge.
