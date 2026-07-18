---
adr: 123
title: Web hosts self-report their private NIC but do NOT self-converge (detect + emit + alarm, no reboot)
status: accepted
date: 2026-07-18
amends: none
supersedes: none
issue: 6438
related: [6400, 6415, 6459, 6538, 6548]
related_adrs: [ADR-115, ADR-103, ADR-117, ADR-082]
brand_survival_threshold: single-user incident
---

# ADR-123: Web hosts self-report their private NIC but do NOT self-converge

> **Ordinal resolved to ADR-123.** The provisional ADR-122 collided with #6653's
> sandbox-security-controls ADR-122 (merged to `main` first); this file and its
> cross-references were renumbered to ADR-123 before merge.

## Status

**Accepted — for the WEB host(s).** This ADR is the web-host counterpart to ADR-115, which is
**deliberately REGISTRY-only** and stays that way. This record does **not** amend, extend, or
dilute ADR-115: it makes a *structurally different* decision for a different host class, and it
cites ADR-115's own normative reboot-blockers as the reason the difference is mandatory rather
than optional. #6438 §3.

## Context

ADR-115 established that a dedicated Hetzner host whose function depends on the private network
must self-verify its private IP at boot and **converge** it with a bounded, guarded **reboot**
(`ip_present=false && imds_nets>0 && uptime_s>600 && reboot_count<2`). That decision was earned
narrowly, on the registry host's merits, and ADR-115's Status is explicit that it is **not
class-wide**: extending the reboot primitive to another host requires clearing its two normative
blockers first.

#6438 §3 asks for the private-NIC self-report guard on the web host(s). The self-*report* half
(detect the NIC-absent / path-broken condition and emit a discriminating `SOLEUR_PRIVATE_NIC`
event) is unambiguously wanted: a web host that boots without `10.0.1.10` loses its private path
to zot and git-data, and — exactly as in #6400 — every existing health signal can stay green
while the product silently rots. The self-*converge* half (the reboot) is where the web host and
the registry host part company.

