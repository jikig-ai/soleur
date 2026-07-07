# Tasks: Extract Inngest to Its Own Dedicated Host (#6178)

Plan: `knowledge-base/project/plans/2026-07-07-feat-extract-inngest-dedicated-host-plan.md`
Lane: cross-domain · Threshold: single-user incident · Deferred HA: #6185 · Supersedes: #5450

## Phase 0 — Resolve fan-out + rehearse (local/read-only)

- [ ] 0.1 Detect current prod web-inngest backend (SQLite vs Postgres) via inngest-inventory hook + pool probe; note heterogeneous-fleet branch
- [x] 0.2 DONE — ROUTE-ONCE confirmed (Docker 2-instance harness; SDK source alone insufficient). Recorded in plan `## Research Insights` + ADR-098. Decision: single-url-now, VIP-at-N>1 (Connect probe cut)
- [~] 0.3 PARTIAL — Redis-swap + route-once rehearsed in the Phase-0 Docker harness; full quiesce→register timing + rollback (T5) rehearsed against cutover-inngest.yml in Phase-2 pre-flight (not local)
- [x] 0.4 DONE — cron-run enum path CONFIRMED (`runs(RunsFilterV2, timeField:STARTED_AT, functionIDs)`; invariant `(functionID, floor(startedAt/period))`; scheduled_tick nonexistent). Redis-swap → FLUSHALL+DBSIZE==0 MANDATORY (empirically proven). State model reconciled. AC13 soak probe demonstrably writable. Evidence: phase0-empirical-spike.md
- [x] 0.5 DONE — ADR-098 authored (status: adopting); C4 edits applied + c4-*.test.ts green (AC5/AC6)

## Phase 1 — Provision on a NON-PROD dark backend (IaC)

Status detail + remaining Phase-1 items (R1 doppler-project cascade, R2 apply-dispatch): see `session-state.md`.
Legend: [x] done+committed · [~] partial · [ ] todo.

- [x] 1.1 `inngest-host.tf`: hcloud_server.inngest (cax11 ARM64) + hcloud_volume.inngest_redis + attachment + hcloud_server_network @ 10.0.1.40 + hcloud_firewall.inngest (deny-all-public)
  - [x] 1.1.1 Host-local **nftables** scoping :8288/:8289 to web-host private IPs (drop .20/.30) — the cloud firewall is a no-op intra-subnet (SEC-H1/H2); verify :8288 GraphQL auth; bind :8289 loopback if Connect unused. (The `hcloud_firewall.web` rule does NOT scope /api/inngest — signature-verify is the boundary.)
  - [x] 1.1.2 New vars inngest_server_type/inngest_redis_volume_size (defaulted); document no-ignore_changes[user_data] = maintenance-window-only force-replace
  - [x] 1.1.3 Rotate INNGEST_SIGNING_KEY/INNGEST_EVENT_KEY for the new boundary (do NOT reuse co-located keys) — SEC-H3
- [x] 1.2 `cloud-init-inngest.yml`: bake GHCR creds; extract+run inngest-bootstrap.sh; Redis on volume; heartbeat; < 32KB [R1 doppler-project cascade done, commit 5044a505d; Vector DEFERRED on arm64 → tracked follow-up]
  - [x] 1.2.1 Template `--sdk-url` in inngest-bootstrap.sh:339 (cross-consumer sweep: web + Vector; preserve web behavior pre-Phase-3) [server + heartbeat + redis units templated + tested — R1 done, commit 5044a505d]
- [x] 1.3 Dark state = distinct non-prod Postgres backend (drop SQLite fail-safe); provision the non-prod DB before the host
- [x] 1.4 Secrets on a separate Doppler PROJECT (not a prd branch config); explicitly provision INNGEST_POSTGRES_URI + keys + Redis pw [core 3 secrets + project + token + heartbeat URL done — R1, commit 5044a505d; BETTERSTACK_LOGS_TOKEN rides the deferred Vector]
- [x] 1.5 Dedicated `apply_target=inngest-host` dispatch job (NOT in per-merge -target set) [done — commit 792826950; parity exclusions + inngest-host.test.sh drift guard]

## Phase 2 — Cutover (operator; one gated `op=execute`; low-traffic window; heartbeat muted)

- [ ] 2.0 Re-detect web backend; confirm dedicated host firing zero prod crons
- [ ] 2.1 Capture reminders from ALL scheduler hosts (incl weight-0 web-2, which self-arms into its own Redis at boot) — merge/dedup on reminder_id; capture AFTER scheduler-stop (or subtract in-window terminal fires) to avoid capture→quiesce double-fire (DI-C3/H4)
- [ ] 2.2 Quiesce + stop + `systemctl disable` inngest on ALL web hosts (incl weight-0 web-2); freeze web-2-recreate/warm-standby for the window
- [ ] 2.2b **Redis FLUSHALL + AOF truncate** on the dedicated host; assert DBSIZE==0 before the prod flip (DI-C1)
- [ ] 2.3 Repoint dedicated host → prod Postgres + start (first-class datastore-flip step; confirm web quiesced + dedicated Redis empty immediately before)
- [ ] 2.4 Repoint app INNGEST_BASE_URL → 10.0.1.40 at BOTH ci-deploy.sh:1341 + :1574; redeploy
- [ ] 2.5 Rearm (op=rearm) AFTER app-repoint; assert capture==rearm==pre-cutover armed; partial-rearm branch
- [ ] 2.6 Verify per-(fn,tick) exactly-once; rollback path stops the DEDICATED host first
- [ ] 2.x Document bounded outage window + crons needing manual trigger-cron re-fire

## Phase 3 — Decommission + observability (SOAK-GATED on 4.1)

- [ ] 3.1 Complete web decommission (bootstrap block 624-681, INNGEST_BASE_URL 716, sudoers dropfile 74-81 + mirror + deploy_pipeline_fix, /var/lib/inngest from 245/webhook.service:45) — KEEP capture subpath writable; co-located inngest stopped+disabled-but-present until soak-green
- [ ] 3.2 Repoint on-host scripts INNGEST_GQL_URL → 10.0.1.40 (enumerate/inventory/rearm); hooks stay web-host
- [ ] 3.3 ONE commit: ci-deploy.sh both sites + INNGEST_HOST_FALLBACK + parity test
- [ ] 3.4 Extend observability to new host; retire deploy.soleur.ai tunnel for inngest

## Phase 4 — Soak gate

- [ ] 4.1 Soak 7d: exactly-once via the Phase-0.4-validated mechanism (real cron-run enumeration grouped by (function_id, bucket(startedAt, cron_period)) OR per-cron Sentry cron-monitor) — NOT scheduled_tick; Follow-Through Enrollment (inngest-double-fire-6178.sh must be demonstrably writable against the pin before it gates 3.1)
- [ ] 4.3 Flip ADR-098 adopting→accepted; `gh issue close 6178`

## Testing (see plan Test Scenarios)

- [ ] T1 per-(fn,tick) exactly-once · T2 reminder preservation · T3 cold-boot · T4 web independence · T5 rollback · T6 recreate-during-window
