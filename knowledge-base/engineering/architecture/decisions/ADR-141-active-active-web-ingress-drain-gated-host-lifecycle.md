# ADR-141: Active-active web ingress + drain-gated blue-green host lifecycle

- **Status:** adopting — flips to `accepted` when the cluster (out-of-band cattle web-2) + the de-pet of web-1 land in prod. Concurrent active-active *serving* is out of scope here (see ADR-068 / #6570).
- **Date:** 2026-07-24
- **Issue:** #6459 (blue-green host replacement — the ADR this issue asked for). Related: #6608 (inngest allowlist), #6570 (git-data root blocker), #6441/ADR-115 (fresh-boot NIC + boot-unlock), #6538 (web-2 retirement), #5274/ADR-068 (multi-host `/workspaces`).
- **Amends:** `hr-prod-host-config-change-immutable-redeploy`, ADR-103 (adds the drain-gated volume-preserving reprovision path for the `web-1` key).
- **Extends:** ADR-068 (this is the ingress + host-lifecycle layer; the serving/writer model is unchanged and its `replicas=1` invariant remains in force until ADR-068 Phase-3 GA).
- **Plan:** `knowledge-base/project/plans/2026-07-24-feat-web-active-active-cluster-iac-plan.md` (6-agent review applied).

## Context

Soleur's web tier is a single pet host `web-1` (`soleur-web-platform`, hel1). The operator's goal is a
full active-active cluster built entirely via Terraform, where every host is disposable cattle, proven by
destroying and IaC-rebuilding a host. Three repo facts constrain the design:

1. **The `/workspaces` block volume is the SOLE COPY of user work** (model.c4:186 — `refs/checkpoints/*` is
   pushed by no refspec, signup workspaces have no git remote). Destroying/reformatting it is permanent,
   unrecoverable loss. The **volume, not the host, is the protected asset.**
2. **`replicas=1` is still operationally in force** (ADR-068); the git-data CAS fence is live-but-non-rejecting.
   Two hosts serving one workspace's git index corrupts it, so *concurrent serving* is gated on ADR-068
   Phase-3 GA (shared git-data #6570 + coordinator), which is blocked (git-data pinned to an unorderable type).
3. **The programmatic anti-pooling gate was deleted 2026-07-20 (#6575)** and `server.tf:278-287` says it
   "MUST be rebuilt before any second web host is pooled."

## Live stock probe (Hetzner API, 2026-07-24 — the decided input)

Read-only query of `/v1/datacenters` (available server types) + `/v1/server_types`:

| Server type | id | Spec | Orderable in hel1/fsn1/nbg1 |
|---|---|---|---|
| `cx33` (Intel; web-1's current type) | 115 | 4c/8g x86 | **NO — none of the 3 EU DCs** |
| `cax11` (ARM; git-data's type, #6570) | 45 | 2c/4g arm | **NO — ARM entirely unavailable in EU DCs** |
| **`cpx32`** (AMD) | 110 | **4c/8g x86** | **YES — all 3 EU DCs (incl. hel1)** |

This confirms model.c4:182 against live data: `cx33` cannot be recreated, so a rebuilt `web-1` cannot come
back as `cx33`. It also confirms #6570's root-blocker framing: `cax11` (ARM) is unorderable.

## Decision

**D1 — web-2 server type = `cpx32` (4c/8g x86/AMD), born in hel1.** The direct successor to `cx33`
(same 4c/8g shape), orderable in all EU DCs, and hel1 keeps it inside the location-scoped `web_spread`
placement group (`server.tf:134`). Arch changes Intel→AMD (both x86 — the web container is x86, so ARM is
excluded regardless). web-1's eventual rebuild also targets `cpx32`.

**D2 — web-2 is an OUT-OF-BAND standby (serving-weight 0), not in the ingress rotation, until ADR-068
Phase-3 GA.** `replicas=1` (single app process) and *ingress/serving membership* are **two independent
axes**; NG1 (ADR-068) covers only the former. Because the sole-copy workspace lives on web-1's volume, any
request routed to web-2 pre-flip hits an empty workspace = the "workspace-gone" single-user incident. web-2
is health-monitored out of band (`web-2.app.soleur.ai/health`, app-readiness + Vector-shipping depth), NOT
request-serving. web-1 remains the singleton ingress (`dns.tf` app record unchanged this increment).

**D3 — Rebuild the deleted #6575 anti-pooling gate** as a fail-closed CI gate asserting web-2's
serving-weight/rotation membership is 0 until the Phase-3 flip.

**D4 — The `web-1` `for_each` key is RETAINED for the life of the cluster.** ~29 refs across 6 files
(`dns.tf:16` app record, `tunnel.tf:54/71` management-plane ingress, `server.tf:134` placement predicate,
`outputs.tf`, `ci-ssh-key.tf:73`, `workspaces-luks.tf`) hard-pin `web["web-1"]`. De-petting changes
web-1's **lifecycle**, not its roster **identity** — never a key rename (which would break DNS/tunnel/
placement) and never a destroy of `hcloud_volume.workspaces["web-1"]`.

**D5 — /workspaces failover data mechanism (pre-Phase-3) = volume-preserving reprovision, NOT
replication.** Because the volume is the sole copy and mounts to one host at a time, de-petting web-1 is a
**maintenance-window, brief-downtime** operation: write-quiesce → off-host **snapshot** (restore-tested) →
detach → recreate host (same key, `cpx32`) → reattach → **`luksOpen` (never `luksFormat`)** guarded by a
LUKS-header-presence check → verify → resume. `prevent_destroy` on the volume; the pre-destroy gate fires
on volume-destroy (snapshot-verified), never on "count un-pushed" (meaningless for no-remote workspaces).
**True zero-downtime blue-green add/drain/remove is deferred to post-ADR-068-Phase-3** (shared git-data),
where a second host can serve the same workspaces.

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| Pool web-2 into ingress now (CF connector-flip / LB weighted pool) | Routes live users to a host that cannot reach the sole-copy volume → workspace-gone single-user incident. This IS the "flip" that must be last (#6575 gate). |
| `cloudflare_load_balancer` weighted drain in this increment | Weighted drain only has a use case once hosts serve concurrently (Phase 6). Multi-connector CF Tunnel already gives health-gated failover; the LB is a paid add-on with no pre-flip value. Deferred to Phase 6. |
| Zero-downtime blue-green add/drain/remove for web-1 pre-Phase-3 | The sole-copy volume can be on one host at a time and web-2 can't serve it without shared git-data (#6570) — so genuine zero-downtime is impossible pre-Phase-3. A maintenance window is the honest mechanism. |
| Rebuild web-1/web-2 as `cx33` | Unorderable in all EU DCs (live probe). |
| Cross-DC (fsn1/nbg1) web-2 for DC-outage resilience | Loses the location-scoped `web_spread` placement group; the 2026-07-13 `-replace`-during-shortage wedge (#6393) is the cautionary precedent. `cpx32` is orderable in fsn1 too, so cross-DC remains a future option, but same-DC hel1 is chosen now for placement-group HA + rebuildability. |
| "Count un-pushed work" as the pre-destroy safety gate | Meaningless for signup workspaces (no remote — everything is un-pushed, nowhere to push); protects only commits, not committed-but-remoteless state a reformat erases. Replaced by snapshot-verified volume preservation. |

## Consequences

- **Positive:** web-2 delivers fresh-boot-readiness proof, a cattle-host template, and proven disposability
  (volume-preserving reprovision) independent of the blocked ADR-068 Phase-3 chain. The sole-copy volume is
  hardened (`prevent_destroy` + snapshot + luksOpen-not-reformat).
- **Negative / accepted:** No *concurrent* redundancy pre-flip (web-2 is a standby, not a second server of
  the same workspaces). De-petting web-1 incurs a brief maintenance-window outage. A recurring `cpx32`
  standby cost (~similar to the retired web-2's €8.49/mo) — but this time with a consumer (disposability +
  blue-green readiness), unlike the retired standby.
- **Follow-on:** git-data (#6570) must also move off the unorderable `cax11` (ARM) to an x86 type — its own
  work; it is the root blocker for the Phase-6 concurrent-serving flip.
