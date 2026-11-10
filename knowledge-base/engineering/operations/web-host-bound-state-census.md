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
| C3 | Per-host Better Stack heartbeat URLs for the host probes (nic-guard, bash-synthetic, zot-consumer) | **Keyed, not delivered.** `web-probe-envwrite.sh` derives the Doppler key name from the host key (`WEB_NIC_GUARD_URL_<KEY>` and siblings) at birth. The secret value must already exist in Doppler for that key. | `web-probe-envwrite.sh` (`HOST_UPPER` derivation) | One Doppler secret per probe for the new key, before its birth |
| C4 | Per-host kernel-marker dead-man heartbeat | **Keyed by hand.** One `betteruptime_heartbeat` resource per web key (`host_kernel_web_1`, `host_kernel_web_2`). A new key has no heartbeat until one is added. | `uptime-alerts.tf` | A `host_kernel_web_<n>` resource (or a `for_each` over `var.web_hosts`) in the same PR as the key |

Rows C3 and C4 are the forcing function for the `web-3` PR (#9421 sequence, PR 5). The suite
counts the `host_kernel_web_*` heartbeats against the `var.web_hosts` keys, so adding a key without
its heartbeat reds CI.

The users' worktrees under `/var/lib/soleur/worktrees` on the root disk are host-bound data, not
configuration. They are lost with the server, and the plan's flush step (PR 6) is what covers them.
They are outside this census, which covers only what a birth must recreate.
