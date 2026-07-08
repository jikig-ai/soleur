---
title: "Tasks — zot 500 blob-upload + blind-host disk observability (Closes #6240 #6244)"
plan: knowledge-base/project/plans/2026-07-08-fix-zot-disk-full-observability-and-resize2fs-plan.md
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# Tasks

## Phase 0 — Preconditions (no writes)
- [ ] 0.1 Read-only: `doppler secrets get BETTERSTACK_LOGS_TOKEN -p soleur -c prd_terraform --plain` resolves (STOP if absent).
- [ ] 0.2 Confirm the reused `BETTERSTACK_LOGS_TOKEN` writes to Logs source 2457081 (table `t520508_soleur_inngest_vector_prd_3_logs`); record whether a `--table` override is needed.
- [ ] 0.3 Probe the Better Stack Logs ingest host/region the token authenticates against (region-bound token — do not assume).
- [ ] 0.4 Read the exact `registry-host-replace` `-target` set in `apply-web-platform-infra.yml`; confirm the 5 registry targets incl. `hcloud_volume.registry`.

## Phase 1 — Observability (in-surface disk probe) [#6244]
- [ ] 1.1 Reuse `disk-monitor.sh` threshold/cooldown/envfile SHAPE; do NOT stand up full Vector (out of scope + quota + missing bespoke fields).
- [ ] 1.2 Keep the absence-based liveness ping (<85% gate) in `zot-disk-heartbeat.sh` unchanged.
- [ ] 1.3 Add a structured self-report emitting ONE `SOLEUR_ZOT_DISK pcent=… fs_size_gb=… block_size_gb=… resize_ok=… zot_restarts=… ping_rc=…` line to Better Stack Logs via `curl -H "Authorization: Bearer $BETTERSTACK_LOGS_TOKEN"`.
- [ ] 1.4 Wrap the cron in `doppler run --project soleur-registry --config prd`; read `BETTERSTACK_LOGS_TOKEN` from the isolated config (NOT baked into user_data).
- [ ] 1.5 Fail-loud guard discipline: neutralize `df`/`grep -c`/`curl` exits with sentinels that SHIP the failure (`resize_ok=false`, `ping_rc=N`), never silently swallow; cron exits 0 so it does not wedge.

## Phase 2 — resize2fs hardening (fail-loud) [#6240 primary]
- [ ] 2.1 Device-wait loop before `mount` (bounded ~30×2s) — handle the attach race.
- [ ] 2.2 Add `e2fsprogs` to `packages:` + a runcmd `dpkg -s e2fsprogs || apt-get install -y e2fsprogs` guard before the resize (packages: stage is non-fatal).
- [ ] 2.3 Assert ext4-on-raw-device (no partition → no growpart); fail loud if a partition unexpectedly appears.
- [ ] 2.4 Capture `df` before/after + resize2fs exit code; persist `/var/lib/zot/.resize-result` for the Phase-1 reporter.
- [ ] 2.5 Remove `|| true` from the resize line (silent-swallow sense); on failure emit `resize_ok=false` to journald + telemetry but still launch zot (fail-loud, not fail-wedge).
- [ ] 2.6 Assert post-resize fs size ≈ block-device size; a persistent `fs_size_gb≈10` on a 30 GB device confirms hypothesis (a).

## Phase 3 — gc/retention + guard amendment [#6240 defense-in-depth]
- [ ] 3.1 `config.json`: `gcInterval` 24h→≤6h and `retention.delay` 24h→shorter; keep-set UNCHANGED (`sha256-*` cosign referrers retained).
- [ ] 3.2 On-boot gc/retention nudge (verify zot v2.1.2 exposes a trigger before prescribing; else rely on tightened interval — `hr-verify-repo-capability-claim`).
- [ ] 3.3 Amend the boot isolation self-check to expect exactly 3 non-DOPPLER secrets `{ZOT_PULL_TOKEN, ZOT_PUSH_TOKEN, BETTERSTACK_LOGS_TOKEN}` (cardinality + identity, fail-loud) — mirror `cloud-init-inngest.yml`.

## Phase 4 — Terraform wiring [#6244 + #6240]
- [ ] 4.1 Add `doppler_secret.registry_betterstack_logs_token` in `zot-registry.tf` (isolated project/config, value `var.betterstack_logs_token`, `ignore_changes=[value]`) — mirror `inngest-betterstack-token.tf`.
- [ ] 4.2 Extend the `registry-host-replace` `-target` set with `doppler_secret.registry_betterstack_logs_token`; confirm dependents (`hcloud_server_network`/`_volume_attachment`/`_firewall_attachment`) remain.
- [ ] 4.3 (Contingent — telemetry-driven only) bump `var.registry_volume_size` if the 30 GB fs is genuinely full after resize+gc.

## Phase 5 — Docs: ADR-096 amendment + C4 edge
- [ ] 5.1 Amend ADR-096: isolation-guard 2→3, disk-observability delivery, resize2fs+gc remediation.
- [ ] 5.2 Add `zotRegistry -> betterstack` edge to `model.c4` (views already include both endpoints).
- [ ] 5.3 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 6 — Post-merge verify (agent-automated, NO operator)
- [ ] 6.1 `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace`; wait for success.
- [ ] 6.2 Verify private-net reachability post-replace (NIC may be down → soft reboot; crane probe IS the check).
- [ ] 6.3 `betterstack-query.sh --since 30m --grep SOLEUR_ZOT_DISK` → `resize_ok=true`, `fs_size_gb≈30`, `pcent<85`.
- [ ] 6.4 Fresh release or manual crane push probe → zero `500` / zero `no space left on device`.
- [ ] 6.5 `soleur-registry-disk-prd` heartbeat `attributes.status==up` (Uptime API, NOT `last_event_at`); incident auto-resolves.
- [ ] 6.6 Close #6240 + #6244 AFTER 6.3+6.4+6.5 green.
- [ ] 6.7 `compound`: capture the resize2fs-failed-silently signature + recovery (no prior learning exists).
