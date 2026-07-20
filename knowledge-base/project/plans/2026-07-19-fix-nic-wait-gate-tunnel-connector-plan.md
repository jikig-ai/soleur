---
title: "fix: NIC-wait gate before cloudflared connector registration (ADR-114 §I1)"
date: 2026-07-19
type: fix
issue: 6441
umbrella: 6178
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_adrs: [ADR-114, ADR-115, ADR-100, ADR-096, ADR-080, ADR-068]
related: [6441, 6178, 6425, 6426, 6594, 6466, 6500, 6090, 5921, 6122, 6415, 6400]
status: draft
---

# fix: NIC-wait gate before cloudflared connector registration (ADR-114 §I1)

> **Lane note:** no `spec.md` exists for this branch, so `lane:` could not be carried
> forward. Defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened:** 2026-07-19 · **Reviewers/researchers:** CTO domain lead,
architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer, security-sentinel,
learnings-researcher, best-practices-researcher, C4 completeness read, precedent-diff sweep.

### Key improvements (each changed the plan, not just annotated it)

1. **A design contradiction was found and fixed.** The first draft put the timeout emit in
   a caller-side `|| soleur-boot-emit …` arm *while* specifying the helper exits 0 on
   timeout — so the arm could never fire and `private_nic_timeout` would never be emitted,
   breaking the plan's only observability guarantee. The same single arm also could not
   discriminate ready / timeout / probe-fault, so a probe fault would have been mislabelled
   as "NIC absent" — the exact #6415 defect this plan cites. **Fix:** all emission moved
   inside the helper; three mutually-exclusive arms; no caller-side error handling.
2. **A P0 delivery hazard was found that the plan had described as safe.** `Apply path`
   originally called the two delivery channels independent with "zero downtime". They are
   **coupled** by `host_scripts_content_hash`, whose mismatch aborts the entire runcmd at
   `cloud-init.yml:559` under `set -e`. Verified the existing coherence guard covers
   **only** the web-2-recreate job — not the routine apply or a fresh `web-1` create, which
   is this plan's target path. Now AC-gated.
3. **A contract inversion was avoided.** The draft added a `nic` *verb* to the fail-closed
   `soleur-wait-ready`, then spent a section, an AC, and two test edits managing the
   inversion. Replaced with a **separate** `soleur-wait-nic`, leaving the shared helper
   byte-identical and deleting the whole cascade.
4. **The load-bearing uncited claim is now verified.** "cloudflared resolves origin per
   connection" — **CONFIRMED** against `cloudflared` source and four Cloudflare doc pages.
   It carries both the ExecStartPre rejection and the severity split, so verifying it was
   not optional.
