# Tasks — feat-one-shot-9342-bwrap-rollback-alert

Plan: knowledge-base/project/plans/2026-10-01-chore-alert-on-deploy-rollback-bwrap-probe-plan.md

## Phase 1: Guard (RED first)

- 1.1 Create `apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh` (sibling of `workspaces-luks-deadman-fired-alert.test.sh`): instrument self-test, heredoc extractor, predicate/exploration/alert/`-target`/runbook-anchor checks, needle read from `ci-deploy.sh` `BWRAP_LINE`
- 1.2 Add mutation rows R1-R9 (R7a/R7b) + whitespace must-PASS row + pristine-tree control + exact pass-count floor
- 1.3 Register the suite as a `run:` step in `.github/workflows/infra-validation.yml` after the `#9045` step
- 1.4 Run it; confirm RED (resource absent)

## Phase 2: Resource (GREEN)

- 2.1 Add `bwrap_probe_rollback_sql` + `bwrap_probe_rollback_runbook_url` locals, `logtail_exploration.bwrap_probe_rollback`, `logtail_exploration_alert.bwrap_probe_rollback` to `apps/web-platform/infra/betterstack-logs-alerts.tf` (no `host_name`; fmt-aligned `values` line; severity-first `incident_cause` with decode command)
- 2.2 Add both `-target=` lines to `.github/workflows/apply-web-platform-infra.yml` MAIN plan allowlist
- 2.3 Bump M17 count 8 -> 9 and comment in `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`
- 2.4 Bump `BASELINE_DECLARED_PROBES` 40 -> 41 with dated justification in `plugins/soleur/test/preflight-discoverability-test.test.ts`
- 2.5 `terraform fmt -check` / `terraform validate`; run the new guard + all sibling alert guards + send-failed mutation battery

## Phase 3: Runbooks

- 3.1 `canary-probe-set.md`: name `soleur-bwrap-probe-rollback-prd` in the `rc` row; replace the "pull-only until #9342 lands" sentence; keep the "Re-run failed jobs" remediation
- 3.2 `betterstack-log-query.md`: add the standing-alarm bullet

## Phase 4: Live probe

- 4.1 Probe the final heredoc SQL via `scripts/betterstack-query.sh` raw mode (14 days): positive control > 0, `...functionalX` negative control = 0; record counts in PR body

## Phase 5: Ship

- 5.1 PR #9376 body: `Closes #9342` (not the title), labels priority/p3-low, type/chore, domain/engineering, observability
- 5.2 Post-merge: apply workflow run success; reconciler `logs_alert` arm shows no absent/paused for `soleur-bwrap-probe-rollback-prd`
