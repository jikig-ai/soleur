# ADR-143: Active-active web ingress + drain-gated blue-green host lifecycle

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
   Phase-3 GA (shared git-data #6570 + coordinator), which is blocked — no longer by the type
   (repinned `cax11` → `cpx22` 2026-07-27, #6570) but because git-data still has **no birth route**
   at all (#6977).
3. **The programmatic anti-pooling gate was deleted 2026-07-20 (#6575)** and `server.tf:278-287` says it
   "MUST be rebuilt before any second web host is pooled."

## Live stock probe (Hetzner API, 2026-07-24 — the decided input)

Read-only query of `/v1/datacenters` (available server types) + `/v1/server_types`:

| Server type | Spec | Net €/mo (hel1) | Orderable in hel1 (live 2026-07-25) |
|---|---|---|---|
| `cx33` (Intel; web-1's current type) | 4c/8g x86 | 8.49 | **NO — out of stock (also all EU DCs)** |
| `cax11` (ARM; git-data's type **at the time of this probe** — repinned to `cpx22` 2026-07-27, #6570) | 2c/4g arm | 5.99 | **NO — ARM unavailable in EU DCs** |
| `cx22` (Intel) | 2c/4g x86 | ~4.59 | **NO — out of stock** |
| `cpx32` (AMD) | 4c/8g x86 | 35.49 | YES |
| `cpx22` (AMD) | 2c/4g x86 | 19.49 | YES |
| **`cx23`** (Intel; *was* the registry's type) | **2c/4g x86** | **5.49** | **Availability VOLATILE — see note below** |

This confirms model.c4:182 against live data: `cx33` cannot be recreated, so a rebuilt `web-1` cannot come
back as `cx33`. It also confirmed #6570's root-blocker framing at the time of this probe: `cax11` (ARM)
is unorderable. **Superseded 2026-07-27 (#6570):** git-data is repinned to `cpx22`, so the TYPE is no
longer the blocker; the remaining blocker is the absent birth route (#6977).

## Sizing input (30-day Better Stack host_metrics, measured 2026-07-25 — the decided input for D1)

web-1's real utilization was pulled from Better Stack (`host_metrics` memory/load, `tags.host=soleur-web-platform`,
1,732 samples over 30 days) rather than assumed from its 8 GB shape:

| Signal | Value | Fit on a 4 GB / 2 vCPU box |
|---|---|---|
| Memory: min available (peak usage) | 5.91 GB avail of 7.39 → **~1.5 GB peak used** | ~37% of 4 GB |
| Memory: p50 / avg used | ~1.0–1.1 GB | ~26% |
| CPU: max load15 (sustained) | **0.48** (avg 0.13; brief load1 spike 1.9) | well under 2 cores |

web-1 is ~5× over-provisioned on memory and barely touches CPU. A 4 GB / 2 vCPU host is amply sufficient for
the measured workload, with the "resize at flip if web-2's own metrics warrant" safety net (a `server_type`
change is a reboot-forcing in-place update, covered by the `reboot_updates` destroy-guard).

## Decision

**D1 — web-2 server type = `cx23` (2c/4g x86/Intel), born in hel1.** Sized to web-1's MEASURED usage
(Sizing input above: ~1.5 GB peak RAM, 0.48 max load15), not web-1's over-provisioned 8 GB shape. `cx23` is
the cheapest orderable 4 GB x86 in hel1 (live probe; the registry runs it there) — at ~€5.49/mo it is
actually *cheaper* than web-1's grandfathered `cx33` (~€8.49), and ~6× cheaper than the `cpx32` this ADR
originally chose. hel1 keeps it inside the location-scoped `web_spread` placement group (`server.tf:134`);
arch stays Intel x86 (same family as web-1's cx33; the web container is x86, so ARM is excluded regardless).
Superseded rationale (recorded, not deleted): the original D1 chose `cpx32` (4c/8g) as a like-for-like
successor to `cx33` before web-1's utilization was measured. With the data in hand, matching the 8 GB shape
was 5× the memory web-1 has ever used and 6× the cost. **Resize path:** if web-2's own host_metrics (or a
serving-load projection at the GA flip) ever show 4 GB is tight, bump `server_type` — a reboot-forcing
in-place update caught by the `reboot_updates` guard, done in a maintenance window. web-1's eventual de-pet
rebuild targets the same evidence-based `cx23`-class shape (falling back to `cpx22`/`cpx32` only if a
birth-time stock miss on the Intel line forces it — a clean, recoverable apply failure).

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

## Implementation Rulings (2026-07-24 CTO consult — 3 binding decisions)

Three mechanism-level questions surfaced at implementation where the plan under-specified against the live code. All three were routed to the `cto` agent (`hr-architectural-fork-decisions-route-to-cto`) and ruled as below.

### R1 — web-2 out-of-band health mechanism (refines D2; binding parent: **ADR-068 §(c)(3)**)

The plan's `web-2.app.soleur.ai/health` off-host probe is architecturally impossible here: web-2 has **zero public ingress** (the CF Tunnel connector is gated `each.key == "web-1"`, `server.tf`), and `uptime-alerts.tf:79-92` already deleted a per-host external monitor because the shared origin false-521s. ADR-068 §(c)(3) explicitly rejects off-host `readyz==200` (loopback-Host-gated → 403 off-host; empty `/workspaces` → 503) and defers the `/internal/readyz` serve-readiness gate to the cutover orchestrator.

**Ruling:** BUILD **no** off-host `/health` monitor. **AC9 is REFRAMED (not descoped)** onto a strictly-deeper composite, all already in the PR's fan-out: (a) the two per-host **outbound** heartbeats `web_nic_guard`/`web_zot_consumer` (`web-probe.tf`, absence-alerted), (b) the `SOLEUR_FRESH_BOOT_READY` marker readiness-DEPTH fields (volume-mounted+luksOpen / vector-installed / token-present — **boot-precondition readiness**: deeper than port-open, but a one-shot boot-time snapshot, NOT a served-request `/internal/readyz` assertion, which stays deferred), (c) per-host Vector log-count > 0 via `scripts/betterstack-query.sh "host:soleur-web-2 | count"` (the #6538 dark-host detector — the "Vector-shipping depth" half). The tunnel-reachable web-2 signal, when needed pre-flip, is web-1's `/hooks/deploy-status` `.reason` (`ok` vs `ok_peer_fanout_degraded`), which already exists. **DEFER** (ADR-068's, blocked on #6570): the on-host in-container `/internal/readyz` serve-readiness gate.

### R2 — rebuilt #6575 anti-pooling gate (refines D3)

The original `lb-weight-gate.sh` was deleted (#6575) because its first assertion required web-2 in the roster, so a correct post-retire config could only FAIL — "a gate a correct config cannot pass is not a guard."

**Ruling:** REBUILD as `apps/web-platform/infra/lb-weight-gate.sh` + `lb-weight-gate.test.sh` (name preserved for the ADR-068 §(c)/server.tf pointer), re-registered in `infra-validation.yml`. Fix the polarity via a **serving-weight TOP-GUARD**: web-2 `weight==0 && ∉ rotation` short-circuits to PASS (the standby state a correct pre-flip config is in), evaluated FIRST; the original Condition A (relay shape) + Condition B (git-data soak) run **only** when web-2 is being pooled (`weight>0` or in rotation). Fail-closed hardening: absent/non-integer/negative weight → FAIL (never default-0-PASS); unset rotation → FAIL (explicit empty = valid "no rotation"). **Condition C** (static committed-HCL, in the test harness): assert `dns.tf` app record stays web-1-only, the connector predicate excludes web-2, no `cloudflare_load_balancer` pools web-2 — the CI regression guard against an accidental *commit* that pools web-2 (the env-driven test alone cannot). Satisfies AC7 (weight>0 pre-flip → unit-testable FAIL).

### R3 — web-2 /workspaces LUKS mechanism (the most data-sensitive; open architectural question)

`workspaces-luks.tf` implements LUKS as an **additive web-1 singleton** (`hcloud_volume.workspaces_luks`, ADR-119); web-2's `for_each` volume is plaintext, and its old "slated for destruction (#6538)" justification is now FALSE (web-2 is a permanent standby). AC5 requires web-2 LUKS-backed, but the fresh-boot LUKS path does not exist and modifying the sole-copy-volume cloud-init boot path is the highest blast radius in the repo.

**Ruling: DEFER** the guest-side fresh-boot LUKS path to the **Phase-4 disposability-proof PR** (tracking **#6931**), CONDITIONAL on three couplings that make the defer fail-CLOSED (all built in this PR): **(1)** rewrite the void justification in `workspaces-luks.tf:169-179`; **(2)** add a `WORKSPACES_LUKS_CUTOVER_AT` precondition to `lb-weight-gate.sh` Condition B so a plaintext web-2 **cannot be pooled** (a flip reddens unless web-2 `/workspaces` is asserted LUKS-backed — the merge-blocker that makes the defer safe); **(3)** open #6931 + record here. **AC5 is REFRAMED**: LUKS-intent declared in HCL + plaintext-pooling physically gated + tracked for Phase-4. web-2 holds NO user data pre-flip (serves nothing; flip externally blocked on #6570) → no GDPR Art. 32 at-rest exposure. **Corrections the Phase-4 PR MUST inherit:** (i) use the `blkid -o value -s TYPE` discriminator, NEVER `cryptsetup isLuks` (the `cloud-init-git-data.yml:169` pattern is the documented data-destroyer on a populated device — safe there only because that host is single-purpose fresh; the web-host cloud-init is SHARED); (ii) **reconcile the two-mechanism topology split** — decide whether web-1's post-de-pet serving volume is the additive singleton or a fresh-boot `for_each` volume, so web-1/web-2 share ONE topology (cattle parity). **This split is an OPEN architectural question, deferred to Phase-4** (cross-ref ADR-119 additive design + ADR-068 §(c)); "mirror web-1's cutover" is ambiguous today because web-1 serves off the singleton, not off `hcloud_volume.workspaces["web-1"]`.

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| Pool web-2 into ingress now (CF connector-flip / LB weighted pool) | Routes live users to a host that cannot reach the sole-copy volume → workspace-gone single-user incident. This IS the "flip" that must be last (#6575 gate). |
| `cloudflare_load_balancer` weighted drain in this increment | Weighted drain only has a use case once hosts serve concurrently (Phase 6). Multi-connector CF Tunnel already gives health-gated failover; the LB is a paid add-on with no pre-flip value. Deferred to Phase 6. |
| Zero-downtime blue-green add/drain/remove for web-1 pre-Phase-3 | The sole-copy volume can be on one host at a time and web-2 can't serve it without shared git-data (#6570) — so genuine zero-downtime is impossible pre-Phase-3. A maintenance window is the honest mechanism. |
| Rebuild web-1/web-2 as `cx33` | Unorderable in all EU DCs (live probe). |
| Match web-1's 8 GB shape (`cpx32`/`cpx22`) as a like-for-like standby | Rejected on MEASURED data (Sizing input): web-1 peaks ~1.5 GB / 0.48 load15, so an 8 GB host is 5× the memory it has ever used and `cpx32` is ~6× the cost of `cx23`. A cx23 standby handles web-1's real load; "warm failover parity" is a real-load property, not a nominal-spec one. The resize-at-flip path covers any future growth. |
| Cross-DC (fsn1/nbg1) web-2 for DC-outage resilience | Loses the location-scoped `web_spread` placement group; the 2026-07-13 `-replace`-during-shortage wedge (#6393) is the cautionary precedent. Same-DC hel1 is chosen for placement-group HA + rebuildability; cross-DC (where `cpx*` types are also orderable) remains a future option. |
| "Count un-pushed work" as the pre-destroy safety gate | Meaningless for signup workspaces (no remote — everything is un-pushed, nowhere to push); protects only commits, not committed-but-remoteless state a reformat erases. Replaced by snapshot-verified volume preservation. |

## Consequences

- **Positive:** web-2 delivers fresh-boot-readiness proof, a cattle-host template, and proven disposability
  (volume-preserving reprovision) independent of the blocked ADR-068 Phase-3 chain. **Sole-copy protection
  (precise, PR-1 state):** `prevent_destroy` is on the `for_each` `hcloud_volume.workspaces` (all per-host
  volumes), which is the live sole copy TODAY (pre-LUKS-cutover) and transitively guards a whole-root
  `terraform destroy` (it aborts on the first `prevent_destroy` sibling). The **additive LUKS singleton
  `hcloud_volume.workspaces_luks`** — which BECOMES the sole copy after the ADR-119 rsync cutover — does NOT
  yet carry `prevent_destroy`: adding it collides with the `apply_target=workspaces-luks-recut` `-replace`
  escape hatch, so its direct guard + the off-host snapshot are **deferred to #6931** (the two-mechanism
  topology reconciliation). Interim guards on `workspaces_luks`: absent from the push `-target` allow-list;
  recut/cutover env-gated + typed-confirm + destroy-guarded. Residual exposure = a *targeted*
  `destroy`/`-replace` of `workspaces_luks` during the defer window (tracked as a #6931 cutover-PR blocker).
  luksOpen-not-reformat is likewise the deferred Phase-4 fresh-boot LUKS path (#6931), not present at merge.
- **Negative / accepted:** No *concurrent* redundancy pre-flip (web-2 is a standby, not a second server of
  the same workspaces). De-petting web-1 incurs a brief maintenance-window outage. A recurring `cpx32`
  standby cost (~similar to the retired web-2's €8.49/mo) — but this time with a consumer (disposability +
  blue-green readiness), unlike the retired standby.
- **Follow-on — DONE 2026-07-27 (#6570):** git-data has moved off the unorderable `cax11` (ARM) to
  `cpx22`, with its arch derived rather than hardcoded; the decision record is the ADR-068 addendum
  of that date. It was the root blocker for the Phase-6 concurrent-serving flip **as to the type**;
  the flip remains blocked because the host has no birth route at all (#6977).

## Addendum — 2026-07-26: web-2 repinned `cx23` → `cpx22` (forced by stock, #6966)

Status unchanged (`adopting`). This is an amendment to the Decision's host-shape choice, not a new
decision — D1 already provided for a shape change ("resize to a serving shape at the GA flip only if
web-2's OWN metrics warrant"), and the choice set here was reduced by the vendor, not by us.

**What forced it.** `main` HALTed on every merge: `hcloud_server.web["web-2"]` was declared but
absent, tripping the `host_creates` tripwire, and the birth path that shipped 2026-07-26 could not
clear it because **`cx23` had become orderable in 0 of 3 EU DCs**. The birth *mechanism* had merged;
the *value* had never been changed. Verified on the birth-path merge commit: run `30207415503`,
"Apply web-platform infra" → failure, `host_creates` HALT.

**Live probe, 2026-07-26 ~18:05 UTC** (`GET /v1/datacenters` → `.server_types.available`):

| | orderable in nbg1-dc3 / hel1-dc2 / fsn1-dc14 |
|---|---|
| available (identical sets) | `cpx12 cpx22 cpx32 cpx42 cpx52 cpx62 ccx13 ccx23 ccx33 ccx43 ccx53 ccx63` |
| orderable **nowhere** | the entire `cx` line (incl. `cx23` **and** web-1's `cx33`) and the entire `cax` ARM line |

No `deprecation` block is set on any of them — Hetzner stopped selling them in our region. Stock
moves on an **hours** timescale (`cx33` went orderable-in-hel1 → orderable-nowhere in ~3h on
2026-07-15), so this table is a snapshot and every host-creating apply re-probes.

**The `cx23` rationale recorded in D1 is void.** It read "cx23 is the cheapest orderable 4g x86 in
hel1". That is now false and has been deleted from `variables.tf` rather than left standing as stale
justification.

**Why `cpx22`.** The D1 *sizing* input is unchanged — 30-day host_metrics still show web-1 peaking
~1.5 GB RAM / 0.48 load15, and `cpx22` matches `cx23` on cores and RAM **exactly** (2c/4g), doubling
local disk (40 → 80 GB). So this is a **price** change, not a resize:

| type | shape | EUR/mo net (hel1) | orderable | vs `cx23` |
|---|---|---|---|---|
| `cx23` | 2c 4g 40gb x86 | 5.49 | **no** | — (superseded) |
| `cpx12` | 1c 2g 40gb x86 | 11.49 | yes | +6.00 |
| **`cpx22`** | **2c 4g 80gb x86** | **19.49** | **yes** | **+14.00** |
| `cpx32` | 4c 8g 160gb x86 | 35.49 | yes | +30.00 |
| `ccx13` | 2c 8g 80gb x86 ded. | 42.99 | yes | +37.50 |

`cpx12` was the only cheaper orderable option and was rejected on **headroom**, not price: 1.5 GB
measured peak on a 2 GB box is 75% with ~0 headroom, and its 1 vCPU is below web-1's shape. Since
web-2's stated purpose is to be the cattle template the Phase-5 web-1 de-pet rebuilds from, it must
be serving-capable as born; `cpx12` would force a reboot-forcing `server_type` resize at the GA flip,
i.e. a second birth cycle through the gated dispatch. `ccx13` is 7.8× `cx23` for a serving-weight-0
standby and over-provisions against the very measurement D1 used to size *down* from web-1's `cx33`.

**Cost caveat.** The Hetzner API returns **identical `net` and `gross`** for this account, so
+EUR 14.00/mo is arithmetic on those values and **not** a VAT-adjusted quote. The ledger row carries
the caveat and a `verify_by`; the first invoice showing the host is the reconciliation point.

**Arch: unchanged.** `cpx22` and `cx23` are both `architecture: x86` (only the CPU vendor differs,
Intel → AMD), and there is no arch derivation for web hosts at all — `server.tf` passes
`each.value.server_type` straight through, unlike `var.registry_server_type` and
`var.inngest_server_type`, which derive `arm64`/`amd64`. **Latent constraint worth recording:** a web
host can never be born on the `cax` ARM line *regardless of stock*, because `cloud-init.yml` pins
`amd64` in three places (Doppler CLI, the Docker apt `arch=amd64` line, the webhook binary). If the
ARM line restocks, a web host still needs cloud-init work first. This permanently narrows the
web-host choice set to `cpx*`/`ccx*`.

**Account cap: not a constraint, and the recorded value was stale.** The birth needed no vendor
request. The live limit is **10 servers with 4 running** (verified 2026-07-26), i.e. six free slots —
the granted outcome of the 2026-07-15 cap-headroom workstream. The pre-raise value of 5 had survived
in the repo's assumptions because `GET /v1/limits` returns **404**, so no automated check can read
the cap and nothing could contradict it. Two decisions were nearly made on the stale number:
requesting a raise that already existed, and retiring `soleur-grok-dogfood` to "free a slot" — an
irreversible `cx33` loss (cheapest orderable 8 GB replacement `cpx32`, 4.2×) for a slot already free
six times over.

**Disaster-recovery consequence — RESTATED 2026-08-06 (#7309).** The table above and this
paragraph both date from the 2026-07-26 probe, and the newer measurement changes what they mean, not
just their values.

It used to read: three of the four running hosts are on types that can no longer be ordered — web-1
(`cx33`), `soleur-grok-dogfood` (`cx33`), `soleur-registry` (`cx23`). Probed live 2026-08-06
(`hel1-dc2`, `.server_types.available`): **`cx23` and `cx33` are both AVAILABLE.** Both were
unavailable on 2026-07-26; `cx23` was unavailable again on 2026-08-04 (`zot-registry.tf`) and
available on 2026-08-06. Three samples, eleven days, two direction changes, no `deprecation` block on
any of them.

So the finding is not "these types are gone." It is that **availability is not a property of a server
type** — it is a point-in-time reading of vendor supply that moves in both directions, and a dated ✓
is not a capacity reservation. The consequence survives in a stronger form: **none of these hosts can
be counted on to rebuild on its current type**, even when today's probe is green, so each rebuild is
a type decision and a cost change regardless.

`soleur-registry` was repinned `cx23` → `cpx22` on that basis (#7309): `cpx22` was available at all
three probes, matches `cx23`'s 2c/4g shape exactly, and costs +€14.00/mo (operator-accepted). The two
`cx33` hosts are unrepinned and still carry the exposure. Nothing catches "a declared type left the
orderable set" until an apply — and nothing notices one coming back either; that periodic audit is
#6460, which must **sample repeatedly**, because any single probe here would have certified one of
three contradictory answers. #6460 also owns recording the account limits as facts with a decay
date.

**Not changed by this addendum:** `var.registry_server_type` keeps its unorderable default — a
`registry_server_type` change is a host *replace* of a live registry. This addendum also left
`var.git_data_server_type` on its unorderable `cax11`, and predicted that moving it would be a real
code change rather than a var flip because git-data's cloud-init installed the **arm64** Doppler
build.

> **Superseded 2026-07-27 as to git-data (#6570).** That prediction was correct and the work is now
> done: `var.git_data_server_type` is **`cpx22`**, and the host's arch — with the Doppler build and
> checksum that hang off it — is **derived** from the type prefix rather than hardcoded, so it is a
> var flip from here on. The sentence above no longer describes git-data; it remains accurate for
> `registry_server_type`. **The decision record lives in
> [ADR-068](./ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md) (addendum
> 2026-07-27, D1–D10)**, because git-data is ADR-068's element, not this ADR's. Note this repin does
> **not** make the host bornable — it still has no birth route (#6977).