<!-- lint-infra-ignore start: decision rationale — describes why the web host must NOT self-reboot; prescribes no human step -->
**A reboot on the web host is not available as a primitive.** The web host is the sole live
origin for the operator's product. `apply-web-platform-infra.yml:878` states plainly that a
web-1 reboot **"would power-off the sole live origin"**; web-2 was retired 2026-07-17
(#6538/#6463), so the fleet is single-host and there is no peer to absorb the traffic. Rebooting
to fix a private-NIC fault would convert a *degraded* origin (private net down, public path and
GHCR fallback still serving) into a *dark* origin (nothing serving at all) — trading a partial,
recoverable outage for a total one. That is strictly worse for the target user than the fault it
would be trying to heal.
<!-- lint-infra-ignore end -->

## Decision

**On the WEB host(s), the private-NIC guard MUST detect + emit + alarm, and MUST NOT reboot.**

<!-- lint-infra-ignore start: decision items describe the automated guard's own behavior (self-verify/emit/ping/do-not-converge); no human step -->
1. **Self-verify** the expected private IP after boot, from a constant **baked at template time**
   (`EXPECTED_IP='${private_ip}'`, sourced per-host from `var.web_hosts[each.key].private_ip`,
   never a literal) — the same zero-runtime-dependency, IMDS-as-corroboration discipline ADR-115
   requires.
2. **Emit** a discriminating `SOLEUR_PRIVATE_NIC` event on every run over the host's existing
   Better Stack Logs transport, from web-1 (in addition to the registry, which already emits it).
   The event carries structured fields (NIC-absent vs path-broken vs serviceability), not a bare
   boolean.
3. **Ping** a dedicated liveness heartbeat (`betteruptime_heartbeat.web_nic_guard`, `for_each =
   var.web_hosts`) on every healthy run, so the fault-emitter is observable-when-healthy: a
   `SOLEUR_PRIVATE_NIC` emit that never fires is indistinguishable from "the guard is dead"
   (ADR-082's in-surface doctrine).
4. **Do NOT converge.** No `reboot`, no `$REBOOT_BIN`, no `converged_by=reboot` path exists on
   the web host. Remediation of a genuine NIC fault is deferred to #6459 (active-active-N, so a
   peer exists to depool onto) plus operator action — never a self-inflicted power-off of the
   only origin.
<!-- lint-infra-ignore end -->

### Why the reboot is blocked, in ADR-115's own terms

ADR-115 does not merely *omit* a reboot mandate for other hosts; it carries a **NORMATIVE
BLOCKER** binding on any future extension of its reboot primitive:

> The reboot primitive **MUST NOT** ship to a host whose storage unlock lives in `runcmd`
> without a reboot-safe equivalent (`crypttab` or a keyscript).

and an **Authority note**:

> `hr-prod-host-config-change-immutable-redeploy` does **not** bless a self-reboot. … This ADR
> earns that authority on its own merits — bounded, corroborated, capped, counter on the root
> disk, emitted before acting.

Both apply against the web host and both come out **against** a reboot:

- **The authority is not transferable.** ADR-115 earned self-reboot authority for *one* host by a
  specific argument: an unreachable registry cannot be fixed any other way, its store is
  disposable, and a bounded capped reboot re-runs cloud-init's renderer to get the NIC back. The
  web host fails the first premise — a private-NIC fault does **not** make it unreachable (public
  `eth0` + CF-proxied origin + GHCR fallback keep it serving), so a reboot is not the only remedy;
  it is a *worse* remedy that darkens a still-serving origin. The authority ADR-115 earned for the
  registry does not carry to a host where its justifying premises are false.
- **The blast-radius asymmetry is the same shape ADR-115 draws for git-data.** ADR-115 excludes
  git-data from the reboot primitive because "the primitive is the same; the blast radius is not"
  — the registry's store is disposable, git-data's is irreplaceable. Here the same logic excludes
  the web host on a *different* axis: the registry can absorb a reboot because a NIC-less registry
  is already dark, so a reboot can only improve it; a web-host reboot takes a **partially-serving
  sole origin to fully dark**, so it can only make it worse.

Citing ADR-115's blockers as the *reason* web hosts do not reboot keeps ADR-115's narrow,
hard-won scope intact instead of stretching it to a host it was never argued for.

### Recorded divergence from ADR-115

<!-- lint-infra-ignore start: comparison table — records ADR-115's reboot vs this ADR's no-reboot divergence; prescribes no human step -->
| Axis | ADR-115 (registry) | ADR-123 (web host) |
| --- | --- | --- |
| Self-verify private IP at boot from a baked constant | Yes | Yes |
| Emit discriminating `SOLEUR_PRIVATE_NIC` on every run | Yes | Yes |
| Dedicated liveness heartbeat (observable-when-healthy) | `registry_prd` liveness beat | `web_nic_guard` (`for_each = var.web_hosts`) |
| **Converge the fault** | **Yes — bounded, capped, guarded self-reboot** | **No — remediation deferred to #6459 + operator** |
<!-- lint-infra-ignore end -->

The registry **self-converges** via a bounded reboot; the web host **self-reports only**. This is
a deliberate, documented divergence, not an oversight: it is the honest consequence of the reboot
being a net-negative primitive on the sole live origin.

## Consequences

<!-- lint-infra-ignore start: consequences prose — describes the no-auto-heal trade-off and deferral to #6459 + operator; prescribes no human step -->
**Positive.** A future fresh web host (the #6459 active-active-N path — the guard is baked into
`cloud-init.yml`) self-reports a NIC-absent boot instead of running #6400's 14-days-dark. The
`web_nic_guard` liveness beat makes the emitter observable even when it has nothing to alarm
about. No path exists by which the guard can power-off the operator's only origin.

**Negative / accepted.**

- **A detected web-host NIC fault is not auto-healed.** It pages (via `SOLEUR_PRIVATE_NIC` +
  heartbeat absence) and waits for #6459 + operator remediation. Accepted: the alternative
  (self-reboot) darkens the sole origin, which is worse than a paged-but-still-partially-serving
  degradation. Single-host today further limits the immediate value — web-1 is already booted and
  its cx33 is `ignore_changes=[user_data]`-pinned, so §3 is largely **future-host** value, armed
  by construction for #6459.
- **Residual, accepted (inherited from ADR-115).** The guard's subject is the host's *local* NIC
  state. "The private net is broken from a consumer's perspective while the host thinks it is
  fine" needs an off-host probe — which is #6438 §1 / #6548 (the zot-consumer and git-data
  consumer probes shipped alongside this guard), not this ADR.
