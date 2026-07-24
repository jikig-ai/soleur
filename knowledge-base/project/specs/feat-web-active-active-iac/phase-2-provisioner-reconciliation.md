---
feature: web-active-active-iac
phase: "2.1 — provisioner-set reconciliation (AC4: pinned enumeration)"
date: 2026-07-24
source: exhaustive grep-enumeration of apps/web-platform/infra/*.tf (2026-07-24)
adr_gate: ADR-136 (preapply-entrypoint-enumeration)
---

# Phase 2.1 — Web-1 Out-of-Band Provisioning: Pinned Reconciliation

Resolves the plan's "11 vs 12 vs 7" discrepancy. **Definitive total: 17 `terraform_data`
siblings** provision the web-1 host out-of-band (16 SSH-provisioned + 1 local-exec over the
CF-Tunnel webhook). `hcloud_server.web` itself has **zero** provisioner/connection blocks — it
provisions only via `user_data` with `ignore_changes=[user_data,…]` (server.tf:293), which is
*why* every mechanism is a separate sibling hardcoded to `hcloud_server.web["web-1"]`.

## The three stale counts

| Source | Says | Reality |
|---|---|---|
| plan prose / `server.tf:117` | "11 SSH provisioners" | stale — predates the 3 probes (#6438/#6548), `registry_insecure_config` (#6122), `cosign_trusted_root` (#6005), `cron_egress_firewall` |
| `model.c4:412-413` | "12 terraform_data SSH provisioners / 12 connection{} inlines" | stale — current SSH-connection count is 16 (15 CI-reachable; `root_authorized_keys` is operator-local) |
| `terraform-target-parity.test.ts` | "7 siblings" | NOT a total — a hardcoded **subset** (the 7 hardening siblings SSH-`-target`ed by `apply-web-platform-infra.yml`); the test's dynamic floor is `MIN_SSH_PROVISIONED=10` and its true dynamic count today is **16** |

## Definitive table (the pinned enumeration — AC4)

`web-1-gated?` = yes for all 17 (each hardcodes `connection.host = hcloud_server.web["web-1"]`).
`fresh-boot?` = whether a fresh cattle host already reproduces the effect (cloud-init.yml /
baked `soleur-host-bootstrap.sh` host-scripts) or is **SSH-ONLY** (the #6459 silent-boot gap).

| # | Resource | Anchor | Type | fresh-boot coverage |
|---|---|---|---|---|
| 1 | root_authorized_keys | ci-ssh-key.tf:68 | remote-exec | COVERED (cloud-init `ssh_authorized_keys`) |
| 2 | disk_monitor_install | server.tf:305 | file+remote-exec | COVERED (baked + cloud-init enable) |
| 3 | resource_monitor_install | server.tf:345 | file+remote-exec | COVERED |
| 4 | container_restart_monitor_install | server.tf:387 | file+remote-exec | COVERED |
| 5 | **private_nic_guard_install** | server.tf:460 | file+remote-exec | **SSH-ONLY** ⟵ gap |
| 6 | **zot_consumer_probe_install** | server.tf:519 | file+remote-exec | **SSH-ONLY** ⟵ gap |
| 7 | **git_data_probe_install** | server.tf:570 | file+remote-exec | **SSH-ONLY** ⟵ gap |
| 8 | fail2ban_tuning | server.tf:652 | file+remote-exec | COVERED |
| 9 | journald_persistent | server.tf:730 | file+remote-exec | COVERED |
| 10 | cosign_trusted_root | server.tf:847 | file+remote-exec | COVERED |
| 11 | registry_insecure_config | server.tf:917 | file(content)+remote-exec | COVERED |
| 12 | infra_config_handler_bootstrap | server.tf:1048 | file+remote-exec | COVERED |
| 13 | deploy_pipeline_fix | server.tf:1174 | **local-exec** (CF-tunnel webhook) | COVERED |
| 14 | **docker_seccomp_config** | server.tf:1317 | file+remote-exec | **PARTIAL** — seccomp file baked; the `bwrap-userns-sysctl.service` + `/etc/sysctl.d/99-bwrap-userns.conf` half is SSH-ONLY ⟵ gap |
| 15 | apparmor_bwrap_profile | server.tf:1380 | file+remote-exec | COVERED |
| 16 | **orphan_reaper_install** | server.tf:1418 | file+remote-exec | **SSH-ONLY** (not even baked) ⟵ gap |
| 17 | cron_egress_firewall | server.tf:1456 | file+remote-exec | COVERED (enforcement path) |

## Phase-2.2 work-list — the 5-item fresh-boot gap

A fresh cattle web host (web-2, Phase 3) currently comes up WITHOUT these. Phase 2.2 bakes/wires
each so the cattle cloud-init is complete. **The SSH provisioners are RETAINED** (they handle
running-host updates + credential rotation on the pet web-1 until Phase 5 de-pets it) — Phase 2
ADDS fresh-boot coverage, it does not remove the SSH path.

1. **`private_nic_guard_install`** — probe `.sh` + `.service`/`.timer` + `/etc/default/web-private-nic-guard` (EXPECTED_IP per-host, Better Stack URL, read-scoped Doppler token).
2. **`zot_consumer_probe_install`** — probe `.sh` + unit + env.
3. **`git_data_probe_install`** — probe `.sh` + unit + env.
4. **`orphan_reaper_install`** — `orphan-reaper.sh` + `.service`/`.timer` (no token; also add to the baked `host_script_files` set).
5. **`docker_seccomp_config` sysctl half** — `/etc/sysctl.d/99-bwrap-userns.conf` + `bwrap-userns-sysctl.service` (`kernel.apparmor_restrict_unprivileged_userns=0`; no token).

### Settled security finding (no CTO fork)

The 3 probes' scoped `doppler_service_token.web_probes` (web-probe-read-token.tf:33) is
**config-scoped read-only** and, per its own rationale, **"adds no new secret exposure — the host
already carries a full-prd DOPPLER_TOKEN via /etc/default/webhook-deploy."** The web host's
user_data *already* embeds a full-prd `${doppler_token}` (server.tf:211), so splicing the
read-scoped probe token into the cattle cloud-init adds **zero marginal exposure**. The dedicated
token exists for env-hygiene (token-only env, avoiding the #6536 `/tmp/.doppler` clash), not
blast-radius. → No security-model fork; no CTO routing required.

## ADR-136 gate

Phase 2/5 reprovision applies run through `apply-web-platform-infra.yml`, which carries the
ADR-136 fail-closed **pre-apply entrypoint gate** (`tests/scripts/lib/preapply-entrypoint-gate.sh`)
guarding `cloudflare_ruleset` whole-list create-from-absent. The cattle-cloud-init reprovision must
present no such ruleset create. `terraform-target-parity.test.ts` remains the enumeration guard for
the SSH-`-target` set (floor `MIN_SSH_PROVISIONED=10`).
