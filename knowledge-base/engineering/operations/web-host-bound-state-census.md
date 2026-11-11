---
title: Web host-bound state census
date: 2026-11-10
category: operations
tags: [web-hosts, cattle, census, bastion]
issues: ["#9421", "#12008"]
---

# Web host-bound state census

What a web host holds that is tied to its key or to its own disk, and whether a fresh birth
delivers it without SSH. ADR-327 decides that web hosts are identical cattle; this census is the
evidence it rests on for the three items its dissent left unverified. Each row is pinned by
`apps/web-platform/infra/web-hosts-generic.test.sh` (section CENSUS), so a change that breaks a
row reds CI instead of leaving this page stale.

| # | State | Delivered at birth? | Evidence | Owed before a new key (web-3) |
|---|---|---|---|---|
| C1 | Egress-gateway token directory `/var/lib/soleur/egress-tokens` (owner 1001, mode 0711) | **Yes.** The baked `egress-gateway-bootstrap.sh` creates it, and runcmd runs that script before the app container mounts the directory. The two `server.tf` SSH provisioners that also create it are redundant for a birth. | `egress-gateway-bootstrap.sh` (`mkdir -p "$TOKEN_DIR"`); `cloud-init.yml` (the bootstrap runcmd item precedes the app `docker run`) | Nothing |
| C2 | Scheduled host work (systemd timers, one weekly cron script, no crontab) | **Yes.** Every timer is enabled from user_data runcmd, and the only cron entry, `/etc/cron.weekly/docker-cleanup`, is written by user_data too. No birth path runs `crontab` or writes `/etc/cron.d`. None of this keeps state that a replacement would lose: each run reads its inputs fresh. | `cloud-init.yml` `systemctl enable --now` items and the `docker-cleanup` heredoc | Nothing |
| C3 | Per-host Better Stack heartbeat URLs for the host probes (nic-guard, bash-synthetic, zot-consumer) | **Keyed and minted per key.** `web-probe.tf` creates each heartbeat and its `WEB_*_URL_<KEY>` Doppler secret `for_each = var.web_hosts`; `web-probe-envwrite.sh` derives the same name from the host key at birth. | `web-probe.tf` (`doppler_secret.web_*_url`); `web-probe-envwrite.sh` (`HOST_UPPER` derivation) | Apply order only: the key's `web-probe.tf` resources must apply before its birth reads the secrets |
| C4 | Per-host kernel-marker dead-man heartbeat | **Keyed by hand.** One `betteruptime_heartbeat` resource per web key (`host_kernel_web_1`, `host_kernel_web_2`). A new key has no heartbeat until one is added. | `uptime-alerts.tf` | A `host_kernel_web_<n>` resource (or a `for_each` over `var.web_hosts`) in the same PR as the key |
| C5 | Session-proxy TLS certificate SANs (every web private IP and key) | **Derived, but fleet-wide.** `proxy-tls.tf` takes the SANs from `var.web_hosts`, so a new key re-mints the certificate. The old hosts keep the old one until they redeploy. | `proxy-tls.tf` (`ip_addresses`, `dns_names`) | A fleet redeploy after the key's apply, so every host serves and trusts the new SANs |
| C6 | Cross-host relay config (`SOLEUR_HOST_ROSTER`, `SOLEUR_PROXY_PEER_ALLOWLIST`) | **No: hand-kept Doppler values.** The session router and the LB gate read them; nothing in Terraform derives them from `var.web_hosts`. | `server/session-router.ts`; `lb-weight-gate.sh` Condition A | The new key and address in both values before it is pooled (the gate refuses otherwise) |
| C7 | SSH host-key pin per host (`web-<n>-ssh-host-key.pub`) | **No: committed per host.** Each birth makes a new host key, and the CI connection that dials that host pins the committed file. | `server.tf` (`web_*_ssh_host_key` locals) | A capture-and-commit after the key's birth, until the bastion (PR 2–3) removes per-host dialing |

Rows C3 and C4 are the forcing function for the `web-3` PR (#9421 sequence, PR 5). The suite
counts the `host_kernel_web_*` heartbeats against the `var.web_hosts` keys, so adding a key without
its heartbeat reds CI.

The users' worktrees under `/var/lib/soleur/worktrees` are host-bound data, not configuration. Nothing
is mounted there: they sit in the app container's writable layer (`apps/web-platform/Dockerfile`), so a
redeploy discards them as surely as a replace does, and the plan's flush step (PR 6) is what covers them.
web-1 also holds the sole copy of the `/mnt/data` workspaces volume, whose attachment is pinned to web-1,
so a web-1 retirement must account for that volume too. Both are outside this census, which covers only what a
birth must recreate.
