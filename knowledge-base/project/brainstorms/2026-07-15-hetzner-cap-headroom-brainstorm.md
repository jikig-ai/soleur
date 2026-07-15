---
date: 2026-07-15
topic: hetzner-cap-headroom
issue: 6453
pr: 6457
branch: feat-hetzner-cap-headroom
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm — Hetzner server-cap headroom (#6453)

## What We're Building

Headroom in the Hetzner fleet so that destroy-shaped remediations and scratch
diagnostics stop being impossible, plus the guards that make the constraint
loud instead of silent.

Four workstreams, in dependency order:

1. **Reclaim `hermes-agent`** (snapshot → destroy → inventory offline). Frees one
   slot today with **zero vendor dependency**. Critical path.
2. **Reconcile the phantom ledger rows + the dead `git-data-host-replace` path.**
   Not in the issue's original four — surfaced here. Small, and it stops an ADR
   corpus growing on top of a host that does not exist.
3. **Request the account server limit → 10.** Operator-driven, vendor-reviewed,
   **the long pole — start it first**.
4. **Amend `hr-prod-host-config-change-immutable-redeploy`** to name the
   no-rollback danger, and add a **stock** preflight (not a cap preflight) to the
   existing destroy-guard steps.

## Why This Approach

The issue is right that headroom is needed, but **its causal story is wrong in
both halves**, and correcting it changes what we build:

| Issue claim | Verdict | Evidence |
|---|---|---|
| "all five slots are load-bearing" | **False** | `hermes-agent` is absent from `apps/web-platform/infra/*.tf`; zero repo references; no private-net attachment; the issue's own table marks its role `—`. Operator confirms reclaimable. |
| **"the cap has no room for a blue-green cutover / a destroy that cannot re-place leaves the fleet short a host"** | **False — the central error** | **A `-replace` destroys first, freeing a slot, then creates. The cap never engages on a recreate.** It engages only on *additive* creates (a probe host, git-data, web-3) — and those fail **safely**, because nothing was destroyed. A `free_slots == 0` preflight would fail **every recreate today, for no reason.** |
| "A free slot would have made [#6393] a non-event" | **False** | #6393 failed on `resource_unavailable` (**hel1 DC stock**), not `resource_limit_exceeded` (**account cap**). Different counters. The `-replace` had already freed a slot by destroying web-2; hel1 simply had no cx33 to give back. A free slot changes nothing. |
| "Even +2 slots converts the recreate paths from destroy-first to blue-green" | **False** | `create_before_destroy` appears **nowhere** in the infra; the singletons have hard-coded names (`git-data.tf:119`, `inngest-host.tf:182`, `zot-registry.tf:227`) and pinned private IPs (`network.tf:51` → `10.0.1.20`). A create-before-destroy collides on **both** before it ever reaches the cap. **Blue-green needs an IaC redesign, not a quota change.** |

**So what does the cap actually cost us?** Not recreate safety — it removes the
*additive* options: the throwaway probe host (#6416's real gap), git-data's birth,
and web-3. That is a real cost, and it is why headroom is still worth buying. But
it is a different problem from the one the issue describes, and it does not want a
recreate preflight.

**What actually hurt in #6393 is orthogonal to the cap:** destroy-before-create has
no rollback **for any reason the create can fail** — stock, cloud-init, name
collision. The sharpest structural point is that
`hr-prod-host-config-change-immutable-redeploy` (`AGENTS.core.md:26`) **mandates**
`-replace` for every prod host config change and **says nothing about it being
irreversible mid-flight**. We have a rule requiring the dangerous action and no
rule naming the danger. That is the gap worth closing.

**A raised limit is free.** Hetzner bills per existing resource, never per quota
(`expenses.md:22` — "billing began at provision"; no quota row exists in the
ledger). So there is no cost argument for under-asking. Steady-state *need* is 6
(5 permanent incl. the unborn git-data + 1 ephemeral, serialized); **ask for 10**
because the request has vendor-review latency and asking twice costs more than
asking once.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Reclaim `hermes-agent` via snapshot-then-destroy**, not bare delete | Hetzner has **no volume snapshots** (the #6416 trap) but **does** have *server* snapshots; hermes' 40GB is a **local disk**. A snapshot preserves it for inventory, **consumes no server slot**, and is already codified — `cutover-inngest.yml:355-373` (`op=backup` → `create_image`, #5509). Reuse it; don't invent. Snapshot gets a **retention expiry** (CLO: a snapshot of personal data is continued processing). |
| 2 | **Request server limit → 10** (not +2) | Free option; need is 6; covers web-3, which the codebase already anticipates (`apply-web-platform-infra.yml:456`). Long pole — start first. |
| 3 | **DROP the cap-headroom preflight** (issue's item 4) | It guards a capability that does not exist. A `-replace` frees its own slot by destroying first, so the cap never blocks it; a `free_slots == 0` check would fail every recreate today for no reason. Additive creates already fail safely with a clear `resource_limit_exceeded` and nothing destroyed. **The operator selected this item — this is a reasoned reversal, not an omission.** |
| 4 | **Ship a STOCK preflight instead** — assert the `server_type` is orderable in the target `location` before the destroy | This is the only check that would have prevented #6393. Add to the existing plan-time destroy-guard steps (`:1165` web-2, `:1583` inngest, `:1744` registry) in **tripwire** posture, matching `:447` ("This is a TRIPWIRE, not a routine gate"). Mechanics unverified — `/v1/limits` is 404, so per-DC availability likely needs `/v1/datacenters`; confirm at plan time. |
| 5 | **Accept the TOCTOU race** | Stock can evaporate between check and apply. The only non-racy fix is create-before-destroy, which needs an IaC redesign (names + IPs). The tripwire narrows a window that stayed open long enough for #6393 to fail **four** retries — worth it; not a guarantee. |
| 6 | **Do NOT build automation for the Console limit-raise; route it to `ops-provisioner` as a one-shot execution** | Investigated per `hr-exhaust-all-automated-options-before`: Hetzner Console is OAuth (Google/GitHub) + MFA + probable Turnstile; `agent-browser` cannot traverse external OAuth; **no Soleur precedent** for infra-provider console automation. A durable automation for a once-ever action is negative ROI — but the operator must not be handed a manual step either. One-shot execution satisfies both. |
| 7 | **Amend `hr-prod-host-config-change-immutable-redeploy` (`AGENTS.core.md:26`) rather than mint a new rule id** | The rule that *mandates* `-replace` should name its own danger (no rollback mid-flight, for any create-failure reason). Adding a sibling rule splits the guidance across two ids and adds corpus noise the unused-rule reporter would flag. Alternative considered: a new `hr-destroy-requires-headroom` — rejected because "headroom" is the wrong frame (the cap is not what makes `-replace` dangerous). |
| 8 | **Fix three ledger drifts in-scope** | The cap did not prevent shadow spend — it guaranteed the shortage surfaced as an outage instead of a line item. See Ledger Drifts below. |
| 9 | **Close the residency validation gap** | The EU-DC check covers `web_hosts` **only**. Headroom that births a non-`web_hosts` host has nothing rejecting a non-EU placement. See Capability Gaps. |
| 10 | **Threshold from LIVE value, not plan target** | `best-practices/2026-06-18-capacity-monitor-threshold-from-live-value-not-plan-target.md` — the gate must assert the **live** free-slot count, not the post-reclaim narrative. |

### The phantom host — a whole corpus reasoning about something that isn't there

`soleur-git-data` has **never existed**, yet the repo treats it as live:

| Artifact | What it says | Reality |
|---|---|---|
| `expenses.md:14-16` | three rows marked **`active`** (CAX11 $4.10 + IPv4 $0.54 + LUKS volume $0.48) | ~$5.12/mo of **phantom** recurring cost. `:14`'s note *"Provisions on this PR's merge"* is the tell — written at plan time; git-data is an `OPERATOR_APPLIED_EXCLUSIONS` resource (`git-data.tf:16`) so it never provisioned on merge, and nobody reconciled the row. |
| **ADR-103** | calls git-data *"the fleet's most irreplaceable data store"* | reasoning about a phantom |
| **ADR-115** | raises a normative blocker about its `luksOpen` not surviving reboot | reasoning about a phantom |
| **PR #6242 `git-data-host-replace`** (`apply-web-platform-infra.yml:2079-2179`) | a sanctioned reprovision path | **dead code — never runnable.** A scoped `-replace` requires the resource in state. ~100 lines of workflow plus `tests/scripts/lib/git-data-host-replace-gate.sh` guarding nothing. |

This is `hr-verify-repo-capability-claim-before-assert` failing **at ADR scale** —
the ledger, the ADR corpus, and a shipped workflow path all describe a host that
is not there. **Risk: HIGH**, and it is the strongest argument in this brainstorm
for the `fleet-capacity-audit` productize candidate below.

**Refuted (verified, so it does not become a fifth artifact reasoning about a phantom):**
the CTO flagged a possible live Art. 17 erasure bug — `removeGitDataRepo` is
deliberately **not** flag-gated (`git-data-replication.ts:141`), so if
`GIT_REMOVE_SSH_PRIVATE_KEY` were in prod, every account deletion would SSH to a
non-existent `10.0.1.20`. **It does not fire.** The key is absent from Doppler
`prd` *and* `dev` (probed), and the code early-returns cleanly:
`git-data-replication.ts:151-152` → `const removeKey = process.env.GIT_REMOVE_SSH_PRIVATE_KEY?.trim(); if (!removeKey) return;`.
Consistent with git-data.tf being wholly un-applied — host, volumes, **and** its
`doppler_secret` resources (`git-data.tf:109`).

### Ledger drifts (all verified against `knowledge-base/operations/expenses.md`)

| Drift | Impact |
|---|---|
| `hermes-agent` has **no row at all** | ~€6/mo (cx23 €5.49 + IPv4) shadow spend, invisible for 49 days. The tight cap did **not** prevent shadow spend — it guaranteed the shortage surfaced as an outage rather than a line item. |
| `:14-16` mark git-data host + IPv4 + LUKS volume **`active`** | ~$5.12/mo **overstated** burn for a host that has never existed. Should be `approved-not-billing` (the ledger uses that status correctly at `:46`) |
| `:17-19` place web-2 in **hel1** | web-2 has been **fsn1** since #6393 |

## Open Questions

1. **What is `hermes-agent` actually running?** The operator confirms it is
   reclaimable, but nothing in the repo records its purpose. The snapshot makes
   this answerable *after* the slot is freed rather than blocking on it. Before
   destroy, run the read-only checks in **Reclaim preconditions** below — *unmanaged*
   is precisely why the IaC's silence proves nothing.
2. **Volume/primary-IP limits.** Live counters are 4 volumes / 10 primary IPs /
   1 network — no pressure today, but the Console form should raise the **volume**
   limit at the same time (separate counter). What those caps are is unverified —
   there is no API to read them.
3. **Does the stock preflight have an API surface?** `GET /v1/limits` → **404**
   (probed live). Per-DC server-type availability likely needs `/v1/datacenters` —
   mechanics **unverified**; confirm before implementing. If no clean surface
   exists, the stock preflight may not be buildable, and the rule amendment
   (Decision 7) carries the whole workstream.
4. **Is the cap even the binding constraint on git-data?** It is one of three
   gates (cap, #6416, ADR-115 `luksOpen`). Raising the cap alone does not unblock
   Phase 3 — worth confirming the other two are tracked before selling the raise
   on that benefit.

### Reclaim preconditions (read-only, before destroying `hermes-agent`)

1. `hcloud server describe hermes-agent -o json` — labels, attached volumes,
   primary IP. **A volume outlives its server and keeps billing after the destroy.**
   (Partially done: labels `{app: hermes-agent}`, `protection.delete: false`,
   no attached volumes in `hcloud volume list`.)
2. **Snapshot first** — converts an irreversible destroy into a reversible one;
   consumes no server slot; costs cents. Exactly the discipline missing from #6393.
3. **Check inbound DNS, not outbound refs.** Grep Cloudflare records for
   `178.105.181.90` — a record pointing at nbg1 is the one way it could still be
   serving traffic despite zero code references.
4. `hcloud primary-ip list` — a Primary IP set to non-auto-delete survives and bills.
5. **Check what it talks *to*.** 49 days old, nbg1, no private net, named "agent" —
   an outbound-only worker (bot, scraper, CI runner) would have no inbound refs and
   no IaC presence yet still be doing something. `hcloud server metrics --type network`
   over 7d shows live-vs-idle. If it is transmitting, find out where before killing it.

**Risk: LOW with a snapshot; MEDIUM without** — unmanaged means there is no state to
restore from, and 49 days of undocumented purpose is the shape of a thing someone
misses in November.

## User-Brand Impact

- **Artifact:** the web-1 (cx33, hel1, live origin) / web-2 (cx33, fsn1, weight-0
  warm standby) origin pair and its destroy-then-create recreate path
  (`web-2-recreate`, `inngest-host-replace`, `registry-host-replace`,
  `git-data-host-replace`, `registry-region-migrate`).
- **Vector:** A recreate destroys web-2, the cap plus DC stock blocks re-placement,
  and apply-on-merge wedges — so if web-1 degrades in that window users hit a full
  outage with no failover, no ability to deploy a fix, and no free slot to
  diagnose from, while the HA posture reads healthy because web-1 is still up.
- **Threshold:** `single-user incident`.

**This is adjudicated, not speculative.** The 2026-07-13 PIR's "no user-facing
impact (weight-0 web-2)" framing was **formally corrected on 2026-07-14 (#6400)**:
the same event froze the **web-1 prod deploy leg for ~10+ hours**
(`2026-07-13-web-2-fsn1-warm-standby-auth-denied-postmortem.md:22-25`). A wedged
apply means prod cannot ship a fix.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
**Spawned (cross-domain lane + USER_BRAND_CRITICAL triad):** Product (CPO), Legal (CLO), Engineering (CTO + platform-strategist)

### Product (CPO)

**Summary:** Two of three user-impact vectors are real. Destroying web-2 itself is
**not** user-visible (weight-0, zero prod traffic) — do not inflate it. But the
warm standby is **fictional** if it cannot be reborn, and the #6393 apply-wedge
froze the prod deploy leg for 10+ hours (PIR-corrected). **p2-medium is wrong**:
"workaround exists" is false when the workaround *was* deleting production data
unverified. Split — reclaim → **p1**, the durable guards → p2.

### Legal (CLO)

**Summary:** Deleting an unmanaged store is *favoured* by storage limitation
(Art. 5(1)(e)); the defect is that we cannot **attest** what we destroyed.
`hermes-agent` is absent from `knowledge-base/legal/article-30-register.md:47-48`,
which enumerates hosts individually by name — an Art. 30(1)(d)/(e) completeness gap
**today**, which destroying the host freezes rather than cures. "We had no free
slot" is **not** an Art. 5(2) defence (self-imposed; Art. 24 cost-of-implementation
does not reach €4/mo) — but the honest form is *systemic* (the cap removes
verify-before-delete **every** time), not "massive GDPR exposure". Server snapshots
dissolve the dilemma. Sharpest finding: the **residency validation gap** (below).

### Engineering (platform-strategist)

**Summary:** The "+2" ask is derived from the wrong failure model. Need is **6**;
**ask 10** (a limit is free, vendor-review latency is the only cost). Reclaiming
hermes is **cost hygiene, not headroom** in steady-state accounting — it funds
git-data's unborn slot. Role consolidation is the **trap answer**: it reverses
ADR-100/096/068 to avoid filling in a browser form. **A cap preflight would not
have caught #6393** — that is the single most important correction to the issue.
Region concentration is the real #6393 lesson (4 of 5 post-reclaim hosts in hel1,
the DC with a twice-demonstrated shortage).

### Engineering (CTO)

**Summary:** Recommends **items 1 + 2 only; drop the preflight (4) and drop
building automation for (3)**. The decisive catch: **every recreate path is
destroy-before-create, which needs *zero* free slots** — so a cap preflight guards
a capability that does not exist and would fail every recreate today. Blue-green is
structurally impossible at **any** slot count: hard-coded names *and* pinned private
IPs (`network.tf:51` → `10.0.1.20`; `network.tf:43` → `each.value.private_ip`)
collide before the cap is ever reached. Surfaced **FINDING 0** (the phantom
git-data corpus above) independently. On git-data: ADR-068 is `adopting` and the
code is **built, wired, and dark** — `agent-runner.ts:2411-2413` and
`cc-dispatcher.ts:1322-1323` call `replicateToGitData` behind
`isGitDataStoreEnabled()`, a plain env strict flag (`workspace-resolver.ts:56-58`,
default false), deliberately not Flagsmith so the cutover is atomic. Verdict:
apply git-data eventually, but **behind #6416 and ADR-115's `luksOpen` blocker**.
Recommends amending the existing rule rather than minting a new id. Flagged
honestly that it had **no hcloud token** and could verify no live fact.

**Reconciliation — the three leaders disagreed on the reclaim math, and each was
right about something different:**

| Leader | Claim | Verdict |
|---|---|---|
| CPO | reclaim → 4/5 → "one free slot is exactly what blue-green needs" | **Half right.** The free slot is real, but it does not enable blue-green — nothing does, at any slot count. |
| platform-strategist | reclaim buys **zero** headroom; it funds git-data's unborn slot (5→4→5) | **Right in steady-state accounting**, wrong about the near term. |
| CTO | +1 buys exactly one thing: ADR-068 Phase 3 can land. No headroom. | **Right on the mechanism**, overstates the urgency. |

**Resolution:** git-data's birth is **not imminent** — its GA trigger #5274 sits in
milestone **"Post-MVP / Later"**, it is additionally gated behind #6416 and
ADR-115's `luksOpen` blocker, and #5723 would move the store to Garage later
anyway. So the reclaimed slot is a **genuine free slot for the foreseeable
future**, restoring the probe-host option #6416 lost. **And** the raise is still
required to reach steady state (cap 5 < need 6). Not either/or — sequence both,
reclaim first because it needs no vendor.

Where all three converge, and it is the finding that matters most: **the cap has
silently pinned ADR-068 Phase 3 at zero.** `GIT_DATA_STORE_ENABLED` is unflippable
because the host cannot be born at 5/5. That is a more consequential cost than the
diagnostics gap the issue leads with — though "Post-MVP / Later" means it is
blocking a *parked* phase, not an active one.

## Capability Gaps

| Gap | Domain | Evidence |
|---|---|---|
| **No *stock* preflight exists** (and no capacity preflight of any kind). `web2-recreate-preflight.sh` checks *image coherence* only (ADR-080 stale-image trap), not availability. The ADR-114 `host_creates` guard (`apply-web-platform-infra.yml:419-458`) is **orthogonal** — it fires on `+ create` on the **wrong apply path** (the #6416 private-NIC drift class), counts plan intent, and never queries Hetzner; its own comment scopes it to the per-PR path (*"the dispatch jobs that legitimately create one are not gated here"*). A stock preflight would share zero logic with it. **Note: a *cap* preflight is NOT a gap — it is a non-requirement** (see Decision 3). | Engineering | Grepped `resource_limit_exceeded`, `server limit`, `hcloud server list` across `.github/workflows/` + `apps/web-platform/infra/scripts/` — zero preflight hits. |
| **All existing destroy-guards are fail-closed with NO `[ack-destroy]` bypass** — they compare the plan against a hardcoded allow-set. A new stock tripwire should match that posture rather than introduce an override. | Engineering | `apply-web-platform-infra.yml:1775-1776`, `:1613`, `:2170-2171`. |
| **Residency validation covers `web_hosts` only.** `variable "location"` (`variables.tf:38`, drives git-data + inngest) and `variable "registry_location"` (`:44`, drives the registry) have **no `validation` block**. `inngest_server_type`'s validation (`:156`) is an **arch regex**, not a location check. Only `web_hosts` carries `contains(["nbg1","fsn1","hel1"], …)` at `:94-96`. A headroom-birthed non-`web_hosts` host can land non-EU with nothing rejecting it. git-data holds bare git objects — the fleet's highest-value residency surface. | Legal / Engineering | `git show main:apps/web-platform/infra/variables.tf \| grep -nE 'variable "\|validation \{'` — validation blocks exist only at `:94`, `:98`, `:155`. |
| **No Hetzner limits API.** `GET /v1/limits` → **404** (probed live with the prd token). Confirms the raise cannot be self-served, and that a cap preflight must derive free slots from `GET /v1/servers` count vs. a **hardcoded** known cap — itself a drift risk. | Engineering | `curl -H "Authorization: Bearer $HCLOUD_TOKEN" https://api.hetzner.cloud/v1/limits` → 404; `/v1/pricing` → 200 (token valid). |
| **No precedent for infra-provider console automation.** `ops-provisioner` automates SaaS signup via Playwright/`agent-browser`; all Hetzner provisioning is API/Terraform-driven. Console is OAuth + MFA + probable Turnstile. | Operations | `plugins/soleur/agents/operations/ops-provisioner.md:26-28`; `plugins/soleur/skills/agent-browser/SKILL.md`. |
| **No phantom-resource detection.** Nothing catches a resource declared unconditionally, excluded from every apply allow-list, and never applied. `terraform-target-parity.test.ts` asserts git-data **is excluded**; nothing asserts it therefore **exists**. This is what let #6242 ship a `-replace` path for a host that was never born. | Engineering | See "The phantom host" above. |
| **No fleet-vs-ledger reconcile.** Nothing compares live `hcloud` state against `expenses.md`. All three ledger drifts here were found by hand-probing during a brainstorm. | Operations (`ops-advisor` owns the ledger) | See "Ledger drifts" above. |

## Deferred (file as follow-ups)

| Item | Why deferred | Re-evaluation criteria |
|---|---|---|
| **Blue-green via add/drain/remove** (`web-3` semantics — distinct keys + generated names + IP allocation, replacing `-replace`) | The only non-racy fix, and the *only* thing that would make the issue's blue-green ask real. But it is an IaC redesign of three load-bearing hosts that amends `hr-prod-host-config-change-immutable-redeploy` and ADR-103 — **it warrants its own ADR**, not a line in this issue. | A stock-blocked recreate strands the fleet a **third** time. |
| **Location override on recreate dispatches** (re-place into a sibling eu-central DC instead of wedging) | The generalized #6393 fix; distinct from headroom, and needs its own risk review (cross-DC hosts cannot share the location-scoped placement group). | Any recreate blocked on `resource_unavailable`. |
| **Fresh-boot readiness assertions** per host | Three postmortems in two weeks (07-06 errexit, 07-13 auth-denied, 07-14 zot NIC — a **14-day silent outage**) show fresh boots fail *silently* while all health gates read green. Any born-new strategy **assumes** a fresh host boots correctly; the evidence says that is not safe. Partially addressed by ADR-115's `soleur-private-nic-guard.sh`. "Remembering is not a control" — the assertion must be automated, not a runbook step. | Before any add/drain/remove work lands. |
| **git-data birth** | Wanted (ADR-068 `adopting`; code built, wired, dark), but gated behind the cap **and** #6416 **and** ADR-115's `luksOpen`-doesn't-survive-reboot blocker. Its GA trigger #5274 is "Post-MVP / Later". | Cap raised **and** #6416 closed **and** ADR-115 blocker cleared. |

## Productize Candidate

`Productize Candidate: fleet-capacity-audit` — a periodic reconcile of live
Hetzner resources vs. IaC vs. `expenses.md`. All three drifts found here
(unmanaged host, `active` rows for an unborn host, stale region) are the same
class and were found only by hand-probing during a brainstorm.
</content>
