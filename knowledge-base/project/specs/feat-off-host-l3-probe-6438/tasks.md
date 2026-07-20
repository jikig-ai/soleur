---
feature: off-host-l3-probe
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-18-feat-web-host-private-net-probe-primitive-plan.md
issues: [6438, 6548]
pr: 6654
---

# Tasks: Web-host private-net probe primitive

Scope: full bundle (#6438 §1 zot + #6548 git-data + §3 NIC guard), operator-confirmed 2026-07-18. Single-host (web-1) reality applied. All review fixes folded in.

## Phase A — Delivery substrate + §3 NIC guard (proves the rail)

- [x] A1 — Ported the §3 guard as standalone env-driven `web-private-nic-guard.sh` (detect+emit+alarm, **NO reboot**), delivered to web-1 by the SSH provisioner. (cloud-init bake for FUTURE hosts is A5 — deferred.)
- [x] A2 — `betteruptime_heartbeat.web_nic_guard` (`for_each = var.web_hosts`) + `doppler_secret.web_nic_guard_url` (web-probe.tf); `terraform_data.private_nic_guard_install` (server.tf, mirrors `disk_monitor_install`).
- [x] A3 — Arm gate built: `doppler_service_token.web_arm_write` → `DOPPLER_TOKEN_WEB_ARM` (web-arm-write-token.tf); op/state-gated on live `paused==true`; T0 → poll `last_ping_at > T0` within `period+grace` (monitor id from tfstate) → PATCH unpause on fresh beat → else leave paused + FAIL apply loud. Never gated on provisioner exit code. (apply-web-platform-infra.yml)
- [x] A4 — `web_nic_guard` + `web_zot_consumer` rows in `heartbeat-manifest.ts` (`web-host-cron`, `paused:true`, timer feeder evidence → server.tf); parity green; `registry_prd` untouched.
- [ ] A5 — **DEFERRED to #6459** (future-host cloud-init bake + arm-gate `var.web_hosts` iteration). No current-fleet value (single host, web-2 retired); new-host-HALT (apply.yml:456) is the safety net; high cloud-init-render risk for hypothetical hosts. See decision-challenges.md §1.
- [x] A6 — ADR-123 ("web-host private-NIC self-report, no self-converge") citing ADR-115's reboot-blockers; ordinal resolved from provisional ADR-122 (collided with #6653's sandbox ADR-122).

## Phase B — zot consumer probe (#6438 §1)

- [x] B1 — `web-zot-consumer-probe.sh`: authenticated (`ZUSER:ZTOK`) GET of `/v2/<repo>/tags/list` (tag-independent); 200=servable(ping), 404=empty(suppress), 401=hard-fail(exit 3), 000/5xx suppress, no `-f`, `-m 10`. Creds via `doppler run`; endpoint/repo via env file.
- [x] B2 — `betteruptime_heartbeat.web_zot_consumer` (`for_each = var.web_hosts`, period 180/grace 60, paused, `ignore_changes=[paused]`, policy_id ternary) + `doppler_secret.web_zot_consumer_url` (masked). (web-probe.tf)
- [x] B3 — Deleted `doppler_secret.zot_heartbeat_url_prd` + stale comment (zot-registry.tf).
- [x] B4 — `terraform_data.zot_consumer_probe_install` (SSH provisioner: timer OnUnitActiveSec=60s/AccuracySec=1s); manifest row + feeder evidence in this phase; arm gate covers web-1's monitor.

## Phase C — git-data consumer probe (#6548)

- [x] C1 — `web-git-data-probe.sh`: bounded connect-and-close to `10.0.1.20:22` (nc -z / dev-tcp), fail-soft; asymmetry documented (C1b); `terraform_data.git_data_probe_install`.
- [x] C2 — `git_data_prd` grace 30→180; flipped its manifest row to `feeder:{kind:"timer",…}` (server.tf evidence); reconciled the "still unfed" tripwire in heartbeat-reprovision-parity.test.ts same commit.

## Phase D — Architecture + observability

- [x] D1 — ADR-117 amended (arm-gate automation delta: apply-workflow PATCH, op/state-gated, `DOPPLER_TOKEN_WEB_ARM`, account-wide BS blast-radius risk note).
- [x] D2 — `model.c4` edited (web-host → zot/git-data consumer edges; §3 `SOLEUR_PRIVATE_NIC` web-host source; betterstack element git-data-fed/heartbeat descriptions); regenerated `model.likec4.json`; `c4-code-syntax.test.ts` + `c4-render.test.ts` green (23/23). views.c4 auto-renders (element-inclusion).
- [x] D3 — `scripts/followthroughs/l3-probe-armed-6438.sh` (checks the 3 live beats `up` via BS API, no dashboard) + directive + label.

## Phase E — Verify (Pre-merge ACs)

- [x] E1 — AC1: `web-zot-consumer-probe.test.sh` (29 pass) — mock-registry proves `-u`/`-f` load-bearing + classification.
- [x] E2 — AC2: manifest + parity green (19 pass) because honestly fed; row+evidence same phase; git_data_prd tripwire reconciled.
- [x] E3 — AC3: arm gate freshness-correct via ADR-117's LIVE-API-VERIFIED sequence (a paused BS heartbeat exposes NO ping timestamp — the plan's `last_ping_at > T0` was corrected at /work): PATCH `paused:false` → poll `status` until `up` within period+grace−10 → roll back to `paused:true` + FAIL the apply if `up` never lands. Fail-loud/rollback branch self-contained in the arm step block.
- [x] E4 — AC4: `web-private-nic-guard.test.sh` (46 pass) — comment-stripped asserts NO reboot invocation path (not a token grep), mutation-controlled.
- [~] E5 — AC5: `terraform validate` green; `+ create` for new resources, exactly 1 `-target`ed destroy (reserved `zot_heartbeat_url_prd`), git_data_prd in-place grace, no `hcloud_server.web` reboot — asserted by construction; the authoritative `terraform plan` runs in the CI apply (destroy-guard) at merge.
- [x] E6 — AC6: ADR-123 + ADR-117 amend + `model.c4` edits; c4 tests green.

## Post-merge (operator/automated)

- [ ] P1 — AC7: `l3-probe-armed-6438.sh` follow-through verifies web-1 zot-consumer + §3 + git_data_prd `up` (real measured beats, no dashboard) over the soak window — enrolled, runs post-merge.

## Deferred

- A5 → **#6459** (future-host cloud-init bake + arm-gate `var.web_hosts` iteration). See decision-challenges.md §1.

Next: `skill: soleur:work` (or `/deepen-plan` first — recommended at single-user-incident threshold + ultrathink).
