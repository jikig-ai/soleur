# Tasks — feat-one-shot-9703-inngest-alert-delivery

Plan: `knowledge-base/project/plans/2026-10-24-feat-inngest-alert-delivery-observability-plan.md`
Issues: epic #10390; Ref #9703, #9705, #6645, #10918, #10584, #10914, #6472.

## Phase 1 — Measurement + mirror core (WS1)

- [ ] 1.1 Phase-0 measurement (record outputs in PR body): `GET /api/v2/slack-integrations`; `GET /api/v2/incidents?from=2026-10-22&until=2026-10-23`; `GET /api/v2/heartbeats` status vocabulary — via `BETTERSTACK_API_TOKEN_READONLY` on stdin-config curl.
- [ ] 1.2 Write `scripts/betterstack-incident-mirror.test.sh` fixtures FIRST (RED): open→file, rerun→comment, resolved→resolve-comment, human same-title→untouched, pagination.next→annotated, API 401→non-zero, empty→`no_incidents` marker.
- [ ] 1.3 Implement `scripts/betterstack-incident-mirror.sh` (xtrace refusal, `--config -` stdin token, `--disable --noproxy '*'`, projection to `{id,name,cause,started_at}`, `--selftest` printing `betterstack-incident-mirror selftest: ok`).
- [ ] 1.4 Create `.github/workflows/scheduled-betterstack-incident-mirror.yml` (gate-override comment, `schedule:`+`workflow_dispatch` only, `cancel-in-progress: false`, `issues: write`, terminal sentry-heartbeat step slug `scheduled-betterstack-incident-mirror`).
- [ ] 1.5 Add `WATCHDOG_DISPATCH_TABLE` row (intervalMinutes 15, clause-1 eligibility); update `sentry-monitor-iac-parity.test.ts` cohort assertions.
- [ ] 1.6 Add `sentry_cron_monitor.scheduled_betterstack_incident_mirror` to `apps/web-platform/infra/sentry/cron-monitors.tf` (margin ≤ parity ceiling, unrouted landing noted); run `terraform validate` + `terraform fmt -check` on the sentry root and paste in PR body (#6472 mitigation).

## Phase 2 — Serving verdict (WS2)

- [ ] 2.1 Extend `scripts/inngest-probe-heartbeat-feeder.sh` jq selection to carry `server_active`/`http_code`/`cutover_flag`; source `scripts/inngest-dedicated-host-classify.sh` (census load contract); verdict routing table + `/fail` beat arm + `fail_beat` marker.
- [ ] 2.2 Feeder harness fixtures (a)–(f) per Guard 2 matrix.
- [ ] 2.3 Update `.github/workflows/scheduled-inngest-probe-heartbeat.yml` `status:` expression + annotations + header comment.
- [ ] 2.4 Update `plugins/soleur/lib/heartbeat-manifest.ts` `inngest_server_probe` row comment (beat certifies fresh row AND serving verdict).
- [ ] 2.5 `push = true` on `betteruptime_heartbeat.inngest_prd` + `.inngest_consumer` in `apps/web-platform/infra/inngest.tf` (measured-flip comment; revert path named).
- [ ] 2.6 Runbook `inngest-server.md` "Arming the probe heartbeat" — serving-verdict sentence.

## Phase 3 — Post-merge soak + records (WS3)

- [ ] 3.1 `plugins/soleur/skills/postmerge/SKILL.md`: Phase 3.9 alert-channel sweep + Phase-6/7 report lines.
- [ ] 3.2 `scripts/followthroughs/post-deploy-incident-soak.sh` + `.test.sh` (TRANSIENT on read failure; paused/pending tolerated; window pinned past deploy).
- [ ] 3.3 `followthrough-convention.md` soak-trigger row.
- [ ] 3.4 ADR-297 (provisional — renumber per ship's collision gate + sweep refs) + `model.c4`/`views.c4` mirror edges; run `c4-code-syntax` + `c4-render` suites.
- [ ] 3.5 Register new suites: `scripts/test-all.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`.
- [ ] 3.6 Cross-reference comments on #6645, #10584 (deferral note: Telemetry-alerts mirroring), #9705.
