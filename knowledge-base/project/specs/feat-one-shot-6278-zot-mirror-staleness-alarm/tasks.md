# Tasks — Live zot mirror-staleness Sentry alarm (#6278)

lane: single-domain
Plan: `knowledge-base/project/plans/2026-07-09-feat-zot-mirror-fallback-rate-sentry-alarm-plan.md`

## Phase 0 — Provider-schema + dataset probe (blocks all design choices; network-free)

- [ ] 0.1 Dump the cached provider schema from the sibling worktree
      (`.worktrees/feat-one-shot-anthropic-cost-attribution/apps/web-platform/infra/sentry/.terraform/…/jianyuan/sentry/0.15.0-beta2`)
      via `terraform -chdir=<sibling-sentry-dir> providers schema -json` — no `terraform init`.
- [ ] 0.2 Confirm `sentry_metric_alert` shape: `aggregate`, `dataset`, `query`, `time_window`,
      `threshold_type`, nested `trigger { alert_threshold, action {…} }`.
- [ ] 0.3 **P1 gate:** confirm the metric-alert dataset (likely `events`, NOT `errors`) matches
      `level:warning` / `event.type:default` store events; the query MUST have no `event.type:error` prefix.
- [ ] 0.4 Confirm `event_frequency` block in `sentry_issue_alert.conditions_v2` (fallback branch —
      already verified present).
- [ ] 0.5 Re-confirm emit-site tags: `ci-deploy.sh:564` (ghcr-fallback), `:592` (zot-gate-degraded),
      `cloud-init.yml:650` (inngest_ghcr_fallback, stage-only).
- [ ] 0.6 Pick free `frequency` (Branch A only): `23`.
- [ ] 0.7 Decide branch: **Branch B (metric alert)** unless 0.3 fails → Branch A with operator note.
      Record decision + values in session-state.

## Phase 1 — Alarm resource in `issue-alerts.tf`

- [ ] 1.1 Add `sentry_metric_alert.zot_mirror_fallback_rate` (Branch B primary): aggregate `count()`,
      `time_window=60`, critical `alert_threshold=3`, query over the OR-of-signals (no event.type:error),
      notify shape confirmed in 0.2.
- [ ] 1.1-alt (Branch A fallback) `sentry_issue_alert` + `event_frequency` count>3/1h, `filter_match="any"`,
      `frequency=23`; correct the stale `:838-839` comment; surface per-path sensitivity in PR body.

## Phase 1b — App-image fresh-boot fallback breadcrumb (close boot blind spot)

- [ ] 1b.1 Add `soleur-boot-emit app_ghcr_fallback warning` on the web-boot zot→GHCR fallback branch
      (`cloud-init.yml:~496`), symmetric with the inngest path at `:650`.
- [ ] 1b.2 Include `stage:app_ghcr_fallback` as a 4th signal in the alarm query/filter.
- [ ] 1b-alt (descope) drop the 4th signal, correct the "closes the gap" framing, file a follow-up issue.

## Phase 2 — Apply wiring + guard sweep + op-contract test

- [ ] 2.1 Append `-target=sentry_metric_alert.zot_mirror_fallback_rate` (or issue-alert) to
      `apply-sentry-infra.yml` after line 261.
- [ ] 2.2 **Branch B guard sweep (P1):** add `sentry_metric_alert` nested-clause to
      `tests/scripts/lib/destroy-guard-filter-sentry.jq` (sum `trigger[]`/`action[]` deltas); extend the
      scope-guard allowlist (`test-destroy-guard-sentry-scope-guard.sh:52`); add a counter-test fixture case.
- [ ] 2.3 (Branch A) no guard change beyond 2.1 (verified complete).
- [ ] 2.4 Create `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` mirroring
      `sentry-inbox-action-required-alert-op-contract.test.ts`: pin all signal tag-values across emit
      sites (`ci-deploy.sh`, `cloud-init.yml`) + the alarm resource in `issue-alerts.tf`.

## Phase 3 — inngest-bootstrap mirror push-notification signal

- [ ] 3.1 Add a `Post to Slack (inngest mirror status)` step to `build-inngest-bootstrap-image.yml`,
      gated `if: steps.zot_mirror.outputs.mirror_status == 'degraded'`, `continue-on-error: true`,
      reading `SLACK_RELEASES_WEBHOOK_URL`, reusing the injection-inert posting shape from
      `reusable-release.yml:895-914`.
- [ ] 3.2 Update the `zot_mirror` "annotations-only by design" comment to cite the #6278 Slack signal.

## Phase 4 — Verify (no SSH)

- [ ] 4.1 `terraform validate` in `apps/web-platform/infra/sentry/` (accept the deprecation warning).
- [ ] 4.2 `terraform plan` (scoped `-target`) shows 1 to add, 0 change, 0 destroy.
- [ ] 4.3 `./node_modules/.bin/vitest run test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`.
- [ ] 4.4 `actionlint .github/workflows/build-inngest-bootstrap-image.yml` + `bash -n` on the Slack snippet.
- [ ] 4.5 Guard suites green: `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` +
      `bash tests/scripts/test-destroy-guard-counter-sentry.sh`.
- [ ] 4.6 (Optional) correct the stale ADR-062:120 event_frequency note; annotate ADR-096 status line.

## Post-merge (operator — automatable, no SSH)

- [ ] P.1 Auto-apply fires on the `issue-alerts.tf` path; verify via Sentry API
      `GET /api/0/projects/jikigai-eu/web-platform/rules/` (issue alert) or `.../alert-rules/` (metric alert)
      that `zot-mirror-fallback-rate` exists. PR body uses `Closes #6278`.
