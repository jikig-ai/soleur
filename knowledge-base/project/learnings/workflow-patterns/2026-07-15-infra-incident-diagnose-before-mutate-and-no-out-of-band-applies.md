---
title: "Infra incident: diagnose before you mutate — an out-of-band terraform apply on an unverified hypothesis blocked the sanctioned recovery"
date: 2026-07-15
category: workflow-patterns
module: apps/web-platform/infra
issue: 6400
refs: ["#6400", "#6288", "#6415", "#6416"]
tags: [incident, terraform, drift, diagnosis, hetzner, rescue-mode, workflow]
---

# Infra incident: diagnose before you mutate

## Problem

Recovering a dead zot registry host (#6400/#6288), I burned hours cycling through four
hypotheses — **credential class → firewall → store OOM → host boot** — mutating prod at
each step *before* the diagnosis was confirmed. The actual answer (a transient first-boot
IMDS failure left the host with no private NIC) came from a **Hetzner rescue-mode disk read
of `/var/log/cloud-init.log`** — which I did **last**, and which answered it definitively in
one shot.

Worse, one of those mutations actively blocked the fix. On the (wrong) firewall hypothesis I
ran a hand-rolled `terraform apply -target=hcloud_firewall.registry` from a worktree. That:

1. **Didn't fix anything** (the firewall was never the blocker), and
2. **Diverged prod from `main`**, so the sanctioned `registry-host-replace` dispatch — which
   is destroy-guarded — aborted with `out_of_scope=1` on **three** consecutive attempts,
   because its plan wanted to revert my drift.
3. Then resisted clean reversion: `terraform apply` reported `Apply complete! 1 changed`
   while the live Hetzner firewall **still had the rules** (state said empty, API said 2
   rules). Reconciling required a direct `POST /firewalls/{id}/actions/set_rules {"rules":[]}`
   against the API, then `terraform apply -refresh-only` to re-sync state.

Net: a hypothesis-driven apply cost more time than the entire real fix, and left prod
divergent in the middle of a P1.

## Solution

**Diagnosis order for an unreachable host with no off-host telemetry:**

1. **Read, don't write.** Hetzner API first — `GET /servers/{id}` (status, `private_net`),
   `/metrics?type=cpu,disk,network`, `/actions`. Free, instant, zero blast radius.
   *(Query the BOOT window, not the current window — an idle host reads as net=0/disk=0 and
   looks "dead" when it is merely unreachable.)*
2. **Get the authoritative on-host evidence EARLY.** If the host is unreachable and ships no
   logs, go straight to a **rescue-mode disk read** — it is fully self-serve via the API and
   needs no operator console (`hr-no-dashboard-eyeball-pull-data-yourself`):
   - `POST /servers/{id}/actions/enable_rescue` with `{"type":"linux64","ssh_keys":[<id>]}`
     — inject a Hetzner-registered key whose private half is in your agent, so you get **key
     auth** instead of wrestling a password (no `sshpass` needed).
   - Temporarily scope SSH in: `set_rules` allowing **only your egress IP** on `:22`; restore
     `{"rules":[]}` immediately after. (Do NOT detach the firewall wholesale.)
   - `reboot` → SSH → the OS disk is **not** necessarily `sda` (an attached volume can take
     it): use `lsblk` and mount the partitioned boot disk (here `sdb1`, with the 60G store
     volume sitting on `sda`).
   - Read `/var/log/cloud-init-output.log` + `grep -iE 'error|fail' /var/log/cloud-init.log`
     + `/var/lib/cloud/data/status.json`.
   - Force a clean re-run when the failure is a first-boot transient:
     `rm -rf /var/lib/cloud/instance /var/lib/cloud/instances/* /var/lib/cloud/sem/*`,
     then `disable_rescue` + `reboot`.
3. **Only then mutate** — and mutate through the **sanctioned, destroy-guarded dispatch**
   (`apply-web-platform-infra.yml` `apply_target=<registry-host-replace|registry-region-migrate|…>`),
   never a hand-rolled `terraform apply`.

## Key Insight

**An out-of-band prod apply on an unverified hypothesis is doubly negative: it probably
does not fix the problem, and it can block the mechanism that would.** The guarded dispatch
paths exist precisely because a targeted apply is easy to get wrong; drifting prod from
`main` turns those guards from a safety net into a wall — exactly when you need them least.

Corollaries earned the hard way:

- **The guard aborting is information, not an obstacle.** `registry-region-migrate` refusing
  with `volume_created=0` correctly told me the volume was already in the target region (so
  it was a host-replace, not a region-migrate). Read the guard's counters
  (`out_of_scope=`, `server_replaced=`, `firewall_ok=`) — they name the mismatch.
- **`Apply complete` is not proof the world changed.** Verify the *provider's* reality
  (`GET` the resource) after any apply you are relying on. Terraform reported success while
  the live firewall was unchanged.
- **A "harmless" change is not harmless mid-incident.** My firewall rules were arguably
  correct-in-isolation and still cost three failed recovery attempts.
- **Prefer the reversible read over the plausible write.** The rescue read cost ~5 minutes
  and ended the investigation; the writes cost hours and created cleanup work.

## Session Errors

- **Mutated before diagnosing** (host recreate + firewall apply on hypotheses).
  **Prevention:** the read-first ladder above; rescue-mode read before any second mutation.
- **Hand-rolled `terraform apply` against prod**, creating drift that blocked
  `registry-host-replace` three times. **Prevention:** infra changes go through the guarded
  dispatch; if a local apply is truly required, only *after* the diagnosis is confirmed, and
  verify + revert via the provider API, not just terraform's exit code.
- **Trusted `Apply complete` over the API.** **Prevention:** `GET` the resource to confirm.
- **Attempted an operator hand-off** ("can you check the Hetzner console?") for information
  I could fetch myself. Soleur users are non-technical and may have no console access.
  **Prevention:** `hr-no-dashboard-eyeball-pull-data-yourself` covers *diagnosis* too —
  Hetzner API metrics + rescue-mode are the self-serve path; exhaust them before ever
  asking.
