# Tasks: route the scheduled-integration-suites Sentry monitor (two-PR rule PR 2, #9959)

Plan: knowledge-base/project/plans/2026-10-11-route-scheduled-integration-suites-monitor-plan.md

## Phase 0: preflight (read-only)

- 0.1 `git fetch origin main`; confirm the worktree branch is `feat-one-shot-9959-route-sentry-monitor` and the two preconditions still hold (issue #9959 OPEN; unrouted entry still present in `cron-monitor-alerts.tf`).
- 0.2 If another Sentry-root PR merged since plan time, re-check the `monitor_ids` insertion point and the `detectorIds` tail — sort position may have moved.

## Phase 1: the routing move

- 1.1 `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`: delete the `#9855` comment block + the `scheduled_integration_suites = "route after the first measured check-in (#9959)"` entry from `local.cron_monitor_alert_unrouted` (pre-edit lines 59–63). Leave the three remaining entries and comments untouched.
- 1.2 Same file: insert `    sentry_cron_monitor.scheduled_integration_suites.id,` into `sentry_alert.cron_monitor_failure.monitor_ids` between `sentry_cron_monitor.scheduled_inngest_health.id,` and `sentry_cron_monitor.scheduled_legal_audit.id,` (LC_ALL=C sorted).
- 1.3 `apps/web-platform/infra/sentry/alert-reference.json`: in the `cron-monitor-failure` entry, change `      "2359391"` (last `detectorIds` element) to `      "2359391",` and append `      "2403709"`. Detector id verified live at plan time: `2403709`, `type: monitor_check_in_failure`, `workflowIds: []`.
- 1.4 Canonical checks: `jq -S . apps/web-platform/infra/sentry/alert-reference.json | cmp - apps/web-platform/infra/sentry/alert-reference.json`; `jq '.["cron-monitor-failure"].detectorIds | . == sort and length == 61'` → `true`; `git diff origin/main...HEAD -- apps/web-platform/infra/sentry/alert-reference.json` shows exactly one added element.

## Phase 2: local gates, then push

- 2.1 Deps (worktree was created `--no-install`): `npm ci --ignore-scripts --prefix apps/web-platform` if `apps/web-platform/node_modules/.bin/vitest` is absent.
- 2.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/sentry-cron-monitor-routing-parity.test.ts` — green.
- 2.3 `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` — green (hermetic).
- 2.4 `bash plugins/soleur/test/c4-count-parity.test.sh` — green (routing moves no count).
- 2.5 `terraform fmt -check apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — clean.
- 2.6 Commit the two files; PR body first line states the production effect (apply adds detector `2403709` to `cron-monitor-failure`); `Closes #9959` in the body, not the title.
- 2.7 Watch `plan_pr` foreground-bounded (per `hr-monitor-not-run-in-background-for-polling`). Expected: `sentry-alert-reference-gate.sh` PASS on the committed reference.
- 2.8 CONTINGENCY — only if the reference gate reds: `gh run download <run-id> -n sentry-alert-reference-expected-<run-id>`, `diff` the downloaded `sentry-alert-reference.expected.json` against the committed file (only the `detectorIds` hunk may differ — anything else is a finding), `cp` it over `apps/web-platform/infra/sentry/alert-reference.json`, commit, push. Artifact retention 7 days; `gh run rerun <run-id> --failed` regenerates.

## Phase 3: post-merge verification

- 3.1 `apply-sentry-infra.yml` on the merge commit: green, one in-place update of `sentry_alert.cron_monitor_failure`, zero destroy.
- 3.2 Live read-back: `doppler run --project soleur --config prd --command 'curl -s -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/workflows/" | jq ".[] | select(.name==\"cron-monitor-failure\") | .detectorIds | index(\"2403709\")"'` → non-null index.
- 3.3 Confirm #9959 closed via `Closes #9959`; the two checklist items are complete (the third bullet is descriptive, not a task).
