---
feature: hetzner-cap-headroom
issue: 6453
pr: 6457
branch: feat-hetzner-cap-headroom
date: 2026-07-15
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-07-15-hetzner-cap-headroom-brainstorm.md
status: draft
---

# Spec — Hetzner server-cap headroom (#6453)

## Problem Statement

The Hetzner account is at its 5-server cap (verified live: `hcloud server create`
→ `resource_limit_exceeded`). The issue attributes two incidents to this and asks
for a limit raise plus a recreate preflight.

**The attribution is largely wrong, and the corrected problem is different:**

- **A `-replace` destroys first, freeing its own slot, then creates. The cap never
  blocks a recreate.** #6393 failed on `resource_unavailable` (hel1 **DC stock**),
  not on the cap — the `-replace` had already freed a slot by destroying web-2.
- **Blue-green is impossible at any slot count.** No `create_before_destroy` exists
  anywhere in the infra, and the singleton hosts have hard-coded names and pinned
  private IPs, which collide before the cap is ever reached.
- **One of the five slots is not load-bearing.** `hermes-agent` is absent from the
  IaC, has zero repo references, no private-net attachment, and no ledger row.

**What the cap actually costs:** the *additive* options — a throwaway probe host
(#6416, where its absence forced deleting a volume unverified), git-data's birth
(which pins ADR-068 Phase 3 at zero), and web-3.

**What #6393 actually cost:** destroy-before-create has no rollback for **any**
create-failure reason, and `hr-prod-host-config-change-immutable-redeploy` mandates
`-replace` without naming that danger.

**Adjacent discovery (not in the issue):** `soleur-git-data` has never existed, yet
`expenses.md:14-16` bills it `active` (~$5.12/mo phantom), ADR-103/ADR-115 reason
about it normatively, and PR #6242 shipped a `git-data-host-replace` path that has
never been runnable.

## Goals

- **G1** — Reclaim the `hermes-agent` slot via snapshot → destroy → offline
  inventory, restoring the probe-host option with zero vendor dependency.
- **G2** — Reconcile the phantom git-data ledger rows and mark the dead
  `git-data-host-replace` path as not-yet-runnable.
- **G3** — Raise the account server limit to 10 (need is 6; a limit is free).
- **G4** — Amend `hr-prod-host-config-change-immutable-redeploy` to name the
  no-rollback danger of `-replace`.
- **G5** — Add a **stock** preflight to the existing destroy-guard steps, if a
  clean API surface exists.
- **G6** — Close the residency-validation gap on `var.location` /
  `var.registry_location`.

## Non-Goals

- **A cap-headroom preflight.** Explicitly dropped — it guards a non-existent
  capability and would fail every recreate today. (Operator originally selected it;
  reversed with reasoning in the brainstorm's Decision 3.)
- **Building durable automation for the Console limit-raise.** Not production-safe
  (OAuth + MFA + probable Turnstile, no precedent) and negative ROI for a once-ever
  action. Routed to `ops-provisioner` as a **one-shot execution** instead.
- **Blue-green / add-drain-remove.** Warrants its own ADR; deferred.
- **git-data birth.** Gated behind the cap **and** #6416 **and** ADR-115's
  `luksOpen` blocker; GA trigger #5274 is "Post-MVP / Later".
- **Role consolidation.** Would reverse ADR-100/096/068 to avoid a browser form.

## Functional Requirements

- **FR1** — Snapshot `hermes-agent` before destroy, reusing the codified pattern at
  `.github/workflows/cutover-inngest.yml:355-373` (`op=backup` → `create_image`,
  #5509). The snapshot MUST carry a retention expiry (a snapshot of personal data
  is continued processing).
- **FR2** — Run the read-only reclaim preconditions (inbound-DNS grep for
  `178.105.181.90`, `primary-ip list`, 7d network metrics) and record the results
  before destroying.
- **FR3** — Add a `hermes-agent` row to `expenses.md`, then retire it — do not
  silently delete the host, or the shadow-spend class recurs.
- **FR4** — Flip `expenses.md:14-16` from `active` → `approved-not-billing`; correct
  `:17-19` web-2 hel1 → fsn1.
- **FR5** — Amend `hr-prod-host-config-change-immutable-redeploy` (`AGENTS.core.md:26`)
  in place. Do **not** mint a new rule id.
- **FR6** — Stock preflight in the existing plan-time destroy-guard steps
  (`:1165` web-2, `:1583` inngest, `:1744` registry), **tripwire** posture
  (match `:447`), fail-closed with no `[ack-destroy]` bypass (match `:1775`).

## Technical Requirements

- **TR1** — The stock check MUST assert the **live** value, not a plan target
  (`best-practices/2026-06-18-capacity-monitor-threshold-from-live-value-not-plan-target.md`).
- **TR2** — `GET /v1/limits` is **404**; free slots can only be derived from
  `GET /v1/servers` count vs. a hardcoded cap — itself a drift risk. Prefer
  `/v1/datacenters` for per-DC availability. **Mechanics unverified — confirm first;
  if no clean surface exists, drop FR6 and let FR5 carry the workstream.**
- **TR3** — Extend the EU-DC `contains(["nbg1","fsn1","hel1"], …)` validation
  (currently `variables.tf:94-96`, `web_hosts` only) to `var.location` (`:38`) and
  `var.registry_location` (`:44`). `inngest_server_type`'s validation (`:156`) is an
  arch regex, not a location check.
- **TR4** — Do not add `[ack-destroy]`-style overrides; existing recreate guards
  have none.

## Acceptance Criteria

- [ ] `hcloud server list` returns 4; a `hermes-agent` snapshot exists with an expiry.
- [ ] `expenses.md` has no `active` rows for non-existent resources; web-2 reads fsn1.
- [ ] `AGENTS.core.md:26` names the no-rollback danger; rule id unchanged.
- [ ] Server limit raised (or the request filed and tracked).
- [ ] Residency validation covers `var.location` + `var.registry_location`.
- [ ] Stock preflight shipped **or** explicitly dropped with the API finding recorded.

## Open Risks

- **TOCTOU** — stock can evaporate between check and apply; the tripwire narrows a
  window it cannot close.
- **Fresh-boot reliability** — three postmortems in two weeks show fresh boots fail
  *silently* while health gates read green. Any born-new strategy inherits this.
- **`hermes-agent` purpose is unknown** — the snapshot makes the destroy reversible,
  which is what makes proceeding acceptable.
</content>