5. **The severity framing was reconciled with the engineering analysis.** The draft used
   the maximal framing ("serves nothing") to justify the threshold and the minimal framing
   (self-healing) to justify a deferral, without reconciling them. Now split explicitly
   into common vs pathological case, with the threshold justified by the pathological case
   **having actually occurred** (#6400, ~14 days, all signals green).
6. **The helper now conforms to house precedent** on loop shape, probe resolution, match
   flags, and stage naming — with the one deliberate divergence (fail-open next to a
   fail-closed sibling gating the same step) documented rather than left to be discovered.
7. **Tests were unrunnable as specified.** The harness is grep-only and never renders the
   template, so the render tests and behavioural tests could not execute — silently
   degrading two ACs to string-presence proxies. A render step and a stub-`ip` extraction
   harness are now in scope.
8. **17 ACs → 9**, after removing three structurally unsatisfiable, four proxies, and two
   self-contradictory ones.

### New considerations discovered

- **The blast radius is larger than the archived analysis assumed.** Post-#6594 *all three*
  ingress services are private-IP-relative, so a NIC-less connector serves **nothing** —
  the inherited CF-5 trade table ("only `registry.` breaks") is stale.
- **The C3 budget collision** — an `ExecStartPre` NIC wait would consume
  `cloudflared_ready`'s ~60 s budget and detonate its pre-existing `|| exit 1`, causing the
  very CF-5 abort this work exists to prevent. Found during planning, independently
  confirmed at review.
- **The firewall attach shares the NIC's construction-order race** (`firewall.tf:91-93`) —
  same "attach cannot precede create" fact, never written down. Out of scope; flagged.
- **Two AC-authoring defects were caught by executing the ACs**, not by reading them:
  `grep -c` exits 1 on a zero count (fails on the *passing* case), and an unscoped
  `git diff` AC matches this plan's own prose about reboots.
- **This path is not digest-pinned at all** (`:latest`), but the integrity control that
  matters here is the repo-derived content hash — *stronger* than a digest for this
  purpose. Reliance on the unsigned image does not increase.

## Overview

On a freshly-provisioned `web-1`, cloud-init registers the host as the Cloudflare
tunnel's **sole** connector before its Hetzner private NIC exists. ADR-114 §I1 says a
host MUST NOT serve as a connector unless its private NIC is up. That invariant is
recorded but **not enforced at runtime** — `#6425`'s single-connector gate reduced the
*population* that can violate it; it did not add the wait.

This plan adds the missing runtime gate: **wait for the private NIC, then register the
connector — and on timeout, defer and continue. Never abort. Never reboot.**

### Why the race is unfixable upstream

`server.tf:158` passes `tunnel_token` via cloud-init `user_data` at server **create**,
while `hcloud_server_network.web` cannot exist until `hcloud_server.web[k].id` does.
**The attach ALWAYS lands after the token.** This is stated verbatim in ADR-114 §I1 and
is why the ADR states I1 as a *runtime* precondition rather than a construction-time one.

### What this plan does NOT do

Scoped to **#6441 only**. Explicitly out: `#6500` (zot enrollment), `#6466`
(host-addressability), the operator-gated force-replace, and ADR-114 §I2's
origin-relative work beyond the status reconciliation in Phase 4.

---

## Research Reconciliation — Spec vs. Codebase

Every figure below was **re-derived live at branch HEAD this session**. Inherited
figures are marked where they proved stale.

| Claim (as inherited) | Reality (measured this session) | Plan response |
|---|---|---|
| "cloud-init user_data has ~78 B headroom" | **Reproduces.** Live: `22,372 B` measured against `WEB_GZIP_BUDGET = 22_450` → **78 B headroom**. Hard Hetzner cap `32,768` → 10,396 B. | Confirmed. The **binding constraint is the CI budget, not the Hetzner cap** — a distinction the issue framing blurs. Phase 3 re-measures and re-baselines if needed. |
| "The #6500 Phase 0 comment carries the user_data budget context" | **False pointer.** #6500's Phase 0 comment contains **zero byte figures**; its "headroom" is a *Doppler secret-name count* (`n_total=5` at a `-lt 5` floor). | The web budget authority is `apps/web-platform/infra/variables.tf:429-450` + `plugins/soleur/test/cloud-init-user-data-size.test.ts`. Cite those, not #6500. |
| "A NIC-less connector breaks only the `registry.` route; `deploy.` + `ssh.` stay up" (archived plan CF-5 trade table) | **STALE as of #6594.** All three routable ingress services in `tunnel.tf` are now private-IP-relative: `deploy.` → `http://10.0.1.10:9000` (`:53-54`), `ssh.` → `ssh://10.0.1.10:22` (`:70-71`), `registry.` → `tcp://10.0.1.30:5000` (`:106-107`). | **Blast radius is total ingress loss, not partial.** The trade table is corrected in Phase 4. This materially *strengthens* the case for the gate and is reflected in User-Brand Impact. |
| "#6441 is the NIC-wait gate (ADR-114 §I1)" | **Confirmed**, though the issue's live *title* says "origin-relative ingress — ADR-114 I2 residual". ADR-114 §I1 (`:159-163`) states the cloud-init NIC gate and says *"tracked in #6441"*. | Correct premise. The issue tracks both I1 and I2 residuals; this plan takes the **I1** half only. |
| "Reuse `web-private-nic-guard.sh`'s `EXPECTED_IP`" | **Unavailable on the target path.** That value is written by an SSH provisioner (`server.tf:479`) which reaches **running hosts only**. On the fresh boot this gate exists for, `/etc/default/web-private-nic-guard` does not yet exist. | The expected IP must come from `templatefile` vars. Phase 1 adds `private_ip` to the map in `server.tf` (not byte-budgeted). |
| Learnings research recommended: "the NIC-wait gate must **abort the boot** (`exit 1`) if the NIC doesn't converge" | **Rejected — this is exactly finding CF-5.** The recommendation was generalized from the sibling fail-closed readiness gates. | Recorded as a rejected alternative. That an independent research pass reproduced the wrong instinct is *evidence the guard-rail must be loud in code*, hence AC2's CF-5 regression guard. |
| Learnings research: "you likely have ~15 KB headroom" | **False for the web host.** That figure is the git-data host's. Web has 78 B under the CI budget. | Ignored; live measurement governs. |

---

## Hypotheses

The network-outage checklist gate fired on `timeout`. This is a **feature plan, not an
outage diagnosis**, so the L3→L7 discipline applies structurally rather than
diagnostically — and it is, in fact, the plan's whole thesis:

| Layer | Status | Artifact |
|---|---|---|
| **L3 — private NIC / routing** | **This is the layer being gated.** The defect is that L7 (connector registration) proceeds before L3 (private NIC attach) converges. | `tunnel.tf:53-107` — all ingress services dial RFC1918. |
| L3 — firewall allow-list | Not implicated. No allow-list change; the host keeps public egress throughout. | n/a |
| L4/L7 — cloudflared service | **Downstream of L3 by design after this change.** Today it is ordered *before* L3, which is the bug. | `cloud-init.yml:598` |
| L7 — sshd / fail2ban | Explicitly **not** hypothesised. Per `hr-ssh-diagnosis-verify-firewall`, no service-layer cause is proposed. | n/a |

**No reboot hypothesis is entertained** (ADR-115, finding CF-6).

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

The gate fired on `timeout` / `unreachable`. Layer-by-layer verification status, per
`plan-network-outage-checklist.md`. Telemetry emitted
(`hr-ssh-diagnosis-verify-firewall applied`).

| Layer | Verified? | Artifact / note |
|---|---|---|
| **L3 firewall allow-list** | **Not applicable — and deliberately so.** | This plan changes no firewall rule and no allowlist. The host retains public egress throughout the wait, which is *why* deferral preserves a recovery channel. No `hcloud firewall describe` diff is required because no operator-egress path is involved: the failure is host-internal (web-1 cannot reach its **own** `10.0.1.10`). |
| **L3 DNS / routing** | **Verified — this is the layer at fault.** | The defect is the absence of the private-NIC route at cloud-init time. `tunnel.tf:53-107` shows all three ingress services dial RFC1918 literals, so no DNS resolution is involved at all. Confirmed by reading `tunnel.tf` this session. |
| **L7 TLS / proxy** | Not implicated. | The tunnel terminates TLS at Cloudflare's edge; the origin dial is plaintext over the private net. No certificate or proxy change. |
| **L7 application** | **Explicitly not hypothesised first.** | Per `hr-ssh-diagnosis-verify-firewall`, no sshd/fail2ban/app-layer cause is proposed. The plan's whole thesis is that L7 (connector registration) must be **ordered after** L3 (NIC attach) — the L3→L7 discipline is the fix, not merely the diagnostic order. |

**Gap to close before implementation:** none at the network layers. The one open
verification is *not* network-layer — it is the cloudflared origin-resolution semantics
(Phase 0.5), which determines whether the residual outage is bounded or unbounded.

### Downtime & Cutover determination (deepen-plan Phase 4.55)

**Gate evaluated; does NOT fire.** Recorded because the skip is a judgment call:

- **Infra reboot/replace class — excluded by the gate's own carve-out.** The gate exempts
  attributes the serving host pins via `lifecycle { ignore_changes = [...] }`. `server.tf:278`
  carries `ignore_changes = [user_data, ssh_keys, image, placement_group_id]` on
  `hcloud_server.web`, so the `cloud-init.yml`
  edit does **not** plan a replace or a power-off of the running `web-1`. No
  `server_type` / `location` / `placement_group_id` change; no singleton→cluster cutover.
- **Database lock class:** no migration, no DDL, no backfill.
- **Deploy/router class:** no container swap, no tunnel restructure, and **no restart of
  the running connector** — the gate lives on the *first-boot* path only.

Residual availability consideration is the **P0 bake/apply skew** documented under
Infrastructure (IaC), which is a *fresh-create* hazard rather than a cutover of a serving
host. It is handled there with an AC rather than a maintenance window, because no window
would help: the failure would land on a host that is being created, not drained.

---

## User-Brand Impact

**If this lands broken, the user experiences:** total loss of the Soleur web platform's
ingress. Because all three tunnel routes are private-IP-relative (`#6594`), a `web-1`
that registers as connector without its NIC serves **nothing** — `app.soleur.ai`
management reads, the `deploy.` webhook, and `ssh.` CI access all dark. Worse, if this
change is implemented with an `|| exit 1` (the CF-5 trap), the boot aborts *before* the
webhook binary, the monitors and the container egress firewall install — an
unrecoverable, once-per-instance loss with **no in-band recovery channel**.

> **[Reconciled at plan-review — the duration claim above was overstated.]** Review
> correctly flagged that "serves nothing" reads as *permanent*, while D4 finding 2 says a
> NIC-less connector **self-heals when the NIC attaches** (cloudflared resolves its origin
> per connection). Both are true of different cases, and the honest split is:
>
> - **Common case (normal create/replace):** the window is bounded by NIC-attach time —
>   seconds to a few minutes — and occurs while `web-1` is being provisioned and is *not
>   yet serving anyway*. Real, but modest.
> - **Pathological case (the one that motivates this work):** the NIC-attach may **never**
>   land. This is not hypothetical — it is exactly #6400/#6415, where the registry host
>   held no private IP for **~14 days with every health signal green**. In that case
>   "serves nothing" is accurate and unbounded.
>
> **Threshold stays `single-user incident`**, justified by the pathological case having
> actually occurred in production on a sibling host — not by the common case. The gate's
> primary value is that it converts the pathological case from *silent* to *observed* at
> the moment of decision. Stated this way so CPO sign-off is given against the real
> distribution rather than the worst-case framing.

**If this leaks, the user's data/workflow is exposed via:** no new data surface. The one
security-adjacent consideration is that `tunnel_token` already rides `user_data`; this
plan neither moves nor widens it. A NIC-less connector is an *availability* failure, not
a confidentiality one.

- **Brand-survival threshold:** `single-user incident`.

Rationale: `web-1` is the **sole live origin** (ADR-115 is explicit that a web-host
reboot would power off the only origin). One bad boot is one total outage for the only
user. `requires_cpo_signoff: true` is set accordingly.

---

## The central design constraint (read before implementing)

Three constraints bound the entire solution space. Two are inherited; **the third was
discovered this session and is the most dangerous.**

### C1 — `runcmd` is ONE shell (CF-5)

`cloud-init.yml` states it verbatim:
`set +e # H3 (#6090): scope set -e — runcmd is ONE /bin/sh; leak = silent abort (plan).`

An `|| exit 1` does not skip a step; it **terminates the whole remaining runcmd** —
cloudflared install, webhook binary + unit, the `:9000` readiness gate, disk/resource
monitors, and the container egress firewall. `runcmd` is **once-per-instance**: a reboot
does not re-run it. A NIC that converges at minute 11 is then irrelevant; the host never
installs cloudflared, permanently.

### C2 — no reboot on the web host (CF-6 / ADR-115)

`web-private-nic-guard.sh:5-9` records the deliberate divergence: *"It DIVERGES from the
registry guard in ONE deliberate way: it NEVER reboots… on a web host a reboot would
power-off the SOLE live origin, so the web variant is detect + emit + alarm ONLY."*
ADR-115's grant is **registry-host-scoped and explicitly not class-wide**. Any web-host
converge-by-reboot is an ADR-115 amendment + CPO decision, not an implementation detail.

### C3 — ⚠️ the NIC wait can trip the EXISTING fail-closed gate (discovered this session)

`cloud-init.yml:601` already runs, inside the same `%{ if web_tunnel_connector ~}` block:

```
- soleur-wait-ready service cloudflared cloudflared_ready || exit 1
```

`soleur-wait-ready`'s budget is **30 iterations × `sleep 2` ≈ 60 s**
(`soleur-host-bootstrap.sh`, the `WAITEOF` heredoc). During a systemd `ExecStartPre`,
the unit is `activating`, so `systemctl is-active --quiet` returns **false**.

**Therefore:** a NIC wait expressed as an `ExecStartPre` on `cloudflared.service` that
runs longer than ~60 s consumes `cloudflared_ready`'s entire budget, that gate times out,
and its **pre-existing `|| exit 1` aborts the whole runcmd** — causing the exact CF-5
catastrophe this work exists to prevent.

This interaction is the single highest-risk aspect of the change. It is why the design
below places the wait **before `cloudflared service install`** rather than relying on
`ExecStartPre` alone, and why AC5 pins the budget relationship numerically.

> **Note (scoped OUT, recorded):** that pre-existing `|| exit 1` at `:601` is itself a
> live CF-5 hazard that predates this plan. It is **grandfathered, not endorsed** —
> `soleur-host-bootstrap-observability.test.sh:152` currently *pins* it by exact string.
> Changing it is a separate decision with its own blast radius. See "Deferred" below.

---

## Design

**Principle: defer, don't abort.** A slow NIC must *delay* connector registration, not
terminate the boot. Deferral preserves the recovery channel; abortion destroys it.

### D1 — a separate baked `soleur-wait-nic` helper (baked; **0 user_data**)

> **[Revised at plan-review]** The first draft added a `nic` *verb* to the existing
> `soleur-wait-ready`. Review established that this is **collision, not reuse**: the
> helper is 12 lines (`soleur-host-bootstrap.sh:307-319`) and the NIC probe shares
> *nothing* with it but a `sleep 2` loop — different match logic, different timeout, and
> an **inverted exit contract** (`soleur-wait-ready` is fail-closed by construction; the
> NIC wait must be fail-soft). Adding the verb forced a header-comment rewrite, an extra
> AC, and a test-text rewrite purely to manage the inversion.
>
> **Bake a separate `soleur-wait-nic` instead.** Soft-by-construction, no shared contract
> to invert, ~4 duplicated shell lines, still 0 user_data. This deletes the entire
> inversion cascade and leaves `soleur-wait-ready`'s existing greps
> (`soleur-host-bootstrap-observability.test.sh:145-148`) passing **untouched**.

`soleur-wait-ready` is authored by `soleur-host-bootstrap.sh`, which is **baked into the
app image** (#5921 bake-and-extract) and extracted at boot. Adding a third verb costs
**zero user_data bytes** — this is precisely the "prefer baking over inline" guidance the
budget comments repeatedly give, and unlike `#6425`'s connector gate (a `templatefile`
directive, irreducibly render-time) this gate is boot-time behaviour, so baking is
available.

**Contract: `soleur-wait-nic` owns ALL emission internally and ALWAYS exits 0.** It emits
**exactly one** event per invocation, from one of three mutually-exclusive arms:

Shape below **conforms to house precedent** (see Precedent Diff): `IP_BIN` + `PROBE_OK`
resolution, probe-once-before-the-loop, `for i in $(seq 1 30) … sleep 2` (30 × 2 s = 60 s),
`grep -qwF --`, snake_case domain-prefixed stages.

```sh
# usage: soleur-wait-nic <expected-ip>
# ALWAYS exits 0. Emits exactly one event. Never aborts a boot.
EXPECTED="$1"

# Probe resolution FIRST — `ip` lives in /usr/sbin, absent from some minimal PATHs.
IP_BIN=$(command -v ip 2>/dev/null || true)
PROBE_OK=true; [ -n "$IP_BIN" ] && [ -x "$IP_BIN" ] || PROBE_OK=false

# Probe-fault SHORT-CIRCUITS before the wait — never spend 60 s on a missing binary,
# and never read "could not measure" as "the address is absent" (#6415).
if [ "$PROBE_OK" != true ]; then
  soleur-boot-emit private_nic_probe_fault warning; exit 0
fi

nic_ok=false
"$IP_BIN" -4 -o addr show 2>/dev/null | grep -qwF -- "$EXPECTED" && nic_ok=true
if [ "$nic_ok" = false ]; then
  for i in $(seq 1 30); do
    sleep 2
    "$IP_BIN" -4 -o addr show 2>/dev/null | grep -qwF -- "$EXPECTED" && { nic_ok=true; break; }
  done
fi

if [ "$nic_ok" = true ]; then soleur-boot-emit private_nic_ready info
else soleur-boot-emit private_nic_timeout warning
fi
exit 0
```

`grep -qwF` (exact word, fixed string) is deliberate and mirrors
`web-private-nic-guard.sh:44` — it prevents `10.0.1.1` matching inside `10.0.1.10`.
`IP_BIN` is resolved via `command -v ip` (**not** bare `ip`): the
`2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument`
learning records that `ip` lives in `/usr/sbin`, absent from some minimal PATHs, and an
unresolvable probe must never be read as "the address is absent" — hence the **third**
arm rather than folding probe-fault into the timeout arm.

> **[Revised at plan-review — this resolves three P0 contradictions in the first draft.]**
> The first draft put the timeout emit in a caller-side `|| soleur-boot-emit …` arm while
> also specifying the helper exits 0 on timeout. Review established that combination is
> **self-defeating**: if the helper exits 0, the `||` arm *never runs*, so
> `private_nic_timeout` is never emitted — and that emit is the plan's only evidence the
> gate ran at all. The same single `||` arm also could not discriminate three outcomes
> (ready / timeout / probe-fault), so a probe fault would have been mislabelled as
> "NIC absent" — **precisely the #6415 defect this plan cites as a thing to prevent.**
>
> Moving all emission inside the helper fixes all three at once: one event per boot, three
> distinguishable stages, no caller-side error handling to get wrong.

#### D1a — why a separate helper, not a fourth argument

`soleur-wait-ready` is **fail-closed by contract**: its timeout branch is
`soleur-boot-emit "$STAGE" fatal; exit 1`, and its header states *"Callers do `|| exit 1`
to abort the boot on timeout — a never-ready service SHOULD fail it."*

Threading a soft/hard flag through the shared loop would make that fail-closed contract
**conditional**, inviting a future caller to silently get the wrong semantics on a boot
path where the wrong one bricks the host. A separate helper keeps each contract
unconditional and locally readable. The ~4 duplicated lines are the cheaper side of that
trade by a wide margin.

### D2 — call it BEFORE `cloudflared service install`, **without** `|| exit 1`

At `cloud-init.yml:597-598`, inside the existing connector gate — **no `||` clause at all**:

```
%{ if web_tunnel_connector ~}
  - soleur-wait-nic ${private_ip}
  - cloudflared service install ${tunnel_token}
  - soleur-wait-ready service cloudflared cloudflared_ready || exit 1
%{ endif ~}
```

Four properties, each load-bearing:

- **No `|| exit 1`** → C1 satisfied. On timeout the boot continues; cloudflared installs
  anyway; the host lands in *today's* state plus a warning row. **Never worse than today.**
- **No `||` clause at all.** Architecture review confirmed `set +e` is in effect from
  `cloud-init.yml:568` through `:598` and `:601` — pinned by
  `soleur-host-bootstrap-observability.test.sh:135-139`. So a bare call is *already*
  non-aborting; the safety property comes from the **absence of `exit 1`**, and `:618`
  (`webhook_bound || exit 1`) is the proof by contrast that an explicit `|| exit 1` is
  required to abort under `set +e`. A caller-side `||` would add nothing but a way to get
  the emission wrong.
- **Before the install** → C3 satisfied. The wait is spent *outside* `cloudflared_ready`'s
  60 s budget, so it cannot trip the pre-existing fail-closed gate.
- **Exactly one event per boot**, from the helper, on all three arms → a NIC that never
  converges produces a **row, not a silence**.

### D3 — NIC budget must compose with the downstream gate

The `nic` wait budget is a **new, separate** budget from `cloudflared_ready`'s 60 s. It
is spent before the install, so the two are sequential, not nested. Recommended starting
budget: **60 s** (30 × 2 s, reusing the existing loop constant so no new tunable is
introduced). Phase 2 must assert the two budgets are sequential and independent (AC5).

### D4 — deliberately NOT `ExecStartPre` (in this PR)

The archived plan's B1 suggested an `ExecStartPre` or an `After=` oneshot, reasoning that
`runcmd` is once-per-instance so a runcmd wait covers only first boot. That reasoning is
structurally correct, and `ExecStartPre` is the shape that best matches I1's *runtime*
framing. It is nonetheless **deferred**, for three reasons — the third of which was
surfaced by engineering review and substantially weakens the case for it:

1. **It carries the CF-5 risk; the runcmd shape does not.** Per **C3**, an `ExecStartPre`
   sits in `activating` state, so `systemctl is-active --quiet` returns false for the
   entire wait — directly consuming `cloudflared_ready`'s 60 s budget behind a live
   `|| exit 1`. Engineering review confirmed this independently and rated the drop-in
   design **high CF-5 risk as written**. The runcmd shape (D2) removes the interaction
   entirely, because the wait completes *before the unit exists*.
2. **Making it safe requires re-tuning a fail-closed gate** that is currently pinned by an
   exact-string test assertion — coupling a low-risk fix to a change that can brick the
   sole origin.
3. **The value it buys is smaller than assumed.** Engineering review established that
   **cloudflared resolves its ingress origin per connection, not at process start.** A
   connector that registered NIC-less therefore **self-heals the instant the NIC
   attaches** — no restart, no operator action, no rebuild. So "NIC-less connector
   registers eventually" is not a stuck bad state; it is a converging one. Meanwhile the
   *runtime* case (NIC lost on an already-running host) is already covered by
   `web-private-nic-guard.timer`. The provisioning race itself
   (`network.tf:9-13`, additive attach after create) is a **first-boot** phenomenon —
   exactly what D2 covers.

   > **✅ VERIFIED at deepen-plan — the claim is CONFIRMED against primary sources.**
   > It had been flagged as load-bearing-but-uncited (it carries both this rejection *and*
   > the User-Brand Impact severity split). Research resolved it:
   >
   > - **cloudflared dials origins lazily, per request** — not at process start.
   >   `proxy.go` establishes the origin connection during `RoundTrip` / `proxyStream`'s
   >   `originDialer.EstablishConnection()`, i.e. triggered by incoming traffic;
   >   `ingress/origin_service.go`'s `start()` initialises config but opens no connection.
   > - **Cloudflare docs, origin configuration:** *"Connections are created **on demand**
   >   and reused where possible, with no persistent idle pool… **new connections are
   >   created as traffic resumes**."*
   > - **No startup origin validation exists.** The 2026.5.2 connectivity pre-checks
   >   validate only the *Cloudflare edge* path (DNS for `region{1,2}.v2.argotunnel.com`,
   >   UDP/TCP 7844, api.cloudflare.com) — never origin reachability. The tunnel-status
   >   doc is explicit: *"The tunnel status only reflects the connection between cloudflared
   >   and the Cloudflare network. It does not indicate whether cloudflared can reach your
   >   internal services."*
   > - **Applies to all rule types** (HTTP, TCP/SSH), and **IP literals get no special
   >   eager treatment** — they dial per request exactly as hostnames do.
   >
   > Sources: `github.com/cloudflare/cloudflared` (`proxy/proxy.go`,
   > `ingress/origin_service.go`); `developers.cloudflare.com` origin-configuration,
   > connectivity-prechecks, tunnel-status, and common-errors pages.
   >
   > **Consequence:** a NIC-less connector is genuinely a *converging* state — the
   > rejection above and the severity split both stand. **Residual gap (unchanged):**
   > nothing observes *"NIC up but connector still not serving"* —
   > `web-private-nic-guard.sh:94` reports `nic_ok=`, never connector-serving state.

**If the drop-in is ever taken**, three requirements are non-negotiable and must be
asserted by tests, not comments:

- **`ExecStartPre=-/usr/local/bin/soleur-wait-nic …`** — the leading `-` makes the
  CF-5 property **structural**: a missing binary, a bootstrap authoring miss, or a script
  bug then cannot fail the unit and cannot reach `|| exit 1`. This is the cheapest way to
  stop the safety property depending on the script always returning 0.
- **NIC-wait budget < 45 s** — leaves ≥15 s of `cloudflared_ready`'s 60 s window and
  clears systemd's 90 s default `TimeoutStartSec` by ~2×.
- **Pin `TimeoutStartSec=` explicitly in the same drop-in** rather than inheriting
  `DefaultTimeoutStartSec`, so a distro or `system.conf` change cannot move this gate's
  failure mode.

Plus: single-source the drop-in **directory name** against the unit name used at
`cloud-init.yml:601`. A typo'd `cloudflared.service.d` produces **zero error and zero
gate** — a silent no-op.

**Split:** first-boot coverage here; restart-path coverage in a follow-up that owns the
`cloudflared_ready` budget question. Filed as a deferral (see "Deferred").

---

## Files to Edit

- `apps/web-platform/infra/soleur-host-bootstrap.sh` — bake a **separate**
  `soleur-wait-nic` helper (**0 user_data**). The existing `soleur-wait-ready`
  (`:307-319`) is left **byte-identical**.
- `apps/web-platform/infra/cloud-init.yml` — one `runcmd` line before
  `cloudflared service install`, inside the existing `web_tunnel_connector` gate.
  **The only user_data cost in the change.**
- `apps/web-platform/infra/server.tf` — add `private_ip = each.value.private_ip` to the
  `templatefile` vars map (~line 175-248). Not byte-budgeted.
- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` — assert the
  `soleur-wait-nic` helper is baked, that its three arms behave (via the stub-`ip`
  harness), and that the call site renders with **no `||` clause and no `exit 1`**.
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` — re-baseline
  `WEB_GZIP_BUDGET` **only if** Phase 3 measurement requires it, with the measured
  before/after and rationale in the comment block (the #6425/#6594/#6604 precedent).
- `knowledge-base/engineering/architecture/decisions/ADR-114-one-tunnel-many-connectors-ingress-must-be-origin-relative.md`
  — new consolidating amendment reconciling I1's three inconsistent status statements
  (Phase 4).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — three description
  corrections at `:178`, `:406`, `:408` (Phase 4.4). No new elements or relationships.

**Files to Create:** none.

---

## Implementation Phases

### Phase 0 — Preconditions (verify before writing code)

0.1 Re-run the live size measurement and record the number in the PR body:
```bash
bun test plugins/soleur/test/cloud-init-user-data-size.test.ts
```
Baseline established this session: **22,372 B / 22,450 B budget → 78 B headroom.**

0.2 Confirm `soleur-host-bootstrap.sh` runs **before** the cloudflared block. Verified
this session: bootstrap invocation `cloud-init.yml:566`; cloudflared install `:598`.

0.3 Confirm `soleur-boot-emit` supports the `warning` level. Verified: its usage line is
`soleur-boot-emit <stage> [info|warning|fatal]`.

0.4 Confirm `private_ip` is **not** already a `templatefile` var (it is not — the map at
`server.tf:175-248` carries `host_name`, `registry_endpoint`, `workspaces_volume_id`,
etc., but no `private_ip`). Separately confirm the **attribute exists on the object
type**: `variables.tf:98` declares `private_ip = string` in the `web_hosts` object, with a
`10.0.1.0/24` regex validation. Both checks are needed — "absent from the map" and
"present on the object" are different propositions.

0.5 **Verify the per-connection origin-resolution claim** (see D4 finding 2's warning
box). It is load-bearing for both the deferral and the severity split, and is currently
uncited. Record the citation or the empirical result.

0.6 **Verify the bake/apply coherence path (the P0).** Establish whether the delivery
path for this change is covered by a `host_scripts_content_hash` coherence check.
Confirmed this session that it is **not**: `web2-recreate-preflight.sh` has exactly one
call site (`apply-web-platform-infra.yml:1338`) and `grep -n 'Coherence preflight'`
returns exactly one hit — both in the web-2-recreate dispatch job. Decide the AC8
mitigation (reuse vs. sequencing) before writing code.

0.7 Confirm the fleet shape: `variables.tf:109-111` shows `web_hosts` contains **only**
`web-1`, so `web_tunnel_connector` is true for exactly one host.

### Phase 1 — Plumb the expected IP (`server.tf`)

Add `private_ip = each.value.private_ip` to the cloud-init `templatefile` vars map.
Single-sourced from `var.web_hosts` (`variables.tf:110` → `web-1 = 10.0.1.10`), honouring
ADR-115's single-definition doctrine: the value the gate waits on must have exactly one
definition.

### Phase 2 — Bake `soleur-wait-nic` (`soleur-host-bootstrap.sh`)

Bake a **new, separate** `soleur-wait-nic` heredoc alongside the existing
`soleur-wait-ready`. Per D1 it **always exits 0** and emits **exactly one** event from
three mutually-exclusive arms (`private_nic_ready` / `private_nic_timeout` /
`private_nic_probe_fault`). Resolve `IP_BIN` via `command -v ip`; an unresolvable probe
takes the **probe-fault** arm — never the timeout arm (zero evidence ≠ evidence of
absence).

**Leave `soleur-wait-ready` byte-identical** (`soleur-host-bootstrap.sh:307-319`). Its
fail-closed contract, its header comment, and the existing assertions at
`soleur-host-bootstrap-observability.test.sh:145-158` are all untouched — that is the
whole point of the separate-helper choice, and AC6 asserts it as a no-diff check.

**Also add the stub-`ip` extraction harness** (see Test Scenarios) so the three arms are
verified behaviourally rather than by grepping for literals.

### Phase 3 — Wire the call site + measure (`cloud-init.yml`)

3.1 Insert the D2 line.

3.2 **ZERO new comment lines in `cloud-init.yml`.** This is a hard rule for this PR, not
    a style preference. Engineering review measured that a three-line rationale block in
    `cloud-init.yml` costs **40-70 B gzipped** — which alone consumes most or all of the
    78 B headroom, while the *code* costs almost nothing. All rationale goes in
    `soleur-host-bootstrap.sh` (baked → 0 user_data) or `server.tf` (not byte-budgeted).
    `cloud-init.yml` gets at most a one-line pointer, following the #6425/#6594 precedent
    where prose was moved out and only a pointer kept.

3.3 Re-run the size test and record before/after. If over budget, re-baseline
    `WEB_GZIP_BUDGET` following the #6604 precedent: measured before/after, the reason
    baking is unavailable **for this specific line** (it is a `templatefile` interpolation
    of a per-host value, so it cannot move into the baked script), and confirmation the
    KB-scale re-inlining tripwire survives. Note the CI budget is a **drift detector, not
    a physical limit** — ~10.4 KB remains under the hard Hetzner cap, so a modest
    re-baseline is the sanctioned path and is never a boot-failure question.

3.4 **Do not inherit the review's delta figure.** Engineering review measured **+2 B
    gzipped** for adding `SOLEUR_PRIVATE_IP='${private_ip}'` to the bootstrap invocation
    at `cloud-init.yml:566` — but that is the insertion the *drop-in* design needs, **not**
    D2's line. D2 adds a full `runcmd` entry (~95 chars raw). Its true delta is unmeasured
    and MUST be measured directly with the repo's own model
    (`plugins/soleur/test/cloud-init-user-data-size.test.ts`). Review's absolute baseline
    (16,466 B) also does not match this plan's 22,372 B because it gzipped the file
    directly rather than the rendered `templatefile` — **their delta is indicative, their
    absolutes are not comparable.**

3.5 **Entropy caveat:** unlike the sha256 digest experiment recorded at
    `variables.tf:437-441` (a 52 B swing from digest randomness alone), an IPv4 literal
    is low-entropy and gzips well — and `SOLEUR_`/`soleur-wait-ready` already appear on
    nearby lines, so gzip folds much of the addition. Do **not** reason by analogy from
    the digest measurement in either direction — measure this change directly.

### Phase 4 — Tests + ADR reconciliation

4.1 `soleur-host-bootstrap-observability.test.sh` (and/or a sibling suite): assert
    (a) `soleur-wait-nic` is baked; (b) the **rendered** call site carries no `||` and no
    `exit 1`, and renders only when `web_tunnel_connector = true`; (c) the existing
    `cloudflared_ready || exit 1` assertion at `:152` passes unchanged; (d) the shared
    `soleur-wait-ready` heredoc at `:307-319` is **byte-identical** (no-diff check). The
    existing assertion **text** at `:145-148` needs **no** edit — the separate-helper
    design leaves "bounded poll + fatal-on-timeout" true of `soleur-wait-ready`.
4.2 Add the **CF-5 regression guard** across **both** files, heredoc-interior vs
    script-body aware (see AC2).
4.3 ADR-114: add a **new consolidating amendment**. Do **NOT** edit the original
    *"Not shipped in #6416"* sentence — it sits inside preserved *"text as originally
    written"* and editing it corrupts the record the amendment convention protects. The
    amendment reconciles the three existing status statements (original "not shipped";
    2026-07-15 "enforced"; 2026-07-17 "inert on the running fleet") and records what
    this PR ships: a **first-boot** NIC gate, distinct from the already-shipped
    single-connector gate, plus the deferred runtime arm and why. It must also correct the
    stale trade table — post-#6594 the blast radius is total ingress loss, not
    `registry.`-only.
4.4 `.c4` description edits per the C4 section: `model.c4:178`, `:408` (add the
    first-boot gate; correct the stale two-connector claim against `:406`/`:449`), and
    `:406` (attribution framing). Then run `apps/web-platform/test/c4-code-syntax.test.ts`
    and `c4-render.test.ts`.

---

## Acceptance Criteria

### Pre-merge (PR)

> **[Revised at plan-review.]** The first draft carried 17 ACs. Review found three
> structurally unsatisfiable, four asserting proxies rather than invariants, and two
> contradicting the plan's own design sections. The set below is **9**, each asserting
> something the others do not. Cut as redundant or as standing-repo-rules-restated:
> the old AC2 (subsumed by the CF-5 guard), AC5 (restated AC1+AC8), AC12
> (the size test already enforces what matters), AC13 (`boot_id` — moved to its own
> issue), and AC17.

**Idiom note (load-bearing).** Write every check in the suite's established form —
`if grep -qE …; then ok; else no; fi` (`soleur-host-bootstrap-observability.test.sh:152-157`).
Do **not** use `grep -c … == 0`: `grep -c` **exits 1 when the count is zero**, so under
the suite's `set -euo pipefail` it fails on the *passing* case. Confirmed by executing
these commands against the tree during planning. The harness documents the same foot-gun
at `:38-40`.

1. **The gate renders inside the connector block.** Assert against the **rendered**
   output (not raw template line numbers): with `web_tunnel_connector = true`,
   `soleur-wait-nic <private-ip>` appears **immediately before**
   `cloudflared service install`; with `false`, **neither** appears. Rendering is required
   because a raw-file grep passes identically if the line lands *outside* the
   `%{ if ~}` block — which would run a NIC wait on a future non-connector host. See
   Test Scenarios for the render mechanism.

2. **CF-5 regression guard — the single most important AC.** No new `exit 1` reaches an
   aborting path. Scope to **both** files, and distinguish heredoc interior (harmless —
   `soleur-wait-ready`'s own `exit 1` exits the *helper process*) from script body
   (fatal):
   - `cloud-init.yml`: zero added `exit 1` lines.
   - `soleur-host-bootstrap.sh`: zero added `exit 1` **outside** a `<<'…EOF'` heredoc —
     a new `exit 1` in the script *body* aborts runcmd under the `set -e` armed at
     `cloud-init.yml:468` and is equally catastrophic, yet invisible to a
     `cloud-init.yml`-only grep.

3. **The call site has no `||` clause and no `exit 1`.** `soleur-wait-nic` is invoked
   bare. Emission is entirely internal to the helper.

4. **The helper's three arms are behaviourally verified, not grepped.** Extract the
   `soleur-wait-nic` body and execute it against a **stub `ip` on `PATH`**, asserting:
   (a) expected IP present → `private_nic_ready`, exit 0;
   (b) absent through the bound → `private_nic_timeout`, exit 0;
   (c) `ip` unresolvable → `private_nic_probe_fault`, exit 0;
   (d) expected `10.0.1.10`, stub reports only `10.0.1.1` → **no match** (the `grep -qwF`
   substring guard);
   (e) **all three arms exit 0.** This is what makes AC3's no-`||` shape safe.
   Without execution, AC4 degrades to grepping for the literals `command -v` and
   `grep -qwF` — a proxy that asserts strings exist, never that the matcher behaves.

5. **Exactly one event per invocation.** The three stages are mutually exclusive; no
   invocation emits two events, and none emits zero. This is the AC that the first
   draft's `||`-arm design made unsatisfiable.

6. **The shared `soleur-wait-ready` helper is untouched.** Assert as a **no-diff**
   check on `soleur-host-bootstrap.sh:307-319` — the separate-helper design makes this
   mechanically checkable rather than a prose claim, and it protects the existing
   `service`/`port` verbs' fail-closed contract *and* their entry path. The existing
   assertions at `soleur-host-bootstrap-observability.test.sh:145-158` pass unchanged.

7. **The NIC wait bound is pinned**, and pinned *below* `cloudflared_ready`'s budget so
   C3 cannot regress if either number moves. Note the first draft's asymmetry: the
   *deferred* design was given a hard `< 45 s` bound while the *shipping* one had none.

8. **Bake/apply coherence (the P0).** The PR either reuses the existing
   `web2-recreate-preflight.sh` coherence check on the delivery path for this change, or
   asserts the image bake carrying the new `soleur-host-bootstrap.sh` precedes any create
   that would consume the new `host_scripts_content_hash`. Not silence.

9. **No reboot primitive** enters the infra surface (ADR-115 / CF-6). Scope the diff to
   `apps/web-platform/infra/` and **exclude `knowledge-base/`** — this plan's own prose
   and the required ADR-114 amendment both discuss reboots, so an unscoped grep can
   never return 0 and would fail a correct implementation.

**Also required, tracked as PR-body checklist items rather than ACs** (standing repo
rules, not per-change post-conditions): `Ref #6441` and **not** `Closes`/`Fixes` (#6441
also holds the I2 residual and the `WEB_HOST_PRIVATE_IPS` item, both still open); no rule
added to `AGENTS.md`; ADR-114 amendment present with the original *"Not shipped in #6416"*
sentence byte-identical to `origin/main`; `.c4` edits per the C4 section with
`c4-code-syntax.test.ts` + `c4-render.test.ts` passing; the size test passing with
before/after bytes recorded; both deferrals filed as issues.
### Post-merge (operator)

None. The change reaches fresh hosts through `user_data` at create and running hosts
through the baked image on the next deploy; `apply-web-platform-infra.yml` handles the
apply. No operator step is required.

> **Verification note:** the gate is, by construction, only observable on a *fresh host
> boot*. It cannot be exercised by re-running against a running host. Its first real
> exercise is the next `web-1` create/replace — which is why AC6's both-arms emit is
> load-bearing rather than decorative: the emit is the only evidence the gate ran at all.

---

## Observability

```yaml
liveness_signal:
  what: "soleur-boot-emit stage=private_nic_ready (info) — emitted on the success arm of the NIC wait on every fresh connector-host boot"
  cadence: "once per fresh host boot (cloud-init runcmd is once-per-instance)"
  alert_target: "Sentry (the DSN baked into /usr/local/bin/soleur-boot-emit)"
  configured_in: "apps/web-platform/infra/soleur-host-bootstrap.sh (baked emitter); call site apps/web-platform/infra/cloud-init.yml"

error_reporting:
  destination: "Sentry via soleur-boot-emit; stage=private_nic_timeout at level=warning"
  fail_loud: "true — the deferral arm emits a warning row rather than passing silently. The emitter itself is fail-OPEN by design (always returns 0) so a Sentry outage cannot abort a boot; that is deliberate per C1."

failure_modes:
  - mode: "Private NIC never converges within the wait budget; connector registers NIC-less and serves no ingress"
    detection: "stage=private_nic_timeout warning emitted FROM the host itself, at boot, before the connector registers"
    alert_route: "Sentry issue alert `web-host-private-nic-boot-gate` (apps/web-platform/infra/sentry/issue-alerts.tf), filtering stage IN (private_nic_timeout, private_nic_probe_fault). CORRECTED at review: an earlier draft said 'Sentry' unqualified, and at that point NO rule matched these stages — soleur-boot-emit sends one shared message for every stage, so the events raise no new-issue notification on their own either. Emitting without a filter is not a route."
    corroboration: "CORRECTED at review: the web-private-nic-guard.sh signal is NOT 'nic_ok=false within 5 min'. The guard pings its heartbeat ONLY on a healthy run, so a NIC-broken host makes the beat LAPSE — the corroborating signal is a heartbeat lapse at period 360 + grace 120 (~8 min), not a failure beat. It is also second-line: betteruptime_heartbeat.web_nic_guard declares paused = true with ignore_changes = [paused], so its live enablement is not derivable from source. Sentry is the authoritative route; this is confirmation, not detection."
  - mode: "NIC converges but late — connector registration is delayed"
    detection: "stage=private_nic_ready emitted; boot-stage timestamps bound the delay"
    alert_route: "Sentry (info); no page — this is the gate working as designed"
  - mode: "Probe binary unresolvable (ip not on PATH) — gate cannot measure"
    detection: "distinguishable probe-fault stage; MUST NOT be reported as nic-absent"
    alert_route: "Sentry warning. Explicitly modelled after the #6415 cron-PATH defect where an unresolvable probe was read as evidence of absence."
  - mode: "The change itself regresses the boot (the CF-5 class)"
    detection: "CI: the AC3 regression guard (zero added `exit 1`) plus AC8 (pre-existing cloudflared_ready gate unchanged)"
    alert_route: "Blocks merge — caught pre-merge, not in production"

logs:
  where: "Sentry (boot-stage events); journald on-host, shipped by Vector to Better Stack"
  retention: "per existing Sentry + Better Stack retention; no new retention surface"

discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep SOLEUR_PRIVATE_NIC --limit 3
  expected_output: SOLEUR_PRIVATE_NIC
  note: "This probes the CORROBORATING signal (the 5-minute web-private-nic-guard beat on the live web-1), NOT the gate's own emit. The gate is once-per-instance on a fresh boot, so its stage events cannot exist until the next web-1 create — there is no command that can prove the gate fired before it has ever run, and pretending otherwise is what an unverified discoverability_test looks like. Two corrections from review: (a) the guard pings its heartbeat ONLY on a healthy run, so a NIC-broken host makes the beat LAPSE (period 360 + grace 120, ~8 min) — the failure signal is an ABSENCE, not a nic_ok=false line. (b) An earlier draft asserted that zero Sentry events across a window containing a known web-1 create would mean the gate did not run. Unsound: an empty baked DSN silences all three arms identically (soleur-boot-emit exits 0 early when the DSN is empty), as does blocked egress. Zero events is a signal to check the transport FIRST, not a conclusion about the gate."
```

**Affected-surface note (Phase 2.9.2).** A fresh cloud-init boot is a **blind execution
surface**: no SSH, no shell, nothing to inspect while it happens. The probe therefore
emits **from inside** that surface (`soleur-boot-emit` runs in the runcmd shell), and the
two stage values **discriminate the competing hypotheses in one event** — `private_nic_ready`
vs `private_nic_timeout` vs the probe-fault stage separates "NIC came up", "NIC did not
come up", and "we could not tell", which are exactly the three outcomes that would
otherwise be indistinguishable from a silent boot.

### ⚠️ Layer citation + a correlation gap (`hr-observability-layer-citation`)

The two signals covering private-NIC health land on **two different backends and do not
join on a shared key**:

| Signal | Emitter | Backend | Key field |
|---|---|---|---|
| `private_nic_ready` / `private_nic_timeout` (this plan) | `soleur-boot-emit` → `POST /api/$PROJ/store/` | **Sentry** | `host_id` = cloud-init **instance-id** |
| `SOLEUR_PRIVATE_NIC nic_ok=…` (existing, every 5 min) | `web-private-nic-guard.sh` | **Better Stack Logs** | `boot_id` |

These are the *same fact* on two backends with **no shared join key today**. The plan
must resolve this rather than leave it to an incident:

- **Authoritative for alerting: Sentry**, via this plan's boot-stage emit. It is the only
  signal that fires *at the decision point*, before the connector registers. The Better
  Stack beat is **corroboration** — it confirms the steady state 5 minutes later but
  cannot observe the boot-time race at all.
- **Correlation:** joined on the **host**. `host_id` (the cloud-init instance-id) uniquely
  identifies the host, and this gate's event fires **exactly once per instance**, so
  host-level correlation is sufficient here.

> **[Revised at plan-review — a `boot_id` tag was proposed and is now cut.]** The first
> draft proposed adding `boot_id` as a Sentry tag "for free." That was **wrong on cost and
> thin on value**: `soleur-boot-emit` builds its tag block **once**
> (`soleur-host-bootstrap.sh:285`, `"tags":{"stage":…,"host_id":…,"region":…}`), so there
> is no per-arm tagging — adding `boot_id` changes the tag shape of **every boot-stage
> event on every host**, via a shared fail-open emitter, inside a PR about a NIC wait. And
> the join it buys is marginal: `boot_id` discriminates *reboots of the same host*, which
> is irrelevant for a once-per-instance runcmd gate that `host_id` already pins.
> **Out of scope — filed as its own issue against the emitter.**

Recorded because a two-backend split is the shape that turns a 15-minute diagnosis into a
multi-hour one on a blind surface — but the fix belongs to the emitter, not to this gate.

---

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/server.tf` — one added key (`private_ip`) in the existing
  cloud-init `templatefile` vars map. No new resource, no new provider, no new variable,
  **no new secret**. The value is already in `var.web_hosts`.
- No `TF_VAR_*` addition ⇒ no Doppler provisioning ⇒ no operator mint ⇒ the
  "no-default variable on an auto-applied root" hazard does not apply.

### Apply path

**(a) cloud-init-only, plus the standard image bake.** Two delivery channels, both
already existing:

- The `cloud-init.yml` line reaches a host **only at create** (`user_data`). Existing
  hosts are unaffected until replaced — correct and intended, since the gate is a
  *first-boot* gate.
- The `soleur-host-bootstrap.sh` change reaches running hosts via the baked app image on
  the next deploy (#5921 bake-and-extract).

`server.tf` carries `lifecycle.ignore_changes` on `user_data` for the web host, so this
change does **not** arm a pending replace of `web-1`. Blast radius: zero downtime, no
force-replace. Expected downtime: **none**.

### ⚠️ P0 — the two channels are NOT independent: bake/apply skew aborts the boot

> **[Added at plan-review. The first draft described these as two independent routes with
> "zero downtime". That was wrong, and the failure it misses is a full CF-5.]**

`soleur-host-bootstrap.sh` is a member of `local.host_script_files`, which feeds
`local.host_scripts_content_hash` (`server.tf:95-97`), which is injected into `user_data`
(`server.tf:182`) and **recomputed and compared at boot**:

```
cloud-init.yml:559   [ "$GOT" = "$HOST_SCRIPTS_HASH" ] || exit 1
```

That `exit 1` runs under the `set -e` armed at `cloud-init.yml:468` — **before** the
`set +e` at `:568`. And `var.image_name` defaults to a **moving tag**,
`ghcr.io/jikig-ai/soleur-web-platform:latest` (`variables.tf:66-70`).

**Consequence:** editing `soleur-host-bootstrap.sh` changes the hash. A `web-1` created
after the terraform apply but **before** `:latest` carries the matching bootstrap aborts
its **entire runcmd** at `stage=verify` — no cloudflared, no webhook, no monitors, no
egress firewall. This is the exact catastrophe the plan exists to prevent, arriving
through the delivery channel rather than the code.

**This is not hypothetical — it has already happened.** The workflow carries a
*"Coherence preflight (LOAD-BEARING — abort before -replace on mismatch)"* step
(`apply-web-platform-infra.yml:1324-1338`) whose own comment says a stale pin would
*"RE-ABORT at cloud-init stage=verify (**the exact bug**)"*.

**But that guard covers ONE path only.** Verified this session:
`apps/web-platform/infra/scripts/web2-recreate-preflight.sh` is invoked from exactly one
call site (`apply-web-platform-infra.yml:1338`, the web-2-recreate dispatch job), and
`grep -n 'Coherence preflight'` returns exactly one hit. **Neither the routine merge
apply nor any fresh `web-1` create is covered** — and that is precisely the path this
plan targets. That job also pins a resolved digest (`-var="image_name=${PINNED}"`), while
the routine path inherits the `:latest` default.

**Required in this PR (AC-backed):** the PR must either
(a) reuse the existing `web2-recreate-preflight.sh` coherence check on the path that
delivers this change, or
(b) sequence the merge so the image bake carrying the new `soleur-host-bootstrap.sh`
lands **before** any create can consume the new `host_scripts_content_hash`, with the
ordering asserted rather than assumed.

Silence here is not acceptable: this plan is the first to edit
`soleur-host-bootstrap.sh` since that guard was added for the sibling path.

### Distinctness / drift safeguards

- `dev != prd`: not applicable — this is a prd-only host class.
- `lifecycle.ignore_changes = [user_data]` on `hcloud_server.web` means the edit is inert
  for the running `web-1` and applies at next create. This is called out because it is a
  *feature* here but would be a trap if the gate were expected to fix a running host.
- No secret value enters `terraform.tfstate` as a result of this change (an RFC1918
  address is not sensitive and is already in `variables.tf` in plaintext).

### Vendor-tier reality check

Not applicable — no vendor resource is created. Cloudflare tunnel, Hetzner network and
Sentry are all pre-existing and unchanged in shape.

---

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-114** (do not create a new ADR — this enforces an existing recorded decision
rather than making a new one). Add a **consolidating amendment** that:

1. Reconciles I1's three inconsistent status statements (original *"Not shipped in
   #6416"*; the 2026-07-15 #6425 amendment declaring I1 **enforced**; the 2026-07-17
   #6594 amendment saying it is **inert on the running fleet**).
2. Records what this PR ships: a **runtime, first-boot** NIC gate — distinct from, and
   complementary to, the already-shipped single-connector gate.
3. Corrects the stale blast-radius claim: post-#6594 all three ingress services are
   private-IP-relative, so a NIC-less connector serves **nothing**, not `registry.` alone.
4. Records the explicitly deferred half (restart/reboot coverage via `ExecStartPre`) and
   **why** — the C3 budget interaction with `cloudflared_ready`.

**Do NOT edit** the preserved original text. Amendments append.

**ADR-115** is **not** amended: this plan introduces no reboot, so ADR-115's
registry-scoped grant is untouched. It is cited as a binding constraint (C2), not changed.

### C4 views

All three model files (`model.c4`, `views.c4`, `spec.c4`) were read in full — not
grepped. Enumeration below.

**No new element, relationship, or `view … include` line is required.** Justification by
category:

| Category | Finding |
|---|---|
| **(a) External human actors** | `founder` (`model.c4:8`) is the only human on this path. Both alerting exits already exist: `sentry -> founder` (`:493`), `betterstack -> founder` (`:498`). No new actor. |
| **(b) External systems / vendors** | Cloudflare **modelled twice** — system `cloudflare` (`:234`) and container `tunnel` (`:176`). Sentry `:290` (with the boot-emit edge `hetzner -> sentry` `:490`), Better Stack `:283`, zot `:262`, GHCR `:258` — all modelled. Hetzner is modelled as an owned container `hetzner` (`:180`), not an `#external` vendor. |
| **(c) Containers / data stores** | web host `hetzner` `:180`; cloudflared connector = the `tunnel` container `:176`; zot host `:262`; inngest `:188`. All four are in the L2 view include list (`views.c4:32-33`). |
| **(d) Access relationships** | The relationship whose *timing* this gate constrains — `hetzner -> tunnel` (`:408`, the connector-registration edge) — **already exists**, as do `tunnel -> hetzner` (`:401`) and `tunnel -> zotRegistry` (`:406`). |

**Determination:** a boot-ordering gate adds no participant, no data flow, and no trust
boundary — it sequences an already-modelled edge. C4 models *who talks to whom over what*,
not *in what order services start*. That is below C4 granularity; the correct home is
ADR-114 §I1.

**One modelled gap, deliberately not taken here:** the Hetzner **private network**
(`10.0.1.0/24`) has **no element** — it appears only as free text in `technology`/
`description` strings (`:189`, `:401`, `:406`). This is the fourth issue to reference it
(#6415, #6438 §3, #6400, now #6441). Promoting it to an element is a defensible
standalone modelling change but is **not required** by this change, and doing it here
would couple an ordering fix to a model refactor. Not in scope.

### C4 description corrections (in scope — these become misleading)

Three `.c4` description strings are falsified or made misleading by this change, plus one
pre-existing contradiction that is cheap to fix in the same pass:

1. **`model.c4:178` (`tunnel` description)** — currently: *"I1 is a construction-time gate
   presented as a runtime precondition — it governs only future fresh hosts."* Under this
   plan's delivery mechanism (`user_data` at create, with `ignore_changes = [user_data]`
   on the running host) **this sentence remains TRUE**, and that is not an accident — it
   is why D4 defers the runtime arm. Add a pointer to the first-boot gate; do **not**
   claim runtime enforcement.
2. **`model.c4:408` (`hetzner -> tunnel`)** — restates the same claim at the edge level and
   says nothing about NIC preconditions. **Misleading by omission** after this change,
   since this edge is where a reader looks for "what governs connector registration."
3. ~~**`model.c4:406`** — attribution reframing.~~ **Cut at plan-review.** The plan's own
   assessment was *"still true, but…"* — rewriting a true sentence to be more generous
   about credit is prose polish, not a correctness fix. Out of scope. (`:406` is still
   *read* as the adjudicating evidence for item 4 below; it is not edited.)
4. **Pre-existing contradiction (not caused by this change, fixed opportunistically):**
   `:178` and `:408` both assert **two connectors are live in prod (web-1 + web-2)**,
   while `:406` and `betterstack -> hetzner` (`:449`) both say web-2 was **retired
   2026-07-17 (#6538/#6463)** and the fleet is single-host.

   **Adjudicated against Terraform source this session, not just the model's own text:**
   `variables.tf:109-111` shows `web_hosts` default containing **only** `"web-1"`, with a
   standing comment *"Do NOT re-add a key here to restore standby: see ADR-068's
   amendment."* The fleet **is** single-host; `:178` and `:408` are stale. Since Phase 4
   edits both strings anyway, correct the two-connector claim in the same pass rather than
   leaving the model self-contradictory for the next reader.

**Not affected:** `hetzner -> betterstack` (`:448`, the NIC guard) stays accurate — it
describes detect+emit+alarm *remediation*; this gate is *prevention*. Different mechanism,
different lifecycle phase, no contradiction. `hetzner -> sentry` (`:490`) also stays true.

After editing, run the C4 validation suites (`apps/web-platform/test/c4-code-syntax.test.ts`
and `c4-render.test.ts`) — a `view include` referencing an undefined element fails there,
not at `tsc`.

---

## Domain Review

**Domains relevant:** Engineering (CTO)

*(Product/UX Gate: skipped. The mechanical UI-surface override does not fire — no path in
`Files to Edit` matches `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`.
No user-facing surface is created or modified; this is an infrastructure boot-ordering
change. Legal, Finance, Marketing, Sales, Support, Operations: no implications — no new
vendor, no new cost, no data-processing change.)*

### Engineering (CTO)

**Status:** reviewed.

**Assessment.** The framing and the all-three-ingress-private measurement were confirmed
independently at `tunnel.tf:54,:71,:107`. Six findings, all folded into the plan above:

1. **BLOCKING (now resolved by design choice).** Review independently reproduced the C3
   collision and rated the `ExecStartPre` shape **high CF-5 risk as written** — including
   a path where the unit exceeds systemd's 90 s `TimeoutStartSec`, enters `failed`,
   `Restart=on-failure` re-arms, and `soleur-wait-ready` lands *inside a restart loop*,
   detonating `|| exit 1`. The chosen D2 shape (wait **before** the install) removes the
   interaction entirely. Risk: **high → low**.
2. **cloudflared resolves ingress origin per connection, not at process start** — so a
   NIC-less connector **self-heals when the NIC attaches**. This makes exit-0-on-timeout a
   *safety property* rather than a UX trade, and materially weakens the case for the
   deferred runtime arm. Folded into D4.
3. **A `nic` verb would invert `soleur-wait-ready`'s fail-closed contract.** Originally
   folded as D1a (own hardcoded-soft branch + header/test-text updates). **Superseded at
   plan-review** by the stronger fix: a *separate* `soleur-wait-nic` helper, leaving the
   shared one byte-identical. See D1.
4. **Comments are the real budget hazard**, not code (40-70 B for a 3-line block vs ~2 B
   for the code). Folded as Phase 3.2 as a hard zero-new-comments rule.
5. **Observability layer split with no join key** between Sentry and Better Stack. Folded
   into the Observability section with `boot_id` as the proposed shared key.
6. **Do not source `EXPECTED_IP` from `/etc/default/web-private-nic-guard`** — it is
   web-1-only, provisioner-delivered, and not ordered before cloud-init; reusing it
   "would work on web-1 today and fail silently on any future host — the worst failure
   shape." This independently confirms the Research Reconciliation row.

**Dissent recorded (taste, not mechanical).** Review's own preference is that the
`ExecStartPre` drop-in *is* the better long-term call, since ADR-114 §I1 is deliberately
written as a runtime precondition — while agreeing the inline verb is "a clean fallback,
not a regression," and that both can coexist. This plan takes the inline shape for **this
PR** on safety grounds (finding 1) and defers the drop-in with explicit safety
requirements. Surfaced here rather than silently applied.

**Complexity:** small-to-medium (hours), dominated by tests rather than code.

---

## Open Code-Review Overlap

Checked all `Files to Edit` paths against open `code-review`-labelled issues.

- `#2197` (*refactor(billing): SubscriptionStatus type + hoist single-instance throttle
  doc + Sentry breadcrumb UUID policy*) matched on `apps/web-platform/infra/server.tf`.
  **Disposition: Acknowledge.** The match is incidental — a billing/Sentry-policy concern
  that shares no region with the `templatefile` vars map. Different concern, needs its own
  cycle; the scope-out remains open.
- `cloud-init.yml`, `soleur-host-bootstrap.sh`, `cloud-init-user-data-size.test.ts`: no
  matches.

---

## Security Review (deepen-plan)

**Verdict: security-neutral. No P0, no P1 introduced by this change.** Findings that
change the plan's text:

- **Inbound exposure — unchanged.** `firewall.tf:1-89` allows only tcp/22 from
  `var.admin_ips`, tcp/80+443 from Cloudflare edge ranges, and ICMP. cloudflared is an
  **outbound dialer** needing no inbound port, so delaying it opens nothing. The only
  wildcard bind (webhook `-ip 0.0.0.0 -port 9000`, `cloud-init.yml:245`) installs at
  `:604-615` — **after** the insertion point, so the wait pushes it later, not earlier,
  and :9000 is not in the allow-list regardless.
- **`private_ip` in `user_data` — non-finding.** `user_data` already carries
  `tunnel_token`, `doppler_token`, `webhook_deploy_secret`, `sentry_dsn`,
  `ghcr_read_token`. An RFC1918 literal is strictly dominated, and the value is already
  plaintext in `variables.tf:110` and in `tunnel.tf`'s ingress rules.
- **Argument injection — closed by an existing validation.** `variables.tf`'s
  `can(regex("^10\\.0\\.1\\.[0-9]{1,3}$", h.private_ip))` means no shell metacharacter can
  reach `grep -qwF -- "$1"`.
- **PATH hijack — closed by the content hash.** `/usr/local/bin` does precede `/usr/sbin`,
  so `command -v ip` could in principle resolve a planted binary — but `/usr/local/bin` is
  populated only by the hash-verified extraction, and the hash is checked at
  `cloud-init.yml:559` **before any baked code executes**. Planting requires repo write
  access or a sha256 preimage.
- **Egress-firewall ordering — net-zero.** `cron-egress-firewall.service` enables at
  `:632`, so a ≤60 s wait does push it ≤60 s later. But the subject it constrains — the
  app container — starts later still (terminal block `docker run`, after the plugin seed),
  so the extended window **contains no container**. This resolves the concern raised
  during planning.
- **Secret-in-log — none.** `soleur-boot-emit` builds a fixed payload (`message`, `level`,
  tags `stage`/`host_id`/`region`); stage values are literals and the IP is never passed
  to the emitter.

### ⚠️ Correction: this path is NOT digest-pinned, and that is fine

The framing inherited into this work says *"the digest pin gives integrity, never
provenance."* **On this path there is no digest pin at all** — `var.image_name` defaults
to `ghcr.io/jikig-ai/soleur-web-platform:latest` (`variables.tf:66-70`), a **mutable tag**.

The correction matters in the *reassuring* direction: **the integrity control covering the
new helper is not the image reference.** It is `host_scripts_content_hash`
(`server.tf:95-97` → injected `:182` → verified `cloud-init.yml:559`), which binds the
extracted scripts to the **repo files** — strictly stronger than either a tag or a digest
for this purpose, and it covers `soleur-wait-nic` automatically via
`local.host_script_files`.

**So adding a baked helper does not increase reliance on the unsigned image.** It
increases coupling to bake/apply **sequencing** — which is exactly the P0 above. The
"integrity, never provenance" wording elsewhere in this plan is accurate and correctly
scoped; no provenance work is proposed (out of scope by explicit decision).

### Adjacent pre-existing observations (NOT in scope — recorded so reviewers see them)

- **The firewall attach has the SAME construction-order race as the NIC.**
  `hcloud_firewall_attachment.web` depends on `hcloud_server.web[].id`
  (`firewall.tf:91-93`) — the identical "attach cannot precede create" fact this plan
  builds its whole argument on for `hcloud_server_network`. There is therefore a
  fresh-create window where the host boots before the firewall attaches. **This change
  does not move that window** (it lives entirely inside `runcmd`), but the symmetry is
  striking and nobody has written it down. Worth a separate look at what is reachable
  during it; not verified here, so this is a flag to check, not an asserted exposure.
- **`cloudflared service install ${tunnel_token}` puts the token in argv**
  (`cloud-init.yml:598`) — visible in `/proc/<pid>/cmdline` and echoed to
  `/var/log/cloud-init-output.log`. Pre-existing, and the repo already mitigates the same
  hazard in the terminal block (*"Source token from the restricted env file (avoids
  exposing it in /proc/<pid>/cmdline)"*). Out of scope, but the new line lands directly
  above it, so reviewers will read this region.

## Precedent Diff (deepen-plan Phase 4.4)

`soleur-wait-nic` is a pattern-bound behaviour (bounded poll + NIC probe + boot-stage
emit). Repo precedents were enumerated and diffed; the design above was **revised to
conform** on three axes, and **one deliberate divergence** is documented.

| Axis | House precedent | This plan | Verdict |
|---|---|---|---|
| **Loop shape / bound** | `for i in $(seq 1 30); do … sleep 2; done` — **30 × 2 s = 60 s**, used 6+ times verbatim (`web-private-nic-guard.sh:48-51`, `cloud-init-registry.yml:479-482,660,753,777-781`, `cloud-init.yml:472`). `cloud-init-registry.yml:475` calls it *"the same shape as the volume device-wait"* — the style is self-aware. | **Conformed.** First draft used the `while :; n=$((n+1))` form, which is Shape B — the *fail-closed* variant used exactly once (`soleur-wait-ready`). Revised to Shape A. | ✅ conforms |
| **Probe resolution** | `IP_BIN=$(command -v ip 2>/dev/null \|\| true)` then `PROBE_OK=true; [ -n "$IP_BIN" ] && [ -x "$IP_BIN" ] \|\| PROBE_OK=false` (`web-private-nic-guard.sh:38-39`, `cloud-init-registry.yml:467-468`). **Never** `command -v ip` inline in the predicate. Probe-fault **short-circuits before the loop** (`web-private-nic-guard.sh:47`). | **Conformed.** First draft inlined `command -v` and did not explicitly short-circuit. Revised to the `IP_BIN`/`PROBE_OK` pair with an early `exit 0`. | ✅ conforms |
| **Match flags** | `"$IP_BIN" -4 -o addr show 2>/dev/null \| grep -qwF -- "$EXPECTED_IP"` — `-w`/`-F`/`--` all load-bearing and commented at `web-private-nic-guard.sh:40-42`. | Identical. | ✅ conforms |
| **Stage naming** | snake_case, domain-prefixed (`workspaces_mount`, `inngest_ghcr_fallback`, `cloud_init_complete`). Hyphens **never** appear in a stage name — the guards' hyphenated `converged_by=probe-fault` is a *Better Stack log field*, not a Sentry stage. | `private_nic_ready` / `private_nic_timeout` / `private_nic_probe_fault`. | ✅ conforms |
| **`warning` level** | Exactly **one** precedent: `inngest_ghcr_fallback` (`cloud-init.yml:705`) — a *measured* degraded path. | Two of our three arms use `warning`, one of which (`probe_fault`) is an **unmeasurable** state. | ⚠️ thin precedent — acceptable, noted |
| **"Could not measure" stage** | **Novel — no precedent.** No existing Sentry stage encodes instrument failure; the concept lives only in the guards' Better Stack `converged_by=probe-fault` field and has never been promoted to a stage. | `private_nic_probe_fault` is the first. | ⚠️ **novel — flag for reviewer scrutiny** |
| **Always-exit-0 baked helper** | Precedented: 2 of 4 helpers `soleur-host-bootstrap.sh` authors are fail-open (`soleur-boot-emit:279-300`, `soleur-vector-install:350-449`); 2 are fail-closed (`soleur-wait-ready:307-320`, `soleur-luks-structural-gate:461-491`). House rule: **serving-critical invariants fail closed; observability / best-effort convergence fails open.** | Fail-open. | ⚠️ **deliberate divergence — see below** |
| **Heredoc authoring guard** | Each helper heredoc is preceded by `STAGE=…; FAILED_FILE=…` so a *write* miss emits a named stage under the top-level `emit_fail` trap (`:278`, `:349`, `:460`). | Must carry its own pair. *(`soleur-wait-ready:307` lacks one and inherits `STAGE=boot_emit` — an existing gap, not a pattern to copy.)* | ✅ conform — add the pair |

### The one deliberate divergence

`soleur-wait-nic` is fail-**open** while its **nearest functional sibling**,
`soleur-wait-ready`, is fail-**closed** — and they gate the *same* `cloudflared` step,
five lines apart. That asymmetry is intentional and is the plan's central thesis, but it
will read as an inconsistency to any reviewer who does not know why:

- `soleur-wait-ready cloudflared` runs **after** the unit exists. A never-ready cloudflared
  is a *terminal* condition, and its `|| exit 1` is a pre-existing (separately contested)
  choice.
- `soleur-wait-nic` runs **before** the unit exists, on a condition that **provably
  self-heals** — cloudflared dials origins per connection (confirmed below), so a late NIC
  needs no restart. Aborting here would destroy a recovery channel to prevent a condition
  that resolves itself.

**Action:** state this rationale in a comment **inside `soleur-host-bootstrap.sh`** (baked,
0 user_data) — not in `cloud-init.yml`, per the zero-new-comments budget rule.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The fix causes the outage it prevents (CF-5).** An `\|\| exit 1` slips into the runcmd path. | D2 omits it by construction; AC2 + AC3 assert it mechanically on the diff. This is the single most important AC in the plan. |
| **C3: the NIC wait eats `cloudflared_ready`'s 60 s budget** and trips its pre-existing `\|\| exit 1`. | The wait is placed *before* `cloudflared service install`, making the budgets sequential rather than nested. AC5 pins the ordering; AC8 pins the downstream gate unchanged. `ExecStartPre` is deferred precisely because it cannot satisfy this. |
| **Budget overrun** — the added line pushes user_data past `WEB_GZIP_BUDGET`. | Phase 3.2 re-measures; a #6604-style modest re-baseline is the sanctioned path. 10,396 B remain under the *hard* Hetzner cap, so this is a CI-ratchet question, never a boot-failure one. |
| **Wrong expected IP** → the gate waits forever on an address that will never appear. | Single-sourced from `var.web_hosts` (ADR-115's single-definition doctrine). Bounded budget means "forever" is ≤ the budget, and the deferral arm continues the boot. Unlike the registry guard, a wrong IP here cannot cause a reboot — only a delay plus a warning row. |
| **Probe-fault read as NIC-absent** (the #6415 cron-PATH defect). | `command -v ip` resolution + a distinguishable probe-fault stage. Zero evidence ≠ evidence of absence. |
| **Substring match** — `10.0.1.1` matching inside `10.0.1.10`. | `grep -qwF` (exact word, fixed string), mirroring `web-private-nic-guard.sh:44`. AC4. |
| **Silent success** — the gate ships but never actually runs. | Both arms emit (AC6). Because the surface is blind and once-per-instance, an emit that never fires is the only detectable signal of a dead gate. |
| **Delay compounds into a slower boot** on every fresh host. | The wait is bounded and only runs on the connector host (`web_tunnel_connector`), i.e. `web-1` only — and `variables.tf:109-111` shows the fleet is single-host. In the healthy case the NIC is present within seconds and the wait returns on its first iteration. |
| **`soleur-wait-ready` does not exist** because bake-and-extract failed, so the new call is `command not found`. | **Already handled upstream; this change does not alter it.** Bootstrap runs at `cloud-init.yml:566` under a trap (`:561`); the fail-closed sentinel `/run/soleur-hostscripts.ok` drives `poweroff -f` at `:754`. And the pre-existing `cloudflared_ready \|\| exit 1` at `:601` already aborts on a missing binary (exit 127). The new line at `:597` fails soft (`set +e` in scope) and falls through to those existing gates — it neither rescues nor worsens that path. |

---

## Alternative Approaches Considered

| Alternative | Verdict |
|---|---|
| **`soleur-wait-ready nic … \|\| exit 1` in `runcmd`** (the original B2, and what the learnings-research pass independently recommended) | **Rejected — CF-5.** Converts a partial, diagnosable, in-band-fixable degradation into total unrecoverable loss. `runcmd` is once-per-instance, so even a NIC that converges later never gets cloudflared installed. Strictly worse than shipping nothing. |
| **Mirror the registry host's self-converging reboot** (the original B3) | **Rejected — CF-6 / ADR-115.** ADR-115's reboot grant is registry-scoped by explicit normative blocker; `web-1` is the sole live origin. `web-private-nic-guard.sh` already deliberately omits exactly this half. A web-host converge is an ADR-115 amendment + CPO decision, not a bug-fix detail. |
| **`ExecStartPre` on `cloudflared.service` (no runcmd change)** | **Rejected for now (revised at plan-review from "deferred").** Three grounds: (i) per C3 it consumes `cloudflared_ready`'s budget and can trigger a CF-5 abort — engineering review rated it **high CF-5 risk as written**; (ii) making it safe requires re-tuning a fail-closed gate pinned by an exact-string test; (iii) its value is small because a NIC-less connector **self-heals per-connection** (D4 finding 2) and the runtime case is already covered by `web-private-nic-guard.timer`. Grounds (iii) is why this is a rejection rather than a tracked deferral — the plan cannot call the state "converging" and still hold an open item to fix it. **Dissent recorded:** engineering review considers the drop-in the better long-term shape, since ADR-114 §I1 is deliberately written as a runtime precondition. **Revival condition:** evidence that (iii) is false, or an owner for the `cloudflared_ready` budget. If revived, the `-` prefix, the `<45 s` bound and the `TimeoutStartSec` pin in D4 are mandatory. |
| **Fix the race in Terraform** (order the attach before the token) | **Impossible by construction** — ADR-114 §I1 and ADR-115 Context both record it. `hcloud_server_network` is an additive online attach requiring a *created* server, and a created server is already booting. |
| **Raise `WEB_GZIP_BUDGET` generously to buy room** | **Rejected.** The budget's purpose is a KB-scale re-inlining tripwire. Any raise must be *modest* and justified with measured before/after (#6425/#6594/#6604 precedent). Baking is preferred — which is why D1 puts the entire poll body in the baked script and leaves only one interpolated line inline. |
| **Gate on "any RFC1918 address" instead of the exact IP** | **Rejected.** Weaker invariant, and it contradicts ADR-115's doctrine of corroborating on the *expected address* rather than a bare network count — a drifted expectation would otherwise be satisfied by an unrelated attach. |

---

## Deferred

> **[Revised at plan-review — one deferral became a rejection, one was added.]** Review
> made a correct consistency argument: the plan cannot simultaneously hold that a
> NIC-less connector is *"a converging state, not a stuck one"* and that the runtime
> `web-2` case is *"already covered by `web-private-nic-guard.timer`"*, **and** file a
> standing open item to build the `ExecStartPre` arm anyway. Those premises entail that
> the arm is not needed. It is therefore moved to **Alternative Approaches — deferred and
> not tracked as an open item** rather than a deferral with an issue.

Requires a tracking issue filed **in the same PR** (a deferral without a tracking issue is
invisible):

1. **The pre-existing `cloudflared_ready || exit 1` at `cloud-init.yml:601`** — a live
   CF-5 hazard predating this plan, currently *pinned* by
   `soleur-host-bootstrap-observability.test.sh:152`. Re-evaluation criteria: decide
   whether a never-ready cloudflared should abort the boot at all, given that the abort
   also kills the webhook, monitors and egress firewall that would otherwise make the
   host diagnosable. Milestone: Post-MVP / Later.
2. **`boot_id` on the shared `soleur-boot-emit` tag block** — cut from this PR because the
   tag set is built once at `soleur-host-bootstrap.sh:285` and changing it alters **every**
   boot-stage event on **every** host via a shared fail-open emitter. Re-evaluation
   criteria: bundle with the next change that already touches the emitter, and reconcile
   with the emit/QUERY lockstep pinned at
   `soleur-host-bootstrap-observability.test.sh:208-232`. Milestone: Post-MVP / Later.
3. **A coherence preflight for the routine apply / fresh-create paths** — if the P0 is
   resolved in this PR by sequencing rather than by reusing
   `web2-recreate-preflight.sh`, the *structural* gap (only the web-2-recreate job carries
   the guard) remains and must be tracked. Milestone: Post-MVP / Later.

**Not deferred — rejected:** the `ExecStartPre` runtime arm. See Alternative Approaches.
Reviewer dissent is recorded there: engineering review considers it the better long-term
shape, on the grounds that ADR-114 §I1 is deliberately written as a runtime precondition.
Surfaced rather than silently resolved.

---

## Test Scenarios

Runner: `.test.sh` suites under the existing `apps/web-platform/infra/*.test.sh`
convention, plus `bun test` for the TypeScript size guard. No new test framework.

> **⚠️ [Added at plan-review — the first draft's tests were unrunnable.]** The existing
> harness is **grep-only over raw file text**
> (`soleur-host-bootstrap-observability.test.sh:31-32,40`). It **never renders** the
> `templatefile`, so `%{ if ~}` directives stay literal; and the helper exists only as
> heredoc text, so nothing executes it. As first written, the render tests and the
> behavioural tests were both **unimplementable**, which silently degraded AC1 and AC4 to
> string-presence proxies. Two small additions fix this and are **in scope**:
>
> - **A render step.** Produce the rendered cloud-init for both
>   `web_tunnel_connector` values — via `terraform console`'s `templatefile(...)` under
>   the canonical Doppler `tf-var` invocation (the same single-source pattern
>   `apply-web-platform-infra.yml:1334-1336` already uses for
>   `local.host_scripts_content_hash`), or an equivalent minimal renderer. Without it,
>   "inside the `%{ if }` block" is unassertable.
> - **A heredoc-extraction harness.** Extract the `soleur-wait-nic` body to a temp file
>   and execute it with a **stub `ip` earlier on `PATH`**. This converts AC4 from a
>   literal-grep proxy into a real behavioural post-condition, and costs a few lines.

1. **Render — connector host.** With `web_tunnel_connector = true`, the **rendered**
   output has `soleur-wait-nic <ip>` immediately before `cloudflared service install`.
2. **Render — non-connector host.** With `false`, **neither** renders.
3. **Behaviour — ready arm.** Stub `ip` reports the expected IP → `private_nic_ready`,
   exit 0, no `private_nic_timeout`.
4. **Behaviour — timeout arm.** Stub never reports it → `private_nic_timeout` after the
   bound, exit 0, no `private_nic_ready`.
5. **Behaviour — probe-fault arm.** `ip` unresolvable → `private_nic_probe_fault`,
   exit 0, and **not** `private_nic_timeout` (the #6415 mislabel this plan must not
   reproduce).
6. **Behaviour — substring guard.** Expected `10.0.1.10`, stub reports only `10.0.1.1` →
   no match (`grep -qwF`).
7. **Behaviour — exactly one event.** Each of tests 3-5 emits exactly one event.
8. **Negative — no `||`, no `exit 1`** at the call site.
9. **Negative — CF-5 guard** across both files, heredoc-interior vs script-body aware.
10. **Negative — no reboot** primitive in `apps/web-platform/infra/`.
11. **Unchanged shared helper.** `soleur-host-bootstrap.sh:307-319` is byte-identical;
    the existing assertions at `soleur-host-bootstrap-observability.test.sh:145-158` pass.
12. **Size.** `cloud-init-user-data-size.test.ts` passes; measured delta recorded.

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Filled
  above with a concrete artifact and vector.
- **The 78 B headroom figure is a timestamped measurement, not a constant.** It has moved
  at least twice (`761243954`'s absolutes no longer reproduce). Re-derive with
  `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` before depending on it.
  Do not reason by analogy from the sha256-pin experiment: that measurement's 52 B swing
  came from *digest entropy*, and an IPv4 literal compresses very differently.
- **`soleur-wait-ready`'s own `exit 1` is not the hazard.** It exits the *helper process*.
  Only the **caller's** `|| exit 1` in `runcmd` aborts the boot. Reviewers reading the
  helper in isolation reliably misread this — the hazard is at the call site.
- **`web-private-nic-guard.sh`'s `EXPECTED_IP` is unavailable on the path this gate runs
  on.** It arrives via an SSH provisioner (`server.tf:479`) that reaches running hosts
  only; on a fresh boot `/etc/default/web-private-nic-guard` does not yet exist. Any
  design that "reuses the guard's config" is wrong for the fresh-host case.
- **There is NO `cosign verify` on this path.** The bootstrap image is unsigned by design;
  the digest pin gives integrity, never provenance. Do not add a provenance claim (CF-2).
- **Do not gate anything on the terraform drift signal (#6443)** — it always alarms.
- **The zot soak's veto behaviour is correct.** Leave it.
- **PR body must use `Ref #6441`, never `Closes`/`Fixes`.** The squash-merge reads commit
  bodies and would auto-close work that is still open (#6441 also holds the I2 residual
  and the `WEB_HOST_PRIVATE_IPS` single-sourcing item).
- **Do not add rules to `AGENTS.md`** in this PR — it is over its 22k CRITICAL threshold.
- **`grep -c` exits 1 when the count is zero** — even though it correctly prints `0`.
  Every AC in this plan of the form "`grep -c … == 0`" will therefore **abort a `set -e`
  verification script on the passing case**. This was confirmed by executing the AC
  commands against the current tree during planning: each printed `0` and returned exit 1.
  Append `|| true` (or capture into a variable and compare) in every such AC. Do not
  discover this at AC-check time.
- **Diff-scoped ACs must exclude `knowledge-base/`.** This plan's own prose contains the
  words `reboot`, `exit 1`, and `#` comment markers many times. An AC that greps
  `git diff origin/main` unscoped will match the plan file itself and **fail on a correct
  implementation**. AC9 was caught and re-scoped to `apps/web-platform/infra/` during
  planning; apply the same scoping to any AC added later.
