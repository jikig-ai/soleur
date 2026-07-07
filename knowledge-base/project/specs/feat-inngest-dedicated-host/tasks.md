# Tasks: Extract Inngest to Its Own Dedicated Host (#6178)

Plan: `knowledge-base/project/plans/2026-07-07-feat-extract-inngest-dedicated-host-plan.md`
Lane: cross-domain · Threshold: single-user incident · Deferred HA: #6185 · Supersedes: #5450

## Phase 0 — Resolve fan-out + rehearse (local/read-only)

- [ ] 0.1 Detect current prod web-inngest backend (SQLite vs Postgres) via inngest-inventory hook + pool probe; note heterogeneous-fleet branch
- [ ] 0.2 Resolve invocation semantics by reading `node_modules/inngest` routing source; local 2-instance harness only if ambiguous; record in Research Insights (Connect probe cut)
- [ ] 0.3 Rehearse quiesce→outage→register timing + rollback (T5) locally
- [ ] 0.4 Author ADR-098 (fan-out mechanism, hooks-stay-web-host, dark→live flip, #5450 supersession); status: adopting

## Phase 1 — Provision on a NON-PROD dark backend (IaC)

- [ ] 1.1 `inngest-host.tf`: hcloud_server.inngest (cax11 ARM64) + hcloud_volume.inngest_redis + attachment + hcloud_server_network @ 10.0.1.40 + hcloud_firewall.inngest (deny-all-public)
  - [ ] 1.1.1 Inbound rule on `hcloud_firewall.web` for 10.0.1.40 (inngest→app path) + app private-interface bind for /api/inngest
  - [ ] 1.1.2 New vars inngest_server_type/inngest_redis_volume_size (defaulted); document no-ignore_changes[user_data] = maintenance-window-only force-replace
- [ ] 1.2 `cloud-init-inngest.yml`: bake GHCR creds; extract+run inngest-bootstrap.sh; Redis on volume; heartbeat; Vector; < 32KB
  - [ ] 1.2.1 Template `--sdk-url` in inngest-bootstrap.sh:339 (cross-consumer sweep: web + Vector; preserve web behavior pre-Phase-3)
- [ ] 1.3 Dark state = distinct non-prod Postgres backend (drop SQLite fail-safe); provision the non-prod DB before the host
- [ ] 1.4 Secrets on a separate Doppler PROJECT (not a prd branch config); explicitly provision INNGEST_POSTGRES_URI + keys + Redis pw
- [ ] 1.5 Dedicated `apply_target=inngest-host` dispatch job (NOT in per-merge -target set)

## Phase 2 — Cutover (operator; one gated `op=execute`; low-traffic window; heartbeat muted)

- [ ] 2.0 Re-detect web backend; confirm dedicated host firing zero prod crons
- [ ] 2.1 Capture reminders (op=backup + op=capture)
- [ ] 2.2 Quiesce + stop + `systemctl disable` inngest on ALL web hosts (incl weight-0 web-2); freeze web-2-recreate/warm-standby for the window
- [ ] 2.3 Repoint dedicated host → prod Postgres + start (first-class datastore-flip step; confirm web quiesced immediately before)
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

- [ ] 4.1 Soak 7d: per-(function_id, scheduled_tick) no group > 1; Follow-Through Enrollment (inngest-double-fire-6178.sh)
- [ ] 4.3 Flip ADR-098 adopting→accepted; `gh issue close 6178`

## Testing (see plan Test Scenarios)

- [ ] T1 per-(fn,tick) exactly-once · T2 reminder preservation · T3 cold-boot · T4 web independence · T5 rollback · T6 recreate-during-window
