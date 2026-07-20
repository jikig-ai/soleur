---
title: 'Immutable prod-host redeploy — -target the dependents, and verify the private NIC after a -replace'
date: 2026-07-07
category: engineering
tags: [terraform, hetzner, immutable-infra, cloud-init, private-network, zot, provisioning, apply-path]
problem_type: infra_operational
resolution_type: workflow_fix
severity: high
issues: ['#6122']
---

# Immutable prod-host redeploy: the sharp edges

Backing detail for hard rule `hr-prod-host-config-change-immutable-redeploy`. A config/package/daemon
change to an already-running prod host ships by editing cloud-init/Terraform and re-provisioning the
host immutably — never an in-place SSH/rescue edit, even a one-liner. Rescue/SSH stays **read-only
diagnosis** (`hr-all-infrastructure-provisioning-servers`, `hr-no-ssh-fallback-in-runbooks`).

## Why immutable, not in-place

The `user_data`/cloud-init edit is `ForceNew`, so it drives a `terraform apply` server `-replace`.
An in-place SSH/rescue edit (e.g. hand-editing zot's `config.json` + reboot) leaves the running host
diverged from what cloud-init would reproduce — the next legitimate re-provision silently reverts it.
The data **volume survives** a server `-replace` (only `user_data` is ForceNew), so a store-and-serve
host keeps its data; a dark/pre-cutover host is the ideal time. This is NOT the ci-deploy image-swap
(pull new immutable image → replace container) — that's the app layer and already immutable.

## Sharp edge 1 — `-target` pulls dependencies, NOT dependents

A server `-replace` must **also** `-target` the server's dependent attachments:
`hcloud_server_network`, `hcloud_volume_attachment`, `hcloud_firewall_attachment`. `terraform -target`
walks *upstream* (dependencies) but not *downstream* (dependents), so a bare
`-target=hcloud_server.<h>` recreates the host with:
- no `hcloud_server_network` → **new host off the private net** (fleet can't reach it), and/or
- no `hcloud_firewall_attachment` → **public-exposed boot** before the firewall re-attaches.

## Sharp edge 2 — a fresh Hetzner host may boot with its private NIC down

Even with `hcloud_server_network` correctly `-target`ed (control plane shows the host **attached at its
private IP**), the **guest** may not bring the private interface up on first boot after a `-replace` —
the additive online-attach can land after cloud-init's network stage. Symptom (observed #6122): from a
peer on the private net, the new host is **100% ping loss + TCP connection timeout** at its private IP,
while `hcloud server describe` shows it running and attached, and *other* freshly-created hosts on the
same net are reachable. A **soft reboot** brings the NIC up (cloud-init re-runs the network stage with
the attachment present). A down container gives connection *refused*; an unconfigured NIC gives
*timeout* + ping loss — use that to distinguish.

> **AUTOMATED for the registry host as of 2026-07-15 (#6415 / ADR-115).** The instruction this
> section used to carry — *"always verify private-net reachability after a `-replace`"* — was an
> **operator-memory dependency**, and it failed exactly as you would expect: #6400 is this same
> sharp edge, unnoticed for **~14 days** because nobody remembered to check and no signal could
> tell them. Remembering is not a control.
>
> The registry host now converges its own private NIC (`soleur-private-nic-guard.sh`, every 5 min
> + at boot) and emits `SOLEUR_PRIVATE_NIC` on every run, which
> `scripts/zot-restart-loop-alarm.sh` turns into a deduped `action-required` issue. **Do not
> hand-verify the registry after a `-replace`** — read the event instead (no SSH):
>
> ```
> doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
>   --since 30m --grep SOLEUR_PRIVATE_NIC --limit 20
> ```
>
> `converged_by=already` ⇒ no race on this boot; `converged_by=reboot` / `reboot_count>0` ⇒ the
> race is real and the guard healed it (it also files an advisory issue, because a successful
> self-heal emits `nic_ok=true` and would otherwise be invisible).
>
> **Still manual for `git-data` and `inngest`** — the guard is registry-only. ADR-115 carries a
> normative blocker: a reboot primitive must not ship to a host whose storage unlock lives in
> `runcmd` without a reboot-safe equivalent, and git-data's `luksOpen` does (no `crypttab`,
> fstab `nofail`), so a reboot would silently unmount the store. For those two hosts the
> verify-after-`-replace` instruction above still stands.

## Sharp edge 3 — watch the store volume, and the diagnosis path

Two more things the #6122 recovery surfaced on the zot registry host:
- **Volume capacity.** The zot store is a 10 GB volume (dedup on). After recovery, small image pushes
  (inngest bootstrap) succeeded but large ones (the web-platform image) failed the blob `PATCH` with
  `500 Internal Server Error` while existing images stayed readable — the ENOSPC signature of a
  near-full volume. Size the store for the *largest* image set it must hold, not the current one, and
  alarm on free space.
- **Diagnosis reachability.** The registry host is deny-all-public-ingress and authorizes only the
  operator's default hcloud SSH key — NOT the `ci_ssh` key the CF-tunnel SSH bridge uses — so it can't
  be `df`/`docker logs`-diagnosed through the standard bridge when its private NIC is also down. Give a
  deny-all-ingress host a reachable read-only diagnosis path (authorize `ci_ssh`, or a push heartbeat
  that reports disk) or it becomes a black box exactly when it breaks.

## Verified as a side effect

The docker2s2 compat fix (zot `"compat": ["docker2s2"]`) works: after recovery, the Docker-schema2
`soleur-inngest-bootstrap` image mirrored GHCR → zot cleanly (the manifest `PUT` that 400'd pre-fix
now succeeds).
