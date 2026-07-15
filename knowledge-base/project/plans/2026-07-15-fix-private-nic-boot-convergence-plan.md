---
title: 'fix: private-NIC boot convergence + fail-loud self-report for the registry host'
date: 2026-07-15
type: fix
issue: 6415
related: ['#6400', '#6405', '#6288', '#6122', '#6242']
related_adrs: [ADR-096, ADR-100, ADR-103, ADR-068, ADR-082]
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
revision: v2 (post 6-agent plan-review — see ## Plan-Review Consolidation)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed; see `## Infrastructure (IaC)`. No manual / SSH / dashboard provisioning:
  delivery is `terraform apply` via the EXISTING non-SSH `registry-host-replace` workflow_dispatch
  (ADR-096 amendment / ADR-103) — a `gh workflow run`. No new TF resource, provider, var, or secret.
  This host has NO SSH provisioner; the dispatch is the only sanctioned path.
  v2 note: the ONE dashboard step v1 hid (a Better Stack UI unpause) is GONE — the heartbeat arming
  that depended on it is deferred to a follow-up (see ## Plan-Review Consolidation).
  Any service-manager verb quoted below is a CITATION of an existing committed line, used to locate
  an edit — never an operator instruction.
-->

# fix: private-NIC boot convergence + fail-loud self-report for the registry host

> **Lane note:** no spec.md existed on this branch at plan time, so `lane:` defaulted to
> `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-07-15 · **Agents used:** `Explore`, `learnings-researcher`, `cto` (research);
`dhh`, `kieran`, `code-simplicity`, `architecture-strategist`, `spec-flow-analyzer`, `cpo` (review);
a `sonnet` verify-the-negative sweep (Phase 4.45).

### Gates run

| Gate | Result |
| --- | --- |
| **4.5** Network-Outage Deep-Dive | **Fired** (`unreachable`) → `## Network-Outage Deep-Dive` added; all four L3→L7 layers carry artifacts; **no gap to close**. Telemetry emitted. |
| **4.55** Downtime & Cutover | **Fired** (AC14 `-replace`s a running `hcloud_server`) → **was a real gap**; `## Downtime & Cutover` added. Telemetry emitted. |
| **4.6** User-Brand Impact | Pass — section present, threshold `single-user incident`, re-grounded per CPO C1. |
| **4.7** Observability 5-field | Pass — all 5 fields present, non-placeholder; `discoverability_test.command` is **ssh-free**. |
| **4.8** PAT-shaped variable | Pass — no PAT-shaped vars/literals. |
| **4.9** UI wireframe | **Skipped** — zero UI-surface files in Files to Edit/Create (the lone glob hit is prose *explaining* their absence). |

### Key improvements over v1

1. **Netplan converge path deleted** — both panels fired on it; the reboot is the sole primitive and the
   only one verified in production. R3(MTU) + R5 + Phase 0.1–0.3 dissolve. (~-60/-75 guard LOC.)
2. **L3 deferred** — v1's precedent claim was **false** (`apply-web-platform-infra.yml:2198-2206`: the
   probe cron is *"unbuilt"*); its `paused` flip was a **Terraform no-op** (`ignore_changes=[paused]`),
   so L3 would have shipped **inert behind a green AC**.
3. **`last_err` → `zot_last_err`** — the lib strips a **literal**; v1's spoof guard never fired.
4. **The emit→human leg is now asserted** — v1 edited the alarm and tested none of it; the
   `PRODUCER_SILENT` branch is keyed on `SOLEUR_ZOT_DISK`, so a dead NIC guard read **GREEN**.
5. **`network.tf:60` single-sourced** — `10.0.1.30` was dual-sourced; drift would **reboot a healthy
   host** (the new R3, and the real highest-severity risk — v1 mis-ranked R2).

### New considerations discovered

- **The registry is off the user-serving path** (`model.c4:260`, `:380`) — the replace is
  zero-downtime *by construction* via the atomic GHCR fallback. **But #6400's fallback was itself
  degraded**, which is why that outage escalated → a **fallback-health precondition** now gates AC14.
- **A pre-existing latent bug** (`runcmd` never re-runs on reboot ⇒ only `nofail` mounts the store)
  is fixed in 2 lines; it was reachable from *any* reboot cause, not just this plan's.
- **Verify-the-negative sweep: 12/12 CONFIRMS** (no Sentry emitter on the registry; no `crypttab`
  repo-wide; `ZOT_HEARTBEAT_URL` zero code consumers; no glob auto-discovery in `infra-validation.yml`;
  no SSH provisioner on the registry; the `sed` literal). One citation drift found and fixed
  (`variables.tf:298` → `:301`, the `default = false` line).

## Overview

The 2026-07-14 zot outage (#6400): the registry host booted **without its private NIC**.
`hcloud_server.registry` came up, zot served `:5000` fine, but the host held no `10.0.1.30` — so the
fleet's primary image-pull path was unreachable for **~14 days while every health signal stayed
green**.

Two layers, registry-only:

| Layer | Fixes | Phase |
| --- | --- | --- |
| **L1 — on-host converger** | *why it broke* — covers all boot paths, incl. the operator's from-empty apply | 2 |
| **L2 — in-surface emit + alarm** | *why nobody knew* — 14 days → ~30 min for the observed failure | 3 |

**Headline:** this brings the host into compliance with
`hr-fresh-host-provisioning-reachable-from-terraform-apply` — today a from-empty `terraform apply`
can yield an unreachable registry needing an operator reboot. That, not "IMDS resilience", is the
decision.

**Framing correction to the issue:** the "transient IMDS blip" is likely a **misdiagnosis of a known,
documented structural ordering race** (see Research Reconciliation).

## Plan-Review Consolidation (v1 → v2)

6 agents (5-agent escalation + `cpo`). **v2 applied every Mechanical finding.** Full audit + decision
classes: [`specs/…/decision-challenges.md`](../specs/feat-one-shot-6415-private-nic-imds-resilience/decision-challenges.md).

**The three findings that reshaped the plan** — each **verified by me against the code**, not taken on
the agent's word:

1. **L3 (off-host probe) is greenfield — my precedent claim was false and inverted.** v1 asserted
   `apply-web-platform-infra.yml` "already names the web-host-driven private-net probe … this follows
   it." The file says the **opposite** at `:2198-2206`: git_data_prd is *"paused until #5274 PR C arms
   the web-host probe cron"* and *"its probe cron is **unbuilt**"*. `ZOT_HEARTBEAT_URL` has **zero
   consumers**. My "the remaining work is small" — the **sole basis** for elevating L3 to
   required-for-close — was fabricated. This is an **`hr-verify-repo-capability-claim-before-assert`
   violation by the plan author.** → **L3 deferred**: CPO's own condition C3 (split if the delivery
   site is unresolved) is **met at plan time**, so L1/L2 ship.
2. **The netplan converge path is deleted.** Both panels fired on it (`dhh` + `code-simplicity`: "pick
   one primitive — the reboot trigger is a **strict subset** of netplan's"; `architecture`: step 5 had
   **no budget** ⇒ re-applies every 5 min, bouncing **public egress**, invisible to a 25-min absence
   window = **#6400's signature, self-inflicted**). Per the consolidation rule (*both panels on the
   same scope ⇒ prefer delete*), the reboot is now the **sole** primitive — and it is the one
   **verified in production** (Sharp edge 2). **R3 (MTU) and R5 (interface bounce) dissolve by
   construction**, with Phase 0.1–0.3.
3. **`last_err` ≠ `zot_last_err`** (`kieran`, `code-simplicity`, `spec-flow` — independently).
   `scripts/lib/zot-telemetry-parse.sh:27` strips the **literal** ` zot_last_err=`. v1 emitted
   `last_err=` ⇒ the spoof strip **never fires** while AC8+AC9 both pass green. → field renamed; the
   shared security lib needs **no fork**.

**Also applied:** the alarm's `PRODUCER_SILENT` branch keys on `$MAIN` (SOLEUR_ZOT_DISK) only, so a
dead NIC guard was **silent** (v1's Observability claimed otherwise — false); `10.0.1.30` is
**dual-sourced** (`network.tf:60` vs `zot-registry.tf:40`) ⇒ drift would **reboot a healthy host**; the
boot anchor must follow the **token file** at `:317-318`, not the CLI install; AC5/AC8 **false-passed on
an unmodified file**; "the same bytes the host boots" was **false** (Terraform `$${…}` escaping);
`converged_by=reboot` ⇒ `nic_ok=true` ⇒ **no alarm** (lost ceiling); the C4 "nothing falsified"
conclusion was **wrong on 3 counts**; the threshold rationale was **falsifiable** (beta users = 0).

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Reality | Response |
| --- | --- | --- |
| Fetch failed due to a **transient IMDS blip** | `learnings/2026-07-07-immutable-redeploy.md` **Sharp edge 2** documents this exact symptom on this exact host (#6122): *"the additive online-attach can land after cloud-init's network stage… a soft reboot brings the NIC up."* `network.tf:9-13`: `hcloud_server_network` is a **separate additive online attach** (inline `network {}` force-replaces the host). **No TF ordering can win this race** — the attach needs a created server, and a created server is already booting. | Hold H1 (blip) and H2 (race) as **competing**. The design is correct under both; the emit **discriminates** them (AC15). |
| Fix via `cloud-init clean --logs && cloud-init init --local` | **Three verified failure modes.** (a) `cloud-init-registry.yml:294` appends fstab with a **bare `echo >>`, no `grep -q \|\|` guard** (git-data's `:170` has one) ⇒ **duplicate mount entries** every re-run. (b) `clean` wipes the datasource semaphore; a transient IMDS failure on re-run ⇒ `DataSourceNone` ⇒ default network config ⇒ **loses the public NIC too** ⇒ unrecoverable on a deny-all no-SSH host. *The proposed cure for a transient IMDS blip is triggered by a transient IMDS blip.* (c) re-runs the fail-closed isolation check (FATAL at `:351-353`) ⇒ a Doppler blip and zot never relaunches. | **Rejected.** |
| Emit a `SOLEUR_*` marker (**Sentry**/stdout) | The registry host has **no Sentry emitter**. Its transport is Better Stack Logs (`:148-234` `SOLEUR_ZOT_DISK`, posted under `doppler run` at `:241`). Sentry is a **web-host** pattern. | Emit over the **existing** Better Stack transport. No new sink/secret. |
| Applies to registry, git-data, inngest | **Registry only.** A reboot primitive on git-data is **dangerous**: `luksOpen` is in `runcmd` (`cloud-init-git-data.yml:163`) — **per-instance, does not re-run on reboot** — and **no `crypttab` exists** (verified: repo-wide grep returns nothing); fstab carries `nofail` (`:118`) ⇒ a reboot leaves the fleet's most irreplaceable data store **silently unmounted**. Both hosts also fail *loudly* today. | **Registry-only.** Generalization → tracking issue, **blocked on a reboot-safe LUKS unlock**. |
| Marker "closes the #6405 gap" | For the **observed** failure, yes: #6400's host had **no `10.0.1.30` at all**, so L2's local reading is correct and alarms in ~30 min. L3 covers a *different, never-observed* mode (private net broken while the host thinks it's fine). | L2 ships; **L3 deferred** (finding 1). |
| — | **Why it was invisible 14 days:** `registry_disk_prd` (`paused=false`, live) **stays GREEN on a NIC-less host** (public egress works), and the boot readiness poll hits `localhost:5000` (`:379-382`) — succeeds because zot binds `0.0.0.0:5000` (`:375`). | Recorded in `## Observability` as *why* a new signal is needed, not a new threshold. |
| — | Registry resources are **`OPERATOR_APPLIED_EXCLUSION`** (`zot-registry.tf:16-22`): applied by the operator's **full untargeted** apply + the 12h drift detector, **not** the per-PR `-target=` list. | A dispatch-job reboot would cover only the maintenance path and leave the **primary** provisioning path uncovered ⇒ decisive for the **on-host** layer. |
| — | `registry-host-replace`'s gate asserts `nic_recreated>=1` from **tfplan** (`tests/scripts/lib/registry-host-replace-gate.sh:44-46`). | Proves TF *planned* the attach — **not** that the **guest** configured it. This plan closes that delta. |

## Hypotheses

Phase 1.4 gate **fired** (`unreachable`). L3→L7 order per `hr-ssh-diagnosis-verify-firewall`.

1. **L3 — private-NIC address absent on the guest (ROOT CAUSE, verified).** #6400 body + Sharp edge 2
   (#6122): *100% ping loss + TCP timeout at the private IP while `hcloud server describe` shows
   attached*. Distinguisher: **down container ⇒ connection *refused*; unconfigured NIC ⇒ *timeout* +
   ping loss.** [verified]
   - **H1 — transient IMDS blip.** [**unverified** — no telemetry exists; that absence *is* the gap]
   - **H2 — structural ordering race** (leading). [**unverified**, but *observed* in Sharp edge 2 and
     structurally implied by `network.tf:9-13`]
   - **Resolution:** correct under both; `imds_rc`/`imds_nets`/`uptime_s` decide it in one event (AC15).
2. **L3 — firewall.** *Opt-out w/ artifact:* the registry firewall filters the **public** interface
   only; intra-network `10.0.1.0/24` traffic is **open by membership, no allow rule**
   (`zot-registry.tf:312-313`). Pulls worked before the replace and after recovery. [not implicated]
3. **L3 — DNS/routing.** *Opt-out w/ artifact:* no DNS; consumers target the **literal** `10.0.1.30`
   (`zot-registry.tf:40`, `tunnel.tf:47`). The missing address *is* the fault. [N/A by construction]
4. **L7 — TLS/proxy.** *Opt-out w/ artifact:* zot is **plain HTTP** (`zot-registry.tf:31`); the
   cloudflared rule targets `tcp://10.0.1.30:5000` (`tunnel.tf:45-47`), **unchanged** across the
   incident. The target was right; the address didn't exist. [not implicated]
5. **L7 — application (zot).** [verified — **excluded**] #6400 records zot "running fine, `:5000`".
   Structurally: binds `0.0.0.0:5000` (`:375`), readiness polls `localhost:5000` (`:379-382`) — **both
   succeed NIC-less**. This is *why* it presented as "zot mysteriously down".

## User-Brand Impact

- **If this lands broken, the user experiences:** a registry host that silently takes the fleet's
  image-pull path offline — #6400. Deploys then lean on the ADR-096 GHCR dark-launch fallback; when
  that is **also** degraded (#6400's actual state: `image_pull_failed`, prod pinned to `0.213.2`),
  **no fix of any kind reaches production**.
- **A worse failure this plan must not create:** a mis-parsed healthy state ⇒ self-inflicted reboots.
  Bounded by the counter (≤2 per instance) + an exact-word predicate (**AC3/AC4**).
- **If this leaks, the user's data is exposed via:** *no new vector.* Only **non-secret host routing**
  (a private RFC1918 address already baked into `user_data`, retrievable from the hcloud metadata API
  — `zot-registry.tf:266`). The one secret on the emit path (`BETTERSTACK_LOGS_TOKEN`) is **not
  baked** — injected at cron time via `doppler run --project soleur-registry --config prd` (`:241`).
  Isolation cardinality stays **3** (`:348-353`).
- **Brand-survival threshold:** `single-user incident`

**Rationale (re-grounded per CPO C1 — v1's grounding was falsifiable).** *Not* "a user waits days for
a fix": **beta users = 0** (`knowledge-base/product/roadmap.md:81`) falsifies that, and a future
reviewer would use it to strip the review panel off the next plan in this class. Grounded instead on:
(1) **ADR-103 precedent** — same host class, same threshold, accepted 2026-07-09; downgrading here
implicitly overturns a live ADR. (2) **Phase 4 *is* the founder-recruitment phase** (`#1439`/`#1441`
open) and this is the ship path those fixes travel; the threshold reflects exposure **when the control
is relied upon**, not headcount on plan-write day.

## Open Code-Review Overlap

Checked all 62 open `code-review` issues against Files to Edit/Create (two-stage `gh --json` →
standalone `jq --arg`). **None.** (Two matched the bare substring `private` — #3321 learnings
CODEOWNERS, #2196 rate-limiter — neither touches these files.)

## Implementation Phases

### Phase 1 — Terraform: teach the host its IP, from ONE source

- **1.1** `zot-registry.tf:248` — pass `private_ip = local.registry_private_ip` into `templatefile(…)`
  (the local exists at `:40`; non-secret, same class as `zot_image`).
- **1.2 (load-bearing — `spec-flow` P1).** `network.tf:60` **hardcodes** `ip = "10.0.1.30"` while its
  own comment (`:56`) references `local.registry_private_ip`. **Single-source it:**
  `ip = local.registry_private_ip`. Phase 1.1 promotes this constant to **reboot authority** — if the
  two literals drift, the guard bakes a wrong `EXPECTED_IP` ⇒ `ip_present=false` forever ⇒ IMDS
  *corroborates* (the network genuinely **is** attached) ⇒ **the guard reboots a healthy host to the
  cap, then goes terminal.** R2's mitigations are blind to this (the parse is right, the constant is
  wrong). `inngest-host.tf` fixed this exact shape after the #6180 review ("a dead local + a hardcoded
  copy"); registry still has it.
- **1.3** No `hcloud_server`/`hcloud_server_network` schema change; **no** inline `network {}`
  (force-replaces the host — `network.tf:9-13`).

### Phase 2 — L1: the on-host converger

- **2.1** `write_files` `/usr/local/bin/soleur-private-nic-guard.sh` (`root:root`, `0755`), mirroring
  `zot-disk-heartbeat.sh` (`:148-234`).

  **Precedent to copy:** `:264-267` already solves the identical "attach lands after cloud-init" race
  for the **volume**, with a bounded 60s device-wait. Mirror that shape.

  Order — **idempotent, bounded, fail-open toward serving**:
  1. `EXPECTED_IP='${private_ip}'`.
  2. **Trigger predicate — the local fact ALONE.** `ip -4 -o addr show` **exact-word** match
     (`grep -qw`) for `EXPECTED_IP`. Present ⇒ `converged_by=already`, `nic_ok=true`, exit 0.
     **Healthy path = pure read, zero mutation.** Zero runtime dependencies (the IP is baked at
     template time) — **IMDS is telemetry, not a trigger.**
  3. **Bounded wait** (the `:264-267` shape) — lets an in-flight attach land before acting.
  4. **Diagnose:** `imds_rc`/`imds_nets` (`curl -sf -m 5` on `…/hetzner/v1/metadata/private-networks`,
     **exit-code-neutralized** per `2026-07-05-bounded-retry-off-host-verify-…` — a nonzero exit is a
     valid data outcome and must not abort under `set -e`).
  5. **Store-mount self-heal (2 lines — fixes a PRE-EXISTING bug; `code-simplicity` + `spec-flow`).**
     `runcmd` is **per-instance and does not re-run on reboot**, so the `:264-267` device-wait, `mount`
     and `resize2fs` all skip; only `fstab … nofail` (`:294`) mounts the store. A slow volume node ⇒
     mount fails silently ⇒ zot (`--restart unless-stopped`, `:369`) bind-mounts an **empty root-disk
     dir** ⇒ 404 for every image. Reachable from **any** reboot cause (kernel panic, Hetzner
     migration, the operator's own Sharp-edge-2 recovery) — not something this plan invents:
     `mountpoint -q /var/lib/zot || { mount -a; mountpoint -q /var/lib/zot && docker restart zot; }`.
     **Ordering matters:** `--restart unless-stopped` can start zot *before* the mount lands, so
     `mount -a` alone does not fix zot's bind — it needs the restart. Emit `zot_store_mounted`.
  6. **Converge — ONE primitive: a guarded reboot.** Uses **cloud-init's own renderer** (correct
     MTU/routes **by construction**) and is the recovery **verified in production** (Sharp edge 2).
     The gate is a single `if`; three persistent-state items collapse to **one**:
     ```
     ip_present=false && imds_nets>0 && uptime_s>600 && reboot_count<2
     ```
     - **IMDS corroboration** (`imds_nets>0`) — never reboot on zero valid evidence (the
       `zot-restart-loop-alarm.sh` doctrine). IMDS unreachable ⇒ **emit only**.
     - **`uptime_s>600`** replaces v1's N-consecutive-samples: it says *"don't reboot a host that just
       booted"* **directly**, needs **zero** persistent state, cannot be corrupted, is already an emit
       field, and makes the boot invocation naturally no-op.
     - **Counter — pinned literal cap 2**, at **`/var/lib/soleur/private-nic-reboots`** on the **root
       disk**, keyed by **instance-id**. **Not** `/var/lib/zot` (survives replace ⇒ a fresh host
       inherits an exhausted budget). **Not** `/run` or `/tmp` (tmpfs ⇒ rotates per boot ⇒ reintroduces
       the infinite-reboot trap via *path choice* — `spec-flow` P1). **Not** `boot_id`-keyed. A replace
       gives a new root disk ⇒ fresh budget, for free.
     - v1's **cooldown is cut** — redundant with a hard cap (cap 2 makes a storm *definitionally*
       impossible).
     - Counter written **before** the reboot (fail-safe ordering).
  7. **Emit always** — 9 fields, all load-bearing:
     ```text
     SOLEUR_PRIVATE_NIC nic_ok=<bool> converged_by=<already|reboot|none> imds_rc=<int>
       imds_nets=<int> reboot_count=<int> zot_store_mounted=<bool> uptime_s=<int>
       boot_id=<id> zot_last_err=<free-text, TRAILING>
     ```
     **Discrimination (§2.9.2):** `imds_rc≠0` ⇒ **H1**; `imds_rc=0 && imds_nets=0` ⇒ **H2**;
     `imds_nets>0 && converged_by≠already` ⇒ **third mode** (attach landed, guest never configured).
     `boot_id` is a **hard dependency** of the lib's `zot_newest_boot`/`zot_scope_to_boot` scoping.
     **`zot_last_err` (not `last_err`)** — matches the literal the lib's strip requires (`:27`) and the
     emit precedent (`:221`); **trailing**, so the trusted-region strip works.
     **Dropped as non-discriminating:** `host` — the lib itself states *"the immutable
     registry-host-replace REUSES the terraform hostname, so boot_id (not host) is what separates
     old-host from new-host events"*; v1 cited that file and emitted the field it calls useless. Also
     dropped: `ip_present` (derivable from `converged_by`), `expected_ip` (template constant),
     `instance_id` (conveyed by `reboot_count`), `priv_nic`/`mtu`/`netplan_has_priv` (die with netplan).
- **2.2** `/etc/cron.d/soleur-private-nic-guard` — every 5 min under
  `doppler run --project soleur-registry --config prd` (the `:241` shape), wrapped in **`flock`**.
  **Why a cadence:** under H2 the attach lands *after* boot, so a boot-only check would emit a false
  failure and heal nothing; it also catches a NIC lost later.
- **2.3** `runcmd` boot invocation — **placed after `:318`**, i.e. after the token file
  `/etc/default/registry-doppler` is written (`:317-318`), **not** merely after the CLI install
  (`kieran` P1-3: the binary is *necessary, not sufficient*; `:316` documents that Doppler aborts
  without `HOME`). Anywhere in `:306-316` satisfies v1's stated anchor but has **no token** ⇒
  `doppler run` resolves nothing ⇒ the POST dies ⇒ `|| true` swallows it **silently** — a silent
  failure inside the control built to end silent failures. Source the env file first (the `:390`
  precedent). Suffix `|| true` (**fail-open**; ADR-082 Item 5 rationale) and take the **same `flock`**
  as the cron (`spec-flow` P1 — v1 asserted the lock only on the cron, so boot and cron could race).
  The cron is activated by the **already-present** enable line at `:389` — no new activation step, no
  operator action.

### Phase 3 — L2: emit → human (the leg v1 shipped untested)

- **3.1** `scripts/zot-restart-loop-alarm.sh`:
  - **Independent absence check for the new stream.** `PRODUCER_SILENT` is computed at `:106-124`
    keyed **only** on `$MAIN` (`--grep SOLEUR_ZOT_DISK`). If the NIC guard dies while
    `zot-disk-heartbeat.sh` keeps emitting, `MAIN` is non-empty ⇒ the script proceeds ⇒ **GREEN**.
    v1's Observability claimed this branch covered NIC-guard absence; **it does not**. Add a
    **separate** `--grep SOLEUR_PRIVATE_NIC` absence probe reusing the existing control-marker →
    LOOKBACK ladder.
  - **Fire on `nic_ok=false` scoped to the NEWEST `boot_id`**, not any-in-window. The query window is
    **3h** (`:63`); any-in-window would file an issue for **every successful H2 self-heal for up to
    3h** — paging on the happy path (`spec-flow` P1). Reuse `zot_newest_boot`/`zot_scope_to_boot`.
  - **Advisory branch on `reboot_count>0` / `converged_by=reboot`** (`architecture` P1-1). Without it
    `converged_by=reboot` ⇒ `nic_ok=true` ⇒ **no alarm**: the structural race becomes a *silently
    successful self-heal* and is never reported again — a **lost ceiling** (today the race at least
    surfaces, eventually). A self-rebooting production host is a **standing** signal, not a one-time
    post-merge read. Distinct, lower severity than the `nic_ok=false` terminal alarm.
  - **Exit contract (`spec-flow` P0).** The script is linear/early-exit with **one** `VERDICT`; exits
    at `:106/:129/:155/:177/:197` terminate **before** anything appended. A zot isolation FATAL
    (`:351-353`) ⇒ `zot_restarts=-1` ⇒ `:155` zero-evidence ⇒ `exit 2` ⇒ **the NIC event is never
    read**. Do **not** add exit code 4 — `scheduled-zot-restart-loop.yml:220` maps anything not 0/1/3
    to `'error'`, so a NIC fire would report as a *probe fault*, contradicting that file's "a FIRE is
    NOT a monitor error" doctrine. **Evaluate the NIC check before the zot early-exits, or restructure
    so both facts can be carried.** Sweep `case "$rc"` at `:103-109`. Define precedence for a
    concurrent zot-FIRE + NIC-FIRE.
  - **Auto-close branch.** The GREEN branch (`:182-203`) closes two hardcoded titles via own-title
    searches; nothing would close a NIC issue ⇒ it goes stale ⇒ trains the operator to ignore
    `action-required` (`spec-flow` P1). Add the NIC title to the close path.
- **3.2** `.github/workflows/scheduled-zot-restart-loop.yml` (`*/30`, `:47`) — deduped
  `action-required` branch mirroring `:136`/`:171`, with a **no-SSH** reproduce block.

### Phase 4 — Tests

- **4.1** New `apps/web-platform/infra/private-nic-guard.test.sh`, two layers per
  `registry-boot-guard.test.sh:20-60`:
  1. **Behavioral.** Extract the predicate from `cloud-init-registry.yml` and replay against
     **synthesized** fixtures (`cq-test-fixtures-synthesized-only`). **Render honestly (`kieran`
     P1-6):** v1's "the same bytes the host boots" was **false** — the body lives in a Terraform
     template (`$${…}` escaping at `:305`, `:369`; `${private_ip}` unrendered), so extracted bytes are
     **not** executable bash. The cited precedent extracts only *scalars* (a regex + an integer,
     `:38-42`). This test needs an explicit **un-escape/render** step (+ PATH stubs for `ip`, `curl`,
     `reboot`, `mountpoint`, `docker`, and a fake counter FS) or the anti-drift guarantee is
     rhetorical. Cases: healthy ⇒ **no mutation**; `imds_rc≠0` ⇒ **no reboot**; `imds_nets=0` ⇒ **no
     reboot**; corroborated+unexhausted ⇒ counter-then-**one** reboot; **counter exhausted ⇒ no
     reboot**; `uptime_s<600` ⇒ **no reboot**; store-unmounted ⇒ `mount -a` + `docker restart`.
  2. **Structural:** counter written **before** reboot; counter path is **`/var/lib/soleur/…`** —
     assert the **positive** path (root disk), not v1's `not /var/lib/zot` negation, which did not
     exclude tmpfs; cap is a **literal 2**; `flock` on **both** cron and boot; `|| true` on boot; boot
     invocation **after `:318`**; `zot_last_err` **trailing**; the `doppler run --project
     soleur-registry --config prd` wrapper.
- **4.2** Register in `.github/workflows/infra-validation.yml` as an explicit `- name:` / `run: bash`
  step (verified convention at `:167`–`:176`; `registry-boot-guard.test.sh` is registered at `:224`;
  **no glob auto-discovery**).
- **4.3** **`scripts/zot-restart-loop-alarm.test.sh`** — extend for the NIC branches. It exists and is
  registered in `scripts/test-all.sh`; v1 edited the alarm but listed **neither** the test nor that
  suite, and AC13 asserted only the *infra* suite ⇒ **the entire emit→human leg shipped unasserted**
  (`spec-flow` P1).

### Phase 5 — ADR + learning

- **5.1** **ADR-113** (next free ordinal; highest on `origin/main` is ADR-112). See below.
- **5.2** `learnings/2026-07-07-immutable-redeploy.md` **Sharp edge 2** — its manual *"always verify
  private-net reachability after a `-replace`"* is exactly the operator-memory dependency this
  removes. Point it at the guard + `SOLEUR_PRIVATE_NIC`.

## Files to Edit

| File | Change |
| --- | --- |
| `apps/web-platform/infra/zot-registry.tf` | `:248` pass `private_ip` |
| `apps/web-platform/infra/network.tf` | `:60` `ip = local.registry_private_ip` (single-source) |
| `apps/web-platform/infra/cloud-init-registry.yml` | guard + cron + boot invocation |
| `scripts/zot-restart-loop-alarm.sh` | NIC absence probe, newest-boot fire, advisory branch, exit contract, close branch |
| `scripts/zot-restart-loop-alarm.test.sh` | NIC branch coverage |
| `.github/workflows/scheduled-zot-restart-loop.yml` | deduped `action-required` branch |
| `.github/workflows/infra-validation.yml` | register `private-nic-guard.test.sh` |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | 2 description edits (see C4) |
| `knowledge-base/project/learnings/2026-07-07-immutable-redeploy.md` | Sharp edge 2 → automated fix |

## Files to Create

| File | Purpose |
| --- | --- |
| `apps/web-platform/infra/private-nic-guard.test.sh` | behavioral + structural guard test |
| `knowledge-base/engineering/architecture/decisions/ADR-113-dedicated-host-private-nic-boot-convergence.md` | decision record |

**Path verification:** every Files-to-Edit path confirmed via `git ls-files` / `ls` at plan-write time.
`scripts/lib/zot-telemetry-parse.sh` is **deliberately absent** — renaming the field to `zot_last_err`
means the shared security lib needs **no fork and no edit** (v1 had no route to fix this at all).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** ~~`gzip -9 -c apps/web-platform/infra/cloud-init-registry.yml | base64 -w0 | wc -c` < 32768.~~
  **CORRECTED at `/work`.** `kieran`'s caveat said the raw-template proxy "cannot realistically
  false-pass at this headroom" — but the proxy was never necessary. The **real** figure is
  measurable locally by rendering via `terraform console` and gzipping the render, so the AC now
  asserts the actual artifact instead of a stand-in:
  - **Measured:** rendered + `gzip -6` + base64 = **20,080 bytes** vs the 32,768 cap (~12.6 KB
    headroom). Raw-template `gzip -9` reads 20,040 — i.e. the proxy was *optimistic* by 40 bytes,
    harmless here but directionally wrong, which is exactly why a proxy shouldn't gate.
  - **Verified at `/work`:** the render also passes `cloud-init schema -c` (`Valid schema`) with
    zero unrendered `${...}` left. Validating the RAW template would false-FAIL on the
    un-rendered interpolations.
- **AC2** `bash apps/web-platform/infra/private-nic-guard.test.sh` exits 0, covering all seven Phase
  4.1 behavioral cases.
- **AC3** **Healthy ⇒ zero mutation.** The `ip_present=true` fixture reaches `converged_by=already`
  with **no** reboot and **no** `mount -a`.
- **AC4** **Reboot provably bounded:** `imds_rc≠0` ⇒ no reboot; `uptime_s<600` ⇒ no reboot; counter
  exhausted ⇒ no reboot; structural greps prove counter-write-precedes-reboot, the **literal cap 2**,
  and the counter path is **`/var/lib/soleur/…`** (positive assertion — root disk, not tmpfs).
- **AC5** Phase 1.1 is asserted by the **`templatefile` argument** (`private_ip = local.registry_private_ip`),
  **not** `grep -c 'private_ip'` — which returns **2 on an unmodified file** (`:40`, `:44`) and cannot
  detect whether the phase happened (`kieran` P1-4).
- **AC6** ~~**`10.0.1.30` appears exactly once** across `apps/web-platform/infra/*.tf`.~~
  **CORRECTED at `/work` — as written this gate was UNPASSABLE, and it is the plan's own
  `grep`-matches-its-own-comments trap** (the same class the plan flags elsewhere for `.sh`
  bodies). The literal legitimately appears in prose in `tunnel.tf:47,60-62`, `dns.tf:55`,
  `server.tf:553` — and in live code at `server.tf:608` (`docker info | grep '10.0.1.30:5000'`,
  a docker-daemon probe string, not an address definition). Single-sourcing cannot and should
  not delete any of those. The invariant that actually matters is that the address is
  **defined** once, so the AC now asserts the **assignment shape**:
  - **zero** `ip = "10.0.1.30"` assignments remain in any `*.tf` (was 1, at `network.tf:60`);
  - `network.tf` reads `ip = local.registry_private_ip`;
  - exactly **one** non-comment `"10.0.1.30"` literal survives — the local at
    `zot-registry.tf:40`. Counted with `^[^#]*` so a commented mention can never satisfy or
    break the gate.
- **AC7** `bash scripts/zot-restart-loop-alarm.test.sh` green **with the new NIC branches covered** —
  specifically, a fixture where the NIC guard is **silent while `SOLEUR_ZOT_DISK` still flows** must
  **FIRE**, not go GREEN (the `spec-flow` P0 regression).
- **AC8** A fixture with a **zot early-exit** (`zot_restarts=-1` ⇒ zero-evidence) **still evaluates the
  NIC check** (proves the exit-contract fix). No new exit code 4.
- **AC9** `zot_last_err` is the **trailing** field, and a fixture proves the lib's strip **actually
  fires** on a `SOLEUR_PRIVATE_NIC` line (v1's `last_err` silently passed through — assert the
  **behavior**, not the field name).
- **AC10** A successful self-heal (`converged_by=reboot`, `nic_ok=true`) fires the **advisory** branch,
  not the terminal one, and does not file a duplicate.
- **AC11** `ADR-113-*.md` exists, `status: accepted`, contains the **normative LUKS blocker** (below),
  and its `## Diagram` cites the three-`.c4` enumeration. *(Sweep this AC if the ordinal is renumbered.)*
- **AC12** `bash tests/scripts/test-registry-host-replace-gate.sh` passes **unchanged** (no new TF
  resource ⇒ `-target` set unchanged).
- **AC13** **Both** suites green: the infra suite (`infra-validation.yml`) **and** `scripts/test-all.sh`
  (which recurses `plugins/soleur/` and registers the alarm test at `:211`).

### Post-merge (operator)

- **AC14** Fire `registry-host-replace` via the `apply-web-platform-infra.yml` dispatch
  (`apply_target=registry-host-replace`). **Automation:** the sanctioned non-SSH reprovision path
  (ADR-096 amendment / ADR-103) — a `gh workflow run`, **not** operator SSH. The cloud-init change is
  `ForceNew` and there is **no** `ignore_changes=[user_data]` (`zot-registry.tf:274-276`), so the
  replace **is** the delivery mechanism.
- **AC15** Within 10 min, **SSH-free**:
  ```
  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
    --since 30m --grep SOLEUR_PRIVATE_NIC --limit 20
  ```
  ≥1 event with `nic_ok=true` and `zot_store_mounted=true`. **Record `converged_by` — it is the
  empirical resolution of the Hypotheses section** (`already` ⇒ no race this boot; `reboot` ⇒ the race
  is real and the guard healed it).
  - **Zero-rows branch (required — `spec-flow` P0):** zero rows is **ambiguous** across ≥6 causes (creds
    unset, cloud-init died pre-Doppler, guard crashed, ingest lag, host never booted). Do **not** read
    empty as "no signal" — `betterstack-query.sh:44-59` warns against exactly this. Run
    `bash scripts/zot-restart-loop-alarm.sh`, whose control-marker → LOOKBACK → PRODUCER_SILENT ladder
    (`:106-124`) **already discriminates these**.
  - **`nic_ok=false` branch (required):** revert the PR → merge → re-dispatch `registry-host-replace`.
    The host is `ForceNew` + no-SSH, so there is **no in-place rollback**. Name an owner for the first
    30 minutes.
- **AC16** **Do NOT assert deploy-pipeline success as the zot-reachability proof.** Deploy success is
  satisfied **by the ADR-096 GHCR fallback with zot unreachable** — that is literally #6400, the proxy
  that lied for 14 days (`spec-flow` P0). Assert the invariant directly: `SOLEUR_PRIVATE_NIC
  nic_ok=true` (AC15) **plus** a zot-served pull distinguishable from a fallback pull.
- **AC17** `Ref #6415` in the PR body — **not** `Closes`. Remediation completes only after AC14
  (ops-remediation class), and #6415 also stays open for the deferred L3.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed. Verified every load-bearing claim and reshaped v1: on-host is the right layer (no
TF ordering can win the race; `OPERATOR_APPLIED_EXCLUSION` means a dispatch reboot misses the primary
path); `cloud-init clean` rejected with three concrete failure modes; **scope cut to registry-only** on
the git-data LUKS finding; MTU named as a silent-corruption hazard (now moot — netplan dropped); and
the reboot-bounding rules (local-fact predicate, root-disk counter, corroboration).

### Product/UX Gate

**Not applicable.** Mechanical UI-surface scan: **no** path in Files to Edit/Create matches
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Product assessed **NONE**.

### CPO sign-off

**APPROVE-WITH-CONDITIONS.** C1 (re-ground the threshold — **applied**, see User-Brand Impact);
**C2** (fix #6415 tracking metadata — **operator action**, see decision-challenges UC-2); C3 (bound
Phase 3B — **applied: the split condition is met at plan time**, so L3 is deferred); C4 (bullet-format
User-Brand Impact — **applied**).

### GDPR / Compliance Gate (Phase 2.7)

**Assessed — no regulated-data surface.** The canonical regex (schemas, migrations, auth, API routes,
`.sql`) matches nothing. Triggers (a)/(c)/(d) do not fire. Trigger **(b) fires** (`single-user
incident`), so the gate was **assessed rather than skipped**: the only data is a **private RFC1918
address** already in `user_data` and retrievable from the hcloud metadata API — **not personal data**
under Art. 4(1). No new processing activity; **no Art. 30 entry required**. `BETTERSTACK_LOGS_TOKEN`
unchanged, still injected at cron time.

## Infrastructure (IaC)

### Terraform changes

`zot-registry.tf` (one non-secret template var) + `network.tf` (single-source the IP literal).
**No new resource, provider, variable, or secret** — so the auto-applied-root footgun
(`hr-tf-variable-no-operator-mint-default` / ADR-065) does **not** apply, and **no operator mint** is
sequenced before merge.

### Apply path

**(c) taint + scoped `-replace`** via the existing `registry-host-replace` dispatch. The `user_data`
edit is `ForceNew`; the deliberate **absence** of `ignore_changes=[user_data]` (`:274-276`) preserves
the replace-to-reprovision path.

**Nuance (verified, `:16-22`):** every resource here is an **`OPERATOR_APPLIED_EXCLUSION`** — applied by
the operator's **full untargeted** apply + the 12h drift detector, **not** the per-PR `-target=` list
(which bridges over SSH to the *existing web host* and cannot provision a new host). This is precisely
why the fix must be **on-host**: a reboot bolted into the dispatch job would cover the maintenance path
and leave the **primary** provisioning path uncovered.

- **Blast radius:** registry briefly down during the replace; serving falls back to GHCR (ADR-096). The
  **store volume survives** (only `user_data` is ForceNew), and the gate forbids a store destroy
  (`registry-host-replace-gate.sh:44`: `store_destroyed==0`).
- **Not an SSH bootstrap:** forbidden by `hr-prod-host-config-change-immutable-redeploy`; this host has
  **no SSH provisioner**.

### Distinctness / drift safeguards

`dev != prd`: N/A (prod-only infra). `ignore_changes=[user_data]` stays **absent** by design. No secret
enters `terraform.tfstate` (the new var is a literal already in state via
`hcloud_server_network.registry.ip`). **`-target` set unchanged** — no new resource ⇒ no allow-list edit
and no guard-suite sweep is owed (AC12 asserts the gate still passes).

### Vendor-tier reality check

No new vendor resource. **No `betteruptime_heartbeat` added or unpaused** ⇒
`heartbeat-reprovision-parity.test.ts` stays green **untouched** (v1's AC7 manifest-reconcile obligation
disappears with L3). Recorded for the L3 follow-up: `betterstack_paid_tier` defaults **false**
(`variables.tf:301`) ⇒ `policy_id = null` ⇒ **email-only, no escalation** (`architecture` P2).

## Downtime & Cutover

*(deepen-plan Phase 4.55 — fires because AC14 `-replace`s a running `hcloud_server`, the
infra-reboot/replace class. Zero-downtime-first is the default; residual downtime needs a
justification + a bounded window.)*

**Offline-inducing operation:** `registry-host-replace` destroys and recreates
`hcloud_server.registry` (the cloud-init `user_data` edit is `ForceNew`). **Surface affected: the
image-pull path — NOT the user-serving path.**

**Zero-downtime evaluation (the default, and it holds here — verified, not assumed):**

| Question | Verified answer |
| --- | --- |
| Is the registry on the **user serving** path? | **No.** `model.c4:260` — zot "replaces GHCR on the **pull path**". Web serving is unaffected by a registry outage; no user request touches `10.0.1.30`. |
| What happens to the **deploy** path during the window? | **Atomic fallback, not an outage.** `model.c4:380`: `hetzner -> ghcr` *"Atomic fallback pull when zot is unconfigured/unreachable — dual-pushed + break-glass through the Phase-5 soak"*. `ci-deploy.sh:80`: an empty `ZOT_REGISTRY_URL` ⇒ zot disabled ⇒ pulls fall through to GHCR. `apply-web-platform-infra.yml:1837` states it outright: *"pulls fall through to GHCR meanwhile"*. |
| Is the store lost / does it need a re-fill? | **No.** `registry-host-replace` *"preserves the zot storage volume"* (only `user_data` is ForceNew); the gate enforces `store_destroyed==0` (`registry-host-replace-gate.sh:44`). |
| Blue-green instead? | **Evaluated and rejected as disproportionate.** A blue-green registry would need a second host **and** a re-pointing of `10.0.1.30` — but that private IP *is* the stable contract: `hcloud_server_network.registry` pins it, `local.registry_endpoint` bakes it into the web hosts' `insecure-registries` docker config (`server.tf:608`), and `tunnel.tf:47` targets `tcp://10.0.1.30:5000`. Moving it is itself a multi-surface cutover — strictly more risk than a ~2–5 min fallback window on a path that already has an atomic fallback. The store volume also cannot attach to two servers at once. |

**Verdict: zero user-facing serving downtime by construction.** The residual is a ~2–5 min window in
which a deploy landing concurrently pulls from **GHCR instead of zot** — *slower, not broken*. No
maintenance window or operator sign-off is owed for the serving surface, because it is not touched.

**Precondition (load-bearing — the #6400 compounding factor).** The fallback's atomicity is what makes
this zero-downtime, and **in #6400 the GHCR fallback was itself degraded** (`image_pull_failed`, prod
pinned to `0.213.2`) — which is precisely why the registry outage escalated. So the replace is only
zero-downtime **if the fallback is healthy at that moment**:

- **Before firing AC14, verify the GHCR fallback path is green** (a recent successful deploy, or a
  GHCR pull of the current digest). If the fallback is degraded, the replace window becomes a **real
  deploy outage with no path** — defer the replace until the fallback is restored.
- This is a **read-only precondition**, no new tooling: the deploy pipeline's own recent success is
  the artifact.

**Rollback:** none in-place (ForceNew, no-SSH). Recovery is revert → merge → re-dispatch (AC15's
`nic_ok=false` branch). The store volume survives every arm of this.

## Network-Outage Deep-Dive

*(deepen-plan Phase 4.5 — fires on `unreachable`. Layer-by-layer verification status; the full
hypothesis set with artifacts is in `## Hypotheses`.)*

| Layer | Status | Artifact |
| --- | --- | --- |
| **L3 — firewall allow-list** | **Verified, not implicated** | The registry firewall filters the **public** interface only; intra-`hcloud_network` `10.0.1.0/24` traffic is **open by membership and needs no allow rule** (`zot-registry.tf:312-313`). A firewall rule cannot produce "host holds no `10.0.1.30`". Distinct from the #2681 admin-IP-drift class: no operator egress IP is involved — both endpoints are inside the private net. |
| **L3 — DNS / routing** | **Verified, N/A by construction** | No DNS resolution participates; consumers target the **literal** `10.0.1.30` (`zot-registry.tf:40`, `tunnel.tf:47`, `server.tf:608`). The missing **address/route on the guest** *is* the fault (L3), not a resolution error. |
| **L7 — TLS / proxy** | **Verified, not implicated** | zot is **plain HTTP** on the private net (`zot-registry.tf:31`); the cloudflared ingress rule (`tunnel.tf:45-47`) targets `tcp://10.0.1.30:5000` and was **unchanged** across the incident. The target address was correct — the address did not exist on any host. |
| **L7 — application (zot)** | **Verified, explicitly excluded** | #6400 records zot "running fine, `:5000`". Structurally confirmed: binds `0.0.0.0:5000` (`:375`); readiness polls `localhost:5000` (`:379-382`) — **both succeed on a NIC-less host**. This is *why* the outage presented as "zot mysteriously down". |

**Ordering discipline honored:** the fault is **L3** and every L7 hypothesis is excluded with an
artifact — the inverse of the #2654 malformed shape. **No gap needs closing before implementation.**

**The distinguisher this class turns on** (from `2026-07-07-immutable-redeploy.md` Sharp edge 2, and
the reason "zot is down" was the wrong first hypothesis): **a down container gives connection
*refused*; an unconfigured NIC gives *timeout* + ping loss.** The plan's guard makes this
determination unnecessary next time — `SOLEUR_PRIVATE_NIC` answers it directly.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_PRIVATE_NIC nic_ok=<bool> ... — the host's own assertion that its private IP is
         configured, emitted FROM the affected (blind) surface."
  cadence: "every 5 min (/etc/cron.d/soleur-private-nic-guard, flock-guarded) + once at boot"
  alert_target: "scripts/zot-restart-loop-alarm.sh -> scheduled-zot-restart-loop.yml (*/30)
                 -> deduped action-required issue"
  configured_in: "apps/web-platform/infra/cloud-init-registry.yml (emit);
                  scripts/zot-restart-loop-alarm.sh + .github/workflows/scheduled-zot-restart-loop.yml"

error_reporting:
  destination: "Better Stack Logs source 2457081 (the existing SOLEUR_ZOT_DISK sink), curl + Bearer
                BETTERSTACK_LOGS_TOKEN injected by `doppler run --project soleur-registry --config prd`"
  fail_loud: "yes — emits on BOTH success and failure; a failed POST retries once then leaves a
              journald breadcrumb (the :227 shape). Fail-OPEN toward serving (|| true at the boot call
              site): observing the boot must never break it."

failure_modes:
  - mode: "IMDS unreachable at boot (H1 — the issue's framing)"
    detection: "SOLEUR_PRIVATE_NIC imds_rc!=0   [in-surface probe, emitted FROM the affected host]"
    alert_route: "zot-restart-loop-alarm.sh -> action-required issue"
  - mode: "Attach had not landed when cloud-init ran (H2 — the structural race)"
    detection: "SOLEUR_PRIVATE_NIC imds_rc=0 && imds_nets=0 && uptime_s low"
    alert_route: "same; self-heals on a later tick (converged_by=reboot)"
  - mode: "Attach landed, guest never configured it (third, previously unnamed mode)"
    detection: "SOLEUR_PRIVATE_NIC imds_nets>0 && converged_by!=already"
    alert_route: "same"
  - mode: "Terminal — reboot budget spent, IP still absent"
    detection: "SOLEUR_PRIVATE_NIC nic_ok=false && converged_by=none && reboot_count>=2"
    alert_route: "same — human escalation"
  - mode: "SILENT SELF-HEAL — the race keeps recurring but always heals (lost ceiling)"
    detection: "SOLEUR_PRIVATE_NIC reboot_count>0 || converged_by=reboot   (nic_ok=true — the terminal
                alarm does NOT fire; this is why the advisory branch exists)"
    alert_route: "advisory branch -> action-required issue (lower severity)"
  - mode: "Post-reboot store unmounted — zot 404s fleet-wide (PRE-EXISTING; any reboot cause)"
    detection: "SOLEUR_PRIVATE_NIC zot_store_mounted=false"
    alert_route: "alarm + in-guard self-heal (mount -a + docker restart zot)"
  - mode: "The NIC guard itself is dead / the host is dead (absence)"
    detection: "a DEDICATED --grep SOLEUR_PRIVATE_NIC absence probe. NOT the existing PRODUCER_SILENT
                branch — that is keyed on $MAIN (SOLEUR_ZOT_DISK) at :106-124, so a dead NIC guard with
                a live disk heartbeat reads GREEN."
    alert_route: "new absence branch -> action-required issue"

logs:
  where: "Better Stack Logs source 2457081 (scripts/betterstack-query.sh); journald fallback breadcrumb"
  retention: "per the existing Better Stack Logs source — unchanged"

discoverability_test:
  command: |
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
      --since 30m --grep SOLEUR_PRIVATE_NIC --limit 20
  expected_output: "at least one line with nic_ok=true, zot_store_mounted=true, and converged_by in
                    {already, reboot}. NO ssh."
```

**Why a new signal, not a new threshold (`hr-observability-layer-citation`):** both live signals are
**structurally blind** — `registry_disk_prd` keeps pinging over **public** egress on a NIC-less host
(why #6400 went unseen for 14 days), and the boot readiness poll checks `localhost:5000` (`:379-382`),
which succeeds because zot binds `0.0.0.0:5000`. Neither can be re-thresholded into covering this.

**Affected-surface compliance (§2.9.2):** the registry is a **blind execution surface** (deny-all
ingress; authorizes only the operator's hcloud key, **not** `ci_ssh` — Sharp edge 3). Every `detection`
is an **in-surface** probe, and the field set **discriminates all competing hypotheses in one event**.

**Known residual (accepted, documented):** L2's *subject* is the host's **local** NIC state. It cannot
detect "private net broken from a consumer's perspective while the host thinks it's fine" — that needs
L3 (deferred). For the **observed** failure this is sufficient: #6400's host had **no `10.0.1.30` at
all**.

## Architecture Decision (ADR/C4)

### ADR

**Create `ADR-113-dedicated-host-private-nic-boot-convergence.md`.**

> **Decision:** a dedicated Hetzner host whose function depends on the private net MUST self-verify its
> expected private IP after boot, converge it within a bounded budget, and emit a discriminating
> `SOLEUR_PRIVATE_NIC` event on **every** run — because `hcloud_server_network` is an additive **online
> attach** that cannot be ordered before the guest's network stage, and because a NIC-less host retains
> **public** egress and therefore keeps every existing health signal green.
>
> **Headline:** compliance with `hr-fresh-host-provisioning-reachable-from-terraform-apply` — today a
> from-empty apply can yield an unreachable registry needing an operator reboot.
>
> **NORMATIVE BLOCKER (`architecture` P1-2 — this ADR outlives the plan and its tracking issue).** The
> reboot primitive **MUST NOT** ship to a host whose storage unlock lives in `runcmd` without a
> reboot-safe equivalent (`crypttab` or keyscript). **git-data is excluded until then**
> (`cloud-init-git-data.yml:163` `luksOpen` in `runcmd`; no `crypttab` repo-wide; `nofail` at `:118`
> ⇒ a reboot **silently unmounts** the fleet's most irreplaceable data store). A constraint discovered
> during planning belongs in the durable artifact, not the disposable one.
>
> **Scope:** `status: accepted` for **registry**; **not** class-wide until the blocker clears.

**Authority note (`architecture` P2 — v1 overreached).** `hr-prod-host-config-change-immutable-redeploy`
does **not** "bless" self-reboot: it acknowledges a reboot may be *needed* during an operator
`-replace`; it does not authorize a host to **decide to reboot itself**. This ADR earns that authority
on its own merits (bounded, corroborated, capped, counter on the root disk) rather than leaning on a
citation that does not say it.

Relationship: **extends ADR-103** (reprovision *path* → guest-side *convergence*); **complements
ADR-096/ADR-100** (dispatch mechanism); **inherits ADR-082's** fail-open, in-surface,
discriminating-telemetry doctrine. **No collision** (verified by `architecture` + `kieran`).

**Ordinal provisional.** ADR-113 is next-free vs `origin/main` (highest ADR-112), but `adr-ordinals` is
not a required check; `/ship` re-verifies. **If renumbered, sweep the artifact set in the same edit**
(`grep -rn 'ADR-113' knowledge-base/project/{plans,specs}/feat-one-shot-6415-…/`) — AC11 names the
ordinal.

### C4 views

**Two description-level edits to `model.c4` are owed** — v1's "nothing is falsified" was **wrong**
(`architecture` P2). The *enumeration* was right (no new element/actor/store; Hetzner + Better Stack
already modeled), but this model is maintained **at description granularity**, and precedent commit
`c749e4e6a` edited the C4 for a structurally identical observability change:

1. **`model.c4:396`** (`zotRegistry -> betterstack`) enumerates exactly `SOLEUR_ZOT_DISK` and
   `--grep SOLEUR_ZOT_DISK` — Phase 2 adds a **second event type** to that edge.
2. **`model.c4:400`** (`github -> betterstack`) says *"Polls the SOLEUR_ZOT_DISK Logs source … for the
   zot restart-loop recurrence alarm"* — Phase 3 adds **NIC polling** to that same alarm.
3. **`model.c4:264`** (`betterstack`, *"Apex + inngest/git-data heartbeats"*) — **no edit in this PR**;
   it becomes falsified only **if** the deferred L3 follow-up arms `registry_prd`.

Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after editing, and regenerate
`model.likec4.json` via `scripts/regenerate-c4-model.sh` (the `c4-model-freshness` orphan suite gates
it). ADR-103's "no C4 edit" precedent is a **weaker analogy** than v1 claimed — it added a dispatch
workflow + a static test (**no runtime data-flow**); this adds a runtime event type to a modeled edge.

### Sequencing

True **at merge** for the code; true **on the host** after AC14. ADR-113 is authored **now**,
`accepted` for registry, with the normative blocker gating the rest of the class.

## Risks & Mitigations

| # | Risk | Mitigation |
| --- | --- | --- |
| **R1** | **Reboot loop.** | Gate = `ip_present=false && imds_nets>0 && uptime_s>600 && reboot_count<2`; counter on the **root disk** at a named path, keyed by instance-id, **literal cap 2**, written **before** the reboot. A cap of 2 makes a storm **definitionally impossible** (v1's cooldown was redundant — cut). A replace ⇒ new root disk ⇒ fresh budget, for free. AC4. |
| **R2** | **Parse false-positive on a healthy host** ⇒ self-inflicted reboots. *(v1 mis-ranked this "highest severity"; `architecture` showed the counter makes it **structurally bounded** to ≤2 — the mitigation budget was aimed at the wrong risk.)* | `ip -4 -o addr show` **exact-word** match; `uptime_s>600`; cap 2. **AC3** asserts zero mutation on the healthy fixture. |
| **R3** | **Wrong `EXPECTED_IP` from a drifted literal** ⇒ reboots a **healthy** host to the cap, then goes terminal — and R2's mitigations are blind (parse right, constant wrong). *(The real highest-severity risk.)* | Phase 1.2 single-sources the literal; **AC6** asserts `10.0.1.30` appears **exactly once** in `*.tf`. |
| **R4** | **Post-reboot store unmounted** ⇒ zot 404s fleet-wide while `nic_ok=true`. | **Pre-existing** (any reboot cause), now **fixed**: in-guard `mount -a` + `docker restart zot` (Phase 2.1.5) + `zot_store_mounted` emitted **and alarmed** (v1 emitted it with no reader). |
| **R5** | **Silent self-heal hides the race** (lost ceiling). | Advisory alarm on `reboot_count>0` / `converged_by=reboot` (Phase 3.1) — a standing signal, not a one-time post-merge read. |
| **R6** | **Emit dies silently** (boot anchor before the token file). | Boot invocation **after `:318`**, env file sourced (`:390` precedent); AC4 structural grep. |
| **R7** | **Spoofed telemetry.** | Field renamed **`zot_last_err`** (matches the lib's literal strip at `:27`) and **trailing**; **AC9 asserts the strip actually fires** (behavior, not name). No lib fork. |
| **R8** | **Alarm regression** — NIC work breaks the zot path, or a zot early-exit masks the NIC check. | AC7 + **AC8**; `scripts/test-all.sh` in AC13. |
| **R9** | **Boot/cron race.** | **Same `flock`** on both (v1 asserted only the cron). |
| **R10** | **Test extraction is harder than the precedent** (template escaping; the precedent extracts only scalars). | Explicit un-escape/render step + PATH stubs (Phase 4.1); AC2/AC3/AC4 hang off it. |
| **R11** | **Replace fails mid-flight.** | Pre-existing/unchanged: the dispatch annotates recovery; serving falls back to GHCR. |

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| **`cloud-init clean --logs && cloud-init init --local`** (the issue's proposal) | **Rejected — three verified failure modes** (unguarded fstab append at `:294`; datasource loss ⇒ public-NIC loss on a no-SSH host; fail-closed isolation re-check FATAL). *The proposed cure for a transient IMDS blip is triggered by a transient IMDS blip.* |
| **Netplan drop-in as the converge primitive** (v1's primary) | **Rejected at review — both panels fired.** Its trigger is a **strict subset** of the reboot's; it is the plan's own *lower-fidelity* path (the reboot uses cloud-init's renderer ⇒ correct MTU **by construction**); step 5 had **no budget** ⇒ `netplan apply` every 5 min bouncing **public egress** on a deny-all no-SSH host, invisible to a 25-min absence window — **#6400's signature, self-inflicted**. Deleting it dissolves R3(MTU), R5, Phase 0.1–0.3, and ~60–75 LOC. |
| **Fix at the Terraform layer** (ordering, or a reboot in the dispatch job) | **Rejected.** No TF ordering can win (the attach needs a created, already-booting server). Registry resources are `OPERATOR_APPLIED_EXCLUSION` (`:16-22`) ⇒ a dispatch reboot leaves the **primary** provisioning path uncovered. TF sees only the control plane, which reported "attached" while the guest was broken. |
| **Inline `network {}` block** | **Rejected** — force-replaces the host (`network.tf:9-13`). |
| **Ship git-data + inngest** (the issue's stated scope) | **Rejected on safety.** git-data's `luksOpen` is in `runcmd` (`:163`) — per-instance, **not** re-run on reboot — with **no `crypttab`** (verified repo-wide) and `nofail` (`:118`) ⇒ a reboot **silently unmounts** the data store. Both hosts also fail *loudly* today, lacking the silent-failure property that motivates #6415. → tracking issue, blocked on a reboot-safe unlock. |
| **L3 off-host probe as required-for-close** (v1) | **Deferred.** v1's justification — a git-data probe-cron precedent + "the remaining work is small" — was **false**: `apply-web-platform-infra.yml:2198-2206` says the probe cron is *"unbuilt"*, and `ZOT_HEARTBEAT_URL` has **zero consumers**. L3 is **greenfield** on a different host via an unresolved delivery path (web hosts carry `ignore_changes=[user_data]`), and its arming is blocked by `ignore_changes=[paused]` (`:355`) ⇒ the flip is a **no-op** and the real unpause is a **Better Stack UI** step. CPO condition C3 (split if the delivery site is unresolved) is **met at plan time**. |
| **`Type=oneshot` unit instead of `/etc/cron.d`** | **Rejected.** A boot-only one-shot cannot heal an attach landing **later** (H2 — the leading hypothesis). `/etc/cron.d` is this host's **established** cadence (`:236-243`) and carries the `doppler run` wrapper. It also avoids the oneshot-liveness trap (`inactive` reads as healthy). |

## Deferred Items — Tracking Issues Required

Each needs a GitHub issue **in the same PR** (what, why, re-evaluation criteria, milestone):

1. **L3 — off-host private-net probe** (arm `registry_prd`; `git_data_prd` sibling). **Greenfield.**
   Must resolve: the web-host **delivery site** (`ignore_changes=[user_data]` ⇒ not cloud-init); the
   **arming blocker** — `ignore_changes=[paused]` (`:355`) makes a source flip a **no-op**, so either
   drop that attribute for `registry_prd` (+ reconcile the ADR-103 manifest **in the same PR**) or arm
   via the Better Stack API (already called at `apply-web-platform-infra.yml:1803`); the **cadence
   mismatch** — `period=60/grace=30` needs a ping ≤90s vs a **60s cron floor** + 2 HTTP round trips ⇒
   flapping (widening `period` is a TF change the parity manifest asserts); and
   `betterstack_paid_tier=false` ⇒ **email-only, no escalation** (`variables.tf:301`).
2. **Generalize the guard to git-data + inngest.** **Blocked** on a reboot-safe LUKS unlock for
   git-data (see the ADR-113 normative blocker).
3. **Web hosts (`10.0.1.10/.11`).** They share the race **and the silent-failure property** —
   `model.c4:380` (`hetzner -> ghcr`, *"Atomic fallback pull when zot is unconfigured/unreachable"*)
   means a web host booting NIC-less falls back to GHCR and **deploys keep working**: the identical
   14-day shape (`architecture` Q6 — v1's "registry is the only host with the silent-failure property"
   was **wrong**; the property belongs to the **zot pull path** and is symmetric across both ends).
   Delivery needs the bake-and-extract path. **Re-evaluation criterion:** do **not** wait on the
   unbounded "next ADR-068 blue-green recreate window".

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| T1 | Healthy — `ip addr` contains `10.0.1.30` | `converged_by=already`, `nic_ok=true`, **no mutation** (R2/AC3) |
| T2 | H1 — `imds_rc≠0` | `nic_ok=false`; **no reboot** (no corroboration) |
| T3 | H2 — `imds_rc=0, imds_nets=0` | `nic_ok=false`; no reboot; heals on a later tick |
| T4 | Corroborated, `uptime_s>600`, counter unexhausted | counter written **then** exactly one reboot |
| T5 | Counter exhausted | **no** reboot; `converged_by=none` → terminal alarm |
| T6 | `uptime_s<600` (just booted) | **no** reboot regardless of corroboration |
| T7 | Store unmounted post-reboot | `mount -a` + `docker restart zot`; `zot_store_mounted` emitted |
| T8 | NIC guard silent while `SOLEUR_ZOT_DISK` still flows | alarm **FIRES** (not GREEN) — the `spec-flow` P0 |
| T9 | zot early-exit (`zot_restarts=-1`) + `nic_ok=false` | NIC check **still evaluated**; no exit-4 |
| T10 | `converged_by=reboot`, `nic_ok=true` | **advisory** branch only; no duplicate |
| T11 | Spoof attempt — crafted `zot_last_err` tail containing `nic_ok=true` | strip **fires**; the spoof never reaches the trusted region |

## AI-Era Notes

- Research: `Explore`, `learnings-researcher`, `cto`. Review: `dhh`, `kieran`, `code-simplicity`,
  `architecture-strategist`, `spec-flow-analyzer`, `cpo`.
- **The three highest-leverage findings all came from outside the issue body:** (1) a **learning file**
  already documented this exact failure on this exact host; (2) the **CTO** turned the issue's own
  stated scope into a safety hazard (git-data LUKS); (3) **spec-flow** caught that the plan author
  asserted a repo capability that does not exist (`hr-verify-repo-capability-claim-before-assert`) —
  and that false claim was the **sole basis** for a required-for-close scope elevation.
- **Lesson for the next planner:** v1 was rigorous about the layer it invented (L1) and **credulous
  about the layers that make L1 matter** (L2's emit→human leg had no AC and a false absence claim; L3
  could not arm at all). **Verify the *consumer* with the same rigor as the *producer*** — an emit with
  no reader is decoration, and an AC that passes on an unmodified file is not a gate.
- Every named artifact (paths, line numbers, ADR ordinal, `local.*` names, the absence of `crypttab`,
  the `paused`/`ignore_changes` shapes, the `sed` literal) was verified against the working tree /
  `origin/main` at plan-write time rather than paraphrased.
