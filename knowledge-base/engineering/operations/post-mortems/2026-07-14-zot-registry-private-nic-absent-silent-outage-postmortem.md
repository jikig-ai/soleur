---
title: "zot registry unreachable for ~14 days — host booted with no private NIC; every health signal stayed GREEN"
date: 2026-07-14
incident_pr: 6422
incident_window: "2026-06-30 (registry-host-replace) → 2026-07-14 (~14 days; zot private-net pull path dead, 0 zot pulls)"
recovery_at: "2026-07-14 — reactive: forced a full cloud-init re-run via rescue mode; structural fix in PR #6422"
suspected_change: "registry-host-replace recreated hcloud_server.registry; the additive hcloud_server_network online-attach landed after cloud-init's network stage (or its IMDS fetch blipped), so netplan was rendered with only the public eth0"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - image-pull-path availability (zot private-net registry unreachable at 10.0.1.30:5000)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- **operator** — the founder (sole operator).
- **registry host** — `hcloud_server.registry`, the deny-all / no-SSH Hetzner box running zot (ADR-096).
- **fleet** — the web hosts + CI, which pull platform images from `10.0.1.30:5000` over the private net.

## Status

**Resolved.** Reactively recovered 2026-07-14 (rescue-mode cloud-init re-run). The structural fix —
an on-host converger + a discriminating `SOLEUR_PRIVATE_NIC` self-report — ships in PR #6422
(ADR-115). Residual scope is tracked (see Action Items).

## Symptom

zot "mysteriously down." From any peer on the private net: **100% ping loss + TCP timeout** at
`10.0.1.30:5000`, while `hcloud server describe` showed the host **running and attached**. zot itself
was healthy and serving on `:5000`.

**The distinguisher that was missed for 14 days:** a down container gives connection **refused**; an
unconfigured NIC gives **timeout + ping loss**.

## Incident Timeline

| When | What |
|---|---|
| ~2026-06-30 | `registry-host-replace` recreates `hcloud_server.registry`. cloud-init's `.../hetzner/v1/metadata/private-networks` fetch does not yield the private NIC (network-unreachable on the IPv6 link-local + 169.254.169.254), so netplan is written with **only** the public `eth0`. The host holds no `10.0.1.30`. |
| ~2026-06-30 → 2026-07-14 | **~14 days.** Every deploy silently pulls from GHCR via the ADR-096 atomic fallback instead of zot. **Zero zot pulls.** No alarm fires. |
| 2026-07-13 12:32 | A *separate* fault — the GHCR read credential's login-ok/pull-deny split — freezes the deploy pipeline (#6400). Prod sticks on `0.213.2`. The registry outage is now **load-bearing**, because the fallback it silently depended on is itself degraded. |
| 2026-07-14 | Investigating #6400, the operator finds the registry holds no private IP. Recovered by forcing a full cloud-init re-run via rescue mode. |
| 2026-07-14 | #6415 filed (root-cause fix). PIR (this document) + structural fix in PR #6422. |

## Participants and Systems Involved

Hetzner cloud (`hcloud_server` + `hcloud_server_network`), cloud-init/netplan, zot (ADR-096),
Better Stack Logs (source 2457081), GHCR (the fallback), the operator.

## Detection (+ MTTD)

**MTTD ≈ 14 days — and detection was INCIDENTAL, not signalled.** The registry outage was found only
while diagnosing an unrelated deploy freeze. Absent #6400, it would still be running.

This is the core finding: **every existing signal was structurally blind.**

- `registry_disk_prd` heartbeat: **GREEN throughout.** A NIC-less host keeps **public** egress, so it
  kept pinging.
- Boot readiness poll: **passed.** It targets `localhost:5000`, which succeeds because zot binds
  `0.0.0.0:5000`.
- Deploy pipeline: **green.** The ADR-096 GHCR fallback is atomic, so deploys kept succeeding —
  making the deploy pipeline an *actively misleading* proxy.
- `registry-host-replace`'s own gate: **passed.** It asserts `nic_recreated>=1` from **tfplan** —
  proving Terraform *planned* the attach, never that the **guest** configured it.

## Triggered by

`registry-host-replace` (a `user_data` change is `ForceNew`), which recreates the server and
re-runs the additive online attach.

## Root-cause hypothesis (triage)

Two hypotheses were held as competing; the fix is correct under both, and the new emit
**discriminates them in one event**:

- **H1 — transient IMDS blip.** The issue's original framing. *Unverified* — no telemetry existed;
  that absence **is** the gap.
