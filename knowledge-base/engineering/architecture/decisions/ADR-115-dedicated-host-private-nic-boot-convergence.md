---
adr: 115
title: Dedicated hosts self-converge their private NIC at boot and self-report it
status: accepted
date: 2026-07-15
amends: none
supersedes: none
issue: 6415
related: [6400, 6405, 6288, 6122, 6242]
related_adrs: [ADR-096, ADR-100, ADR-103, ADR-068, ADR-082]
brand_survival_threshold: single-user incident
---

# ADR-115: Dedicated hosts self-converge their private NIC at boot and self-report it

## Status

**Accepted — for the REGISTRY host only.** Explicitly **not** class-wide: see the normative
blocker below. Extending it to git-data or inngest requires clearing that blocker first.

## Context

On 2026-07-14 the zot registry host was recreated via `registry-host-replace`. It came up
holding only its public `eth0`: cloud-init rendered a netplan with no private interface, so the
host never held `10.0.1.30`. zot itself was healthy and serving `:5000`. The fleet's **primary
image-pull path was unreachable for ~14 days** (#6400) and **every health signal stayed green**
for the entire window.

Three facts make this a structural problem rather than a one-off:

1. **The race cannot be fixed in Terraform.** `hcloud_server_network` is a **separate, additive
   ONLINE attach** (`network.tf:9-13`) — an inline `network {}` block on the server would
   force-replace the host, so the attach is a distinct resource. It needs a *created* server,
   and a created server is *already booting*. There is no ordering that guarantees the attach
   lands before the guest's network stage. The control plane reports "attached" while the guest
   is misconfigured; `registry-host-replace`'s own gate asserts `nic_recreated>=1` from **tfplan**
   (`tests/scripts/lib/registry-host-replace-gate.sh:44-46`), which proves Terraform *planned*
   the attach — never that the guest configured it. This exact symptom on this exact host is
   already documented in `learnings/2026-07-07-immutable-redeploy.md` Sharp edge 2 (#6122).

2. **A NIC-less host is invisible to every existing signal.** It retains **public** egress, so
   `registry_disk_prd` keeps pinging green; and the boot readiness poll targets `localhost:5000`
   (the `curl … http://localhost:5000/v2/` loop in `cloud-init-registry.yml`'s zot-launch
   `runcmd`), which succeeds because zot binds `0.0.0.0:5000` (its `-p 0.0.0.0:5000:5000`
   publish). Neither can be re-thresholded into covering this — they are structurally blind, not
   mis-tuned. Compounding it, the ADR-096 GHCR fallback means **deploys keep succeeding**, so
   the deploy pipeline is an actively misleading proxy (asserting deploy success as proof of zot
   reachability *is* the #6400 failure).

3. **The fix must live on the host.** The registry resources are an `OPERATOR_APPLIED_EXCLUSION`
   (`zot-registry.tf:16-22`): they are applied by the operator's **full untargeted** apply plus
   the 12h drift detector, **not** the per-PR `-target=` list (which bridges over SSH to the
   existing web host and cannot provision a new one). A reboot bolted into the dispatch job
   would therefore cover only the maintenance path and leave the **primary** provisioning path —
   a from-empty `terraform apply` — uncovered.

Point 3 is the headline: today a from-empty `terraform apply` can yield an unreachable registry
that needs an operator to notice and reboot it. That violates
`hr-fresh-host-provisioning-reachable-from-terraform-apply`. **That, not "IMDS resilience", is
the decision this ADR records.**

## Decision

A dedicated Hetzner host whose function depends on the private network **MUST**:

1. **Self-verify** its expected private IP after boot, from a constant **baked at template
   time** — so the check has zero runtime dependencies and the metadata service is
   **corroboration, never the trigger**.
2. **Converge** it within a **bounded budget**, using **one** primitive: a guarded reboot. A
   reboot re-runs cloud-init's own renderer, so MTU and routes are correct **by construction**,
   and it is the recovery **verified in production** (Sharp edge 2). The gate is:

   ```
   ip_present=false && imds_nets>0 && uptime_s>600 && reboot_count<2
   ```

   - **IMDS corroboration** — never reboot on zero evidence. A standing alarm that fires on its
     own probe fault trains the operator to ignore it; a *host* that reboots on its own probe
     fault is the same mistake with teeth.
   - **`uptime_s>600`** — says "don't reboot a host that just booted" directly. It needs zero
     persistent state, cannot be corrupted, is already an emit field, and makes the boot
     invocation naturally a no-op for the reboot arm.
   - **Counter on the ROOT disk**, keyed by instance-id, **literal cap 2**, written **before**
     the reboot. A cap of 2 makes a storm *definitionally* impossible, so no cooldown is needed.
     A host replace gives a new root disk ⇒ a fresh budget, for free.
3. **Emit a discriminating event on EVERY run** over the host's existing telemetry transport.

The single-sourcing of the IP is part of the decision, not an implementation detail: baking the
constant into the guard promotes it to **reboot authority**. If the Terraform literal and the
baked copy drift, the guard bakes a wrong `EXPECTED_IP`, `ip_present` is false forever, IMDS
*corroborates* (the network genuinely is attached), and the guard **reboots a healthy host to
the cap and then goes terminal**. The IP therefore has exactly one definition
(`local.registry_private_ip`).

### NORMATIVE BLOCKER (binding on any future extension of this ADR)

> The reboot primitive **MUST NOT** ship to a host whose storage unlock lives in `runcmd`
> without a reboot-safe equivalent (`crypttab` or a keyscript).
>
> **git-data is excluded until that is fixed.** Its `luksOpen` is in `runcmd`
> (`cloud-init-git-data.yml:163`), which is **per-instance and does not re-run on reboot**;
> there is **no `crypttab` anywhere in the repo** (verified); and its fstab entry carries
> `nofail` (`:118`). A reboot would therefore leave the fleet's most irreplaceable data store
> **silently unmounted**.

This blocker lives here rather than in the plan or the tracking issue on purpose: a constraint
discovered during planning belongs in the durable artifact, because the ADR outlives both.

### Authority note

`hr-prod-host-config-change-immutable-redeploy` does **not** bless a self-reboot. It
acknowledges a reboot may be *needed* during an operator-driven `-replace`; it does not
authorize a host to **decide to reboot itself**. This ADR earns that authority on its own
merits — bounded, corroborated, capped, counter on the root disk, emitted before acting — not
by citing a rule that does not say it.

## Consequences

**Positive.** A from-empty apply now converges to a reachable registry without operator memory,
which is what `hr-fresh-host-provisioning-reachable-from-terraform-apply` requires. The observed
#6400 failure moves from **~14 days** to **~30 min** (5-min emit, 30-min alarm poll). The event
also settles the H1-vs-H2 question empirically on the next boot, and the guard incidentally
fixes a **pre-existing** bug reachable from *any* reboot cause: `runcmd` never re-runs, so only
the `nofail` fstab entry remounts the store, and a slow volume node leaves zot bind-mounted on
an empty dir (404s fleet-wide) while `nic_ok=true`.

**Negative / accepted.**

- The host may reboot itself, at most twice per instance. Accepted: the alternative is a silent
  fleet-wide outage. `uptime_s>600` and the healthy path's zero-mutation guarantee bound the
  blast radius, and AC3 asserts a healthy host is never touched.
- **A successful self-heal emits `nic_ok=true`**, so the terminal alarm cannot see it. Without a
  dedicated **advisory** branch the race would self-heal silently forever and never be reported —
  a *lost ceiling*, since today it at least eventually surfaces as an outage. The advisory branch
  is therefore load-bearing, not nice-to-have.
- **Residual, accepted:** the guard's subject is the host's **local** NIC state. It cannot detect
  "the private net is broken from a consumer's perspective while the host thinks it is fine."
  That needs an off-host probe (deferred; see below). For the **observed** failure this is
  sufficient — #6400's host had no `10.0.1.30` **at all**.

## Alternatives considered

| Alternative | Verdict |
| --- | --- |
| **`cloud-init clean --logs && cloud-init init --local`** (the issue's own proposal) | **Rejected — three verified failure modes.** (a) `cloud-init-registry.yml:294` appends fstab with a bare `echo >>` and no `grep -q` guard (git-data's `:170` has one) ⇒ duplicate mounts on every re-run. (b) `clean` wipes the datasource semaphore, so a transient IMDS failure on the re-run yields `DataSourceNone` ⇒ default network config ⇒ **the public NIC is lost too** ⇒ unrecoverable on a deny-all no-SSH host. (c) it re-runs the fail-closed isolation check (FATAL at `:351-353`), so a Doppler blip means zot never relaunches. *The proposed cure for a transient IMDS blip is triggered by a transient IMDS blip.* |
| **A netplan drop-in as the converge primitive** | **Rejected.** Its trigger is a strict subset of the reboot's, and it is the lower-fidelity path (the reboot gets correct MTU/routes from cloud-init's own renderer). Unbudgeted, it would re-apply every 5 min, bouncing **public** egress on a deny-all no-SSH host — invisible to a 25-min absence window. That is #6400's own signature, self-inflicted. |
| **Fix it in Terraform** (ordering, or a reboot in the dispatch job) | **Rejected.** No ordering can win an additive online attach. And the registry resources are an `OPERATOR_APPLIED_EXCLUSION`, so a dispatch-job reboot leaves the primary provisioning path uncovered. |
| **A `Type=oneshot` unit instead of `/etc/cron.d`** | **Rejected.** A boot-only oneshot cannot heal an attach that lands *later* (H2, the leading hypothesis). `/etc/cron.d` is this host's established cadence and already carries the `doppler run` wrapper. It also avoids the oneshot-liveness trap where `inactive` reads as healthy. |
| **Ship git-data + inngest too** (the issue's stated scope) | **Rejected on safety** — see the normative blocker. Both hosts also fail *loudly* today, so they lack the silent-failure property that motivates #6415. |
| **An off-host probe as required-for-close** | **Deferred** (#6415 stays open for it). It is greenfield: the web-host delivery site is unresolved (`ignore_changes=[user_data]` ⇒ not cloud-init), its arming is blocked (`ignore_changes=[paused]` makes a source flip a **no-op**), the cadence mismatches (`period=60/grace=30` vs a 60s cron floor ⇒ flapping), and `betterstack_paid_tier=false` ⇒ email-only, no escalation. |

## Observability

`SOLEUR_PRIVATE_NIC` is emitted every 5 min plus once at boot, over the **existing** Better Stack
Logs transport (no new sink, no new secret), read by `scripts/zot-restart-loop-alarm.sh` →
`scheduled-zot-restart-loop.yml` → a deduped `action-required` issue.

**The Better Stack POST is the ONLY channel.** This host runs no Vector agent, no rsyslog
forwarder and no MTA, so cron discards job stderr and the boot invocation's stderr lands in
on-box `/var/log/cloud-init-output.log` — unreachable on a deny-all, no-SSH box. Every `echo >&2`
in the guard is therefore a **breadcrumb for a post-mortem, not a layer**: do not cite it as
fail-loud cover. The absence probe in the alarm is what covers a dead emit, which is why it
cross-checks the sibling `SOLEUR_ZOT_DISK` producer rather than assuming "no rows = fresh host".

Nine fields. Eight are read by the alarm (`nic_ok`, `converged_by`, `imds_rc`, `imds_nets`,
`reboot_count`, `zot_store_mounted`, `uptime_s`, and `boot_id` via the newest-boot scoping);
`zot_last_err` is not parsed by design — it **bounds the trusted region** and is stripped before
any key=value read.

The field set discriminates every competing hypothesis in **one** event:

| Signature | Meaning |
| --- | --- |
| `imds_rc != 0` | **H1** — a real metadata-service blip (the issue's original framing). |
| `imds_rc = 0 && imds_nets = 0` | **H2** — the structural attach race (the leading hypothesis). |
| `imds_nets > 0 && converged_by != already` | A third, previously unnamed mode: the attach landed and the guest never configured it. |
| `nic_ok = true && reboot_count > 0` | The race is real and the guard healed it — the **advisory** branch. |

`zot_last_err` carries that exact name and is **trailing** because
`scripts/lib/zot-telemetry-parse.sh:27` strips the **literal** ` zot_last_err=` to bound the
trusted region; a `last_err=` would silently never be stripped and the spoof guard would never
fire. `host` is deliberately absent — the immutable replace reuses the Terraform hostname, so
`boot_id` is what separates old-host from new-host events.

Verification is SSH-free:

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  --since 30m --grep SOLEUR_PRIVATE_NIC --limit 20
```

**Zero rows is ambiguous, not "no signal"** (creds unset, cloud-init died pre-Doppler, guard
crashed, ingest lag, host never booted). Run `bash scripts/zot-restart-loop-alarm.sh` — its
control-marker → LOOKBACK → absence ladder discriminates those.

## Diagram

No new element, actor, or store — Hetzner and Better Stack are already modelled. Two
**description-level** edits are owed in `knowledge-base/engineering/architecture/diagrams/model.c4`,
which is maintained at that granularity: `:396` (`zotRegistry -> betterstack`) enumerates only
`SOLEUR_ZOT_DISK` and gains a second event type, and `:400` (`github -> betterstack`) names only
the restart-loop alarm and gains NIC polling. `:264` (`betterstack`) is **not** edited — it
becomes falsified only if the deferred off-host probe arms `registry_prd`. Precedent: commit
`c749e4e6a` edited the C4 for a structurally identical observability change.

## Relationship to other ADRs

**Extends ADR-103** (reprovision *path* → guest-side *convergence*). **Complements ADR-096 /
ADR-100** (the dispatch mechanism). **Inherits ADR-082's** fail-open, in-surface,
discriminating-telemetry doctrine. No collision.
