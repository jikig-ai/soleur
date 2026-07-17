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

- [ ] A1 — Port `soleur-private-nic-guard.sh` into `cloud-init.yml` (Terraform-baked), per-host `EXPECTED_IP='${private_ip}'`, **reboot action disabled** (detect+emit+alarm only); Doppler `--project soleur --config prd`.
- [ ] A2 — Create `betteruptime_heartbeat.web_nic_guard` (`for_each = var.web_hosts`) + `doppler_secret` URL (permanent, independent unit); new `terraform_data.private_nic_guard_install` (mirror `disk_monitor_install` server.tf:278-310) to install the guard + unit onto running web-1.
- [ ] A3 — Build the arm gate: `doppler_service_token` (mirror `inngest-arm-write-token.tf`); op/state-gated (paused==true or triggers_replace); capture T0 → poll `last_ping_at > T0` within `period+grace` (monitor id from tfstate) → PATCH unpause on fresh beat → else leave paused + fail apply loud. Never gate on provisioner exit code.
- [ ] A4 — Add `web_nic_guard` row to `heartbeat-manifest.ts` (`arming:"web-host-cron"`, `paused:true`, executable `feeder` evidence) + parity-manifest row; do not touch `registry_prd` 60/30.
- [ ] A5 — Bake B/C probe scripts into `cloud-init.yml` (future-host self-arm); arm gate iterates `var.web_hosts`; note the `apply.yml:456` new-host-HALT coupling as a #6459 dependency.
- [ ] A6 — New §3 ADR ("web-host private-NIC self-report, no self-converge") citing ADR-115's reboot-blockers; provisional ordinal.

## Phase B — zot consumer probe (#6438 §1)

- [ ] B1 — Probe script: authenticated (`ZUSER:ZTOK`) HEAD of a known manifest; 200=servable, 404=empty(suppress), 401=hard-fail, no `-f`, `-m 10`. Add creds to unit env + secrets list.
- [ ] B2 — `betteruptime_heartbeat.web_zot_consumer` (`for_each = var.web_hosts`, period 180/grace 60, paused, `ignore_changes=[paused]`, policy_id ternary) + `doppler_secret.web_zot_consumer_url` (masked).
- [ ] B3 — Delete `doppler_secret.zot_heartbeat_url_prd` (zot-registry.tf:511-517) + stale comment (:498-510).
- [ ] B4 — New `terraform_data.zot_consumer_probe_install` (SSH provisioner: timer OnUnitActiveSec=60s/AccuracySec=1s + script reading `$WEB_ZOT_PROBE_URL_*`); manifest row + feeder evidence **in this phase**; run the A3 arm gate against web-1's monitor.

## Phase C — git-data consumer probe (#6548)

- [ ] C1 — Probe: bounded connect-and-close to `10.0.1.20:22` (fail-soft accepted; document the reachability-vs-serviceability asymmetry; upgrade to `git ls-remote` per git-data.tf:270-273 TODO if a wedged-but-open git-data is seen).
- [ ] C2 — Relax `git_data_prd` grace (git-data.tf:246, 30→180, sustained-break paging); flip its manifest row (heartbeat-manifest.ts:152-153) to `feeder:{kind:"timer",…}`; reconcile the "still unfed" tripwire (heartbeat-reprovision-parity.test.ts:413) same phase.

## Phase D — Architecture + observability

- [ ] D1 — Amend ADR-117 (arm-gate automation delta: apply-workflow PATCH, op/state-gated, Doppler service token, account-wide blast-radius risk note).
- [ ] D2 — Edit `.c4` (web-host → zot/git-data consumer edges; §3 `SOLEUR_PRIVATE_NIC` web-host source; update `model.c4:268` git-data-unfed / registry-paused descriptions); run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] D3 — Enroll the soak follow-through probe (`scripts/followthroughs/l3-probe-armed-6438.sh` + `<!-- soleur:followthrough … -->` directive + `follow-through` label + sweeper secrets).

## Phase E — Verify (Pre-merge ACs)

- [ ] E1 — AC1: authenticated probe test (200 ping / 404,5xx,000 suppress / 401 hard-fail; `-f` and dropped `-u` fail behaviorally).
- [ ] E2 — AC2: manifest + parity green because honestly fed; row+evidence same phase; git_data_prd tripwire reconciled.
- [ ] E3 — AC3: arm gate freshness-correct (T0), scoped grep for the fail-loud arm-step branch.
- [ ] E4 — AC4: no reboot *action* on web hosts (assert invocation path absent, not the token).
- [ ] E5 — AC5: `terraform plan` = new `+ create`, exactly 1 destroy (reserved secret) + git_data_prd in-place, no `hcloud_server.web` reboot; provisioners on `-target` list.
- [ ] E6 — AC6: §3 ADR + ADR-117 amend + `.c4` edits; c4 tests green.

## Post-merge (operator/automated)

- [ ] P1 — AC7: `betterstack-query.sh` shows web-1 zot-consumer + §3 + git_data_prd `up` (real measured beats, no dashboard); follow-through green over soak.

Next: `skill: soleur:work` (or `/deepen-plan` first — recommended at single-user-incident threshold + ultrathink).