- **H2 — structural ordering race (leading).** `hcloud_server_network` is a **separate, additive
  ONLINE attach**: it needs a *created* server, and a created server is *already booting*. **No
  Terraform ordering can win this race.** Documented on this exact host in
  `learnings/2026-07-07-immutable-redeploy.md` Sharp edge 2 (#6122).

## Resolution

Reactive: forced a full cloud-init re-run (rescue mode) to re-render netplan with the attach present.

Structural (PR #6422 / ADR-115): the host now self-converges. A guard asserts its expected private IP
every 5 min + at boot; if absent **and** IMDS corroborates the expected address **and** uptime > 600s
**and** a durable root-disk budget (cap 2) allows, it reboots — which re-runs cloud-init's own
renderer, so MTU/routes are correct by construction. It emits `SOLEUR_PRIVATE_NIC` on **every** run.

## Recovery verification

SSH-free (`hr-no-ssh-fallback-in-runbooks`):

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  --since 30m --grep SOLEUR_PRIVATE_NIC --limit 20
```

Expect ≥1 event with `nic_ok=true` and `zot_store_mounted=true`. **Record `converged_by`** — it is the
empirical H1-vs-H2 verdict (`already` ⇒ no race this boot; `reboot` ⇒ the race is real and the guard
healed it). **Zero rows is ambiguous, not "no signal"** — run `bash scripts/zot-restart-loop-alarm.sh`,
whose control-marker → LOOKBACK → absence ladder discriminates the causes.

## Root Cause(s) — 5-Whys

1. **Why was zot unreachable?** The host held no `10.0.1.30`.
2. **Why?** cloud-init rendered netplan with only the public `eth0` — the private NIC was not
   configured at network-stage time.
3. **Why?** The private-network attach is a **separate, additive online attach** that can land after
   the guest's network stage (H2), and/or the IMDS fetch blipped (H1). No Terraform ordering can
   guarantee otherwise.
4. **Why did it run 14 days?** Every health signal is structurally blind to it: a NIC-less host keeps
   **public** egress (heartbeat green), the readiness poll targets `localhost` (green), and the GHCR
   fallback keeps **deploys** green.
5. **Why was there no signal for the thing that actually broke?** Nothing on the host asserted the
   invariant that actually matters — *"I hold my expected private IP."* Every probe measured a proxy.

**Root cause:** an un-monitored, structurally-racy invariant on a blind (deny-all, no-SSH) surface,
where all adjacent signals fail **green**.

## Versions of Components

zot per `local.zot_image` (digest-pinned); Hetzner cloud-init/netplan (Ubuntu); Terraform hcloud
provider. Prod was frozen at `0.213.2` during the overlapping #6400 window.

## Impact details

### Services Impacted

The fleet's **primary image-pull path** (zot at `10.0.1.30:5000`) — dead for ~14 days. **The
user-serving path was NOT affected**: `model.c4:260` — the registry "replaces GHCR on the **pull
path**"; no user request touches `10.0.1.30`.

### Customer Impact (by role)

**None directly observed.** Beta users = 0 during the window, and the serving path was never touched.
The real cost is **latent**: for 14 days every deploy silently depended on a fallback nobody knew was
load-bearing. On 2026-07-13 that fallback degraded (#6400) and **no fix of any kind could reach
production** — prod froze on `0.213.2`. That is the `single-user incident` threshold: the ship path
itself was one fault from a total stop, and *was*.

### Revenue Impact

None (0 beta users; no serving impact).

### Team Impact

Operator time: the #6400 investigation was prolonged by chasing "zot is down" when zot was healthy.
The refused-vs-timeout distinguisher was the unlock.

## Lessons Learned

- **A green signal over a proxy is worse than no signal.** Three signals were green and all three
  measured something other than the invariant. Adding a *threshold* to any of them would not have
  helped — they are structurally blind, not mis-tuned.
- **The control plane is not the guest.** The replace gate asserted `nic_recreated>=1` from tfplan —
  Terraform *planned* the attach. Nothing asserted the guest *configured* it.
- **An operator-memory dependency is not a control.** `learnings/2026-07-07-immutable-redeploy.md`
  Sharp edge 2 already said *"always verify private-net reachability after a `-replace`"*. This
  incident is that instruction failing. It is now automated for the registry.
- **A fallback nobody monitors becomes load-bearing silently.** The GHCR fallback absorbed 14 days of
  failure and made it invisible — then degraded, converting a latent fault into a total deploy stop.

### Where we got lucky

The overlapping #6400 credential fault. Without it nobody would have looked, and the registry would
still be dark. **Detection was luck, not design** — that is the whole reason for the new signal.

### What went well

The reactive recovery was fast once diagnosed. The zero-downtime property held: the store volume
survived, and the serving path was never touched.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #6415 | On-host private-NIC converger + `SOLEUR_PRIVATE_NIC` discriminating self-report + alarm (terminal / advisory / absence) — MTTD ~14 days → ~30 min. ADR-115. PR #6422. Closes only after the post-merge `registry-host-replace` verifies `nic_ok=true`. | open |
| #6438 | Deferred scope: the off-host consumer-perspective probe; generalizing the guard to git-data (blocked on a reboot-safe LUKS unlock — ADR-115 normative blocker) + inngest; and the web hosts, which share the race AND the silent-failure property via the same GHCR fallback. | open |
| #6448 | `docker-daemon.json` hardcodes `10.0.1.30:5000` while `server.tf`'s probe greps the file it just delivered (self-referential) — a drifted `local.registry_private_ip` fails **silent** in exactly this incident's shape. | open |