<!-- lint-infra-ignore end -->

## Alternatives considered

<!-- lint-infra-ignore start: rejected-alternatives table — each row explains why a reboot/self-heal was rejected; prescribes no human step -->
| Alternative | Verdict |
| --- | --- |
| **Port ADR-115's guarded reboot verbatim to the web host** | **Rejected.** A web-host reboot powers off the sole live origin (`apply-web-platform-infra.yml:878`); web-2 is retired (#6538), so there is no peer to absorb traffic. Trades a recoverable partial outage for a total one — worse for the target user than the fault. ADR-115's own reboot-blocker + authority-note forbid transferring its self-reboot authority to a host whose justifying premises are false. |
| **Amend ADR-115 to make it class-wide (registry + web)** | **Rejected.** ADR-115 is deliberately registry-only and earned its authority narrowly; a class-wide reboot mandate is exactly what its Status and normative blockers refuse. Folding the web host's *opposite* convergence decision into ADR-115 would dilute the record. A separate ADR that cites ADR-115's blockers keeps both scopes honest. |
| **Emit nothing on the web host (rely on the consumer probes)** | **Rejected.** The consumer probes (#6438 §1 / #6548) see path-broken from a *client's* view but cannot discriminate NIC-absent-at-boot on a fresh host; the §3 guard's structured emit is the in-surface signal for the boot-time fault, and its dedicated heartbeat is what proves the emitter is alive (ADR-082). |
| **Auto-heal via a netplan drop-in (no reboot)** | **Rejected here as well.** ADR-115 already rejected the drop-in as lower-fidelity and prone to bouncing egress on a deny-all box; on the web host any self-mutation of the live origin's networking carries the same power-off-adjacent risk the reboot does. Remediation is deferred to #6459 + operator, not a self-applied network change. |
<!-- lint-infra-ignore end -->

## Diagram

Two **description-level** edits in
`knowledge-base/engineering/architecture/diagrams/model.c4` (maintained at that granularity):
the `SOLEUR_PRIVATE_NIC` edge gains the **web host** as a second source, and the `betterstack`
element description gains the two new web heartbeats (`web_zot_consumer`, `web_nic_guard`). No
new element, actor, or store — Hetzner, Better Stack, zot, and git-data are already modeled. The
consumer-probe edges (web host → zot / git-data) are added for #6438 §1 / #6548 in the same
change.

## Amendment (2026-07-18, #6438/#6548) — web-1 root-doppler-unit auth contract

The probe units this ADR canonizes were delivered (commit 14075d1b) but **failed to start** on
web-1: their `ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- …'` runs as
**root**, and a root systemd service gets no `$HOME`, so the Doppler CLI's `os.UserHomeDir()` init
died `Doppler Error: $HOME is not defined` before it could exec the probe — and the units carried
no `DOPPLER_TOKEN` source (web-1 has no `/etc/default/inngest-server`; `web_colocate_inngest`
defaults false, so there was **no working root-doppler-auth systemd precedent on the host**).

**Contract for any web-host root-run `doppler run` systemd unit** (implemented in server.tf +
the three `.service` files):

- Set `Environment=HOME=/root` on the unit (doppler then uses `/root/.doppler`).
- Source a **prd-scoped `DOPPLER_TOKEN`** from a dedicated read-scoped `doppler_service_token`
  (`doppler_service_token.web_probes`, `config=prd, access=read`) written into the unit's **own**
  `/etc/default/web-<probe>` file (600) by its `*_install` provisioner — **not** the deploy-owned
  `/etc/default/webhook-deploy` (which imports `DOPPLER_CONFIG_DIR=/tmp/.doppler`, re-opening the
  #6536 ownership clash), and **not** the full-prd `var.doppler_token`.
- Keep the unit **root-run**; never `User=deploy` without `PrivateTmp=true`; never set
  `DOPPLER_CONFIG_DIR` (so doppler stays on `/root/.doppler`, never `/tmp/.doppler`).

The probe units use a **mandatory** `EnvironmentFile=/etc/default/web-<probe>` and a **hard**
`doppler run` with no degrade fallback — a deliberate divergence from the fleet's degrade-gracefully
root-doppler units (`container-restart-monitor`, `cron-egress-*` use `EnvironmentFile=-` + a
doppler-less fallback). This is correct here: a probe whose heartbeat URL is resolved *from* Doppler
is useless doppler-less, so a token/auth failure MUST surface as a failed unit + heartbeat lapse
(fail-loud), never a silent degraded run — ADR-117's "coverage that reads green while providing none"
anti-pattern.

**Observability delivery:** vector installs on web-1 only at cloud-init boot, and web-1 never
re-runs cloud-init (`ignore_changes=[user_data]`), so the probe `SyslogIdentifier`s added to
`vector.toml` Source 4 were file-only, never live on the host — the probes' own FATAL stderr never
reached Better Stack. The sole live-prod apply path (a `terraform_data` SSH provisioner —
`journald_persistent`) now also re-delivers `vector.toml` + reloads the Vector agent, and the zot
probe emits a rate-limited positive-control `SOLEUR_PROBE_CANARY` row so Source-4 liveness is a
steady-state signal (the probes are otherwise silent-on-success; luks-#6604 pattern).

**#6459 fresh-host blocker (recorded, not fixed here):** the token is delivered only by the web-1
SSH provisioner. A future baked host would get units requiring `DOPPLER_TOKEN` with nothing writing
it — the future-host cloud-init bake (#6459) MUST also write the read-scoped token into each
`/etc/default/web-<probe>` before it can run these units.

## Relationship to other ADRs

**Counterpart to ADR-115** (registry self-converges; web host self-reports only — this ADR cites
ADR-115's reboot-blockers as the reason, and does not amend it). **Consumes ADR-117** (the
`web_nic_guard` heartbeat is armed by the executable measure-then-arm gate ADR-117 canonizes).
**Extends ADR-103** (a dedicated-host boot-armed heartbeat with a mechanically-guarded non-SSH
reprovision path — here the SSH `terraform_data` provisioner onto the unrebuildable web-1).
**Inherits ADR-082's** fail-open, in-surface, discriminating-telemetry doctrine.

## References

- Issue [#6438](https://github.com/jikig-ai/soleur/issues/6438) §3 — the web-host private-NIC guard.
- [ADR-115](./ADR-115-dedicated-host-private-nic-boot-convergence.md) — the registry self-converge decision this diverges from (registry-only; not amended here).
- [ADR-117](./ADR-117-executable-heartbeat-arming.md) — executable arming; arms `web_nic_guard`.
- [ADR-103](./ADR-103-dedicated-host-boot-heartbeats-require-guarded-reprovision-path.md) — reprovision-path requirement.
- #6459 — active-active-N; where a peer exists to depool onto, the remediation this ADR defers.
- #6538/#6463 — web-2 retirement; the fleet is single-host.
- #6548 / #6438 §1 — the off-host consumer probes that cover the consumer-perspective residual.
