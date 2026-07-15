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
- **G3** — Raise the account server limit to 10. **Rationale: probe/scratch hosts only** —
  not git-data (stock-blocked: cax11 is orderable in 0 EU DCs) and not web-3 (births via an
  operator-local apply, outside CI). A limit is free (Hetzner bills per running server).
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
- **Building durable automation for the Console limit-raise.** A real browser attempt hit
  a `/_ray/pow` proof-of-work gate returning 429, with no Console credentials anywhere and
  no Hetzner session in the persistent profile. Negative ROI for a once-ever action. The
  operator filed it directly on 2026-07-15.
- **Blue-green / add-drain-remove.** Warrants its own ADR; deferred.
- **git-data birth.** Blocked by **stock** above all (cax11 → 0 of 3 EU DCs, so it cannot
  be born at ANY cap), plus ADR-115's `luksOpen` blocker; GA trigger #5274 is "Post-MVP /
  Later".
- **Role consolidation.** Would reverse ADR-100/096/068 to avoid a browser form.

## Functional Requirements

- **FR1** — ~~Snapshot retention follow-through~~ **DROPPED** (operator, 2026-07-15).
  The snapshot was taken (reusing `cutover-inngest.yml:355-373`), the destroy was made
  reversible by it, and it was then deleted rather than enrolled in a 30-day soak. See
  the G1 note above for why every enrollment mechanism was worse than the risk.
- **FR2** — Run the read-only reclaim preconditions (inbound-DNS grep for
  `178.105.181.90`, `primary-ip list`, 7d network metrics) and record the results
  before destroying.
- **FR3** — Add a `hermes-agent` row to `expenses.md`, then retire it — do not
  silently delete the host, or the shadow-spend class recurs.
- **FR4** — Flip `expenses.md:14-16` from `active` → `approved-not-billing`; correct
  `:17-19` web-2 hel1 → fsn1.
- **FR5** — Amend `hr-prod-host-config-change-immutable-redeploy` (`AGENTS.core.md:26`)
  in place. Do **not** mint a new rule id.
- **FR6** — Stock preflight in the existing plan-time destroy-guard steps — **FIVE, not
  three**: gate call sites `:1197` (web-2), `:1614` (inngest), `:1776` (registry), `:1969`
  (registry-region-migrate), `:2171` (git-data-host-replace — NOT dead code: a `-replace`
  on a not-in-state address plans a plain **create**). **Tripwire** posture (match `:447`),
  fail-closed, no `[ack-destroy]` bypass (match `:1775`). **SHIPPED** as
  `tests/scripts/lib/stock-preflight-gate.sh` + a 32-case hermetic suite.

## Technical Requirements

- **TR1** — The stock check MUST assert the **live** value, not a plan target
  (`best-practices/2026-06-18-capacity-monitor-threshold-from-live-value-not-plan-target.md`).
- **TR2** — **RESOLVED: FR6 is buildable and shipped.** `GET /v1/datacenters` exposes
  `server_types.available` (orderable NOW) distinctly from `.supported` (24/DC). Use
  `.available` — `.supported` would pass the live trap, as does the `hcloud` CLI's
  `server-type list -o columns=name,location`. Resolve the type via `?name=<type>`, never
  `?per_page=50` (which encodes "≤50 types" and fails CLOSED if one lands on page 2).
  `GET /v1/limits` is 404 — the drop-clause did not fire.
- **TR3** — Extend the EU-DC `contains(["nbg1","fsn1","hel1"], …)` validation
  (currently `variables.tf:94-96`, `web_hosts` only) to `var.location` (`:38`) and
  `var.registry_location` (`:44`). `inngest_server_type`'s validation (`:156`) is an
  arch regex, not a location check.
- **TR4** — Do not add `[ack-destroy]`-style overrides; existing recreate guards
  have none.

## Status — G1 is DONE (2026-07-15, in-session)

**The reclaim already shipped. Do not re-plan it.**

- `hermes-agent` destroyed 2026-07-15. **Fleet is 4/5 — one free slot**, first time.
- Snapshot `408787015` was taken, then **DELETED the same day** (operator decision).
  **THERE IS NO ROLLBACK.** Retaining an unaudited disk of unknown provenance without an
  expiry is continued processing (CLO); Hetzner images carry no TTL; and every enforcement
  mechanism available was worse than the risk (the follow-through sweeper only *closes*
  trackers, is `--state open` so `Closes #6453` would kill the enrollment at merge, and
  arming it with a Hetzner credential would hand that credential to all 28 follow-through
  scripts via an editable issue body). G1 is CLOSED — nothing remains.
- Both primary IPs were `auto_delete=true` → no orphaned IP billing (verified).
- `expenses.md` row added **at retirement** (~USD 9.7 lifetime shadow spend recorded).
- **Purpose never established.** At reclaim it was steadily transmitting ~410 MiB/day
  outbound (711 B/s out vs 448 B/s in, ~0.43 pps, CPU avg 1.9%) — a low-rate outbound
  producer reporting somewhere unknown. Operator authorised the destroy, then authorised
  deleting the snapshot. **If something breaks and the cause is unclear, suspect this host
  first — but it CANNOT be restored.** That is the accepted cost of not retaining
  unaudited data.

**G3 — REQUESTED by the operator 2026-07-15. Pending Hetzner review (vendor-side, days).**

It was verified operator-only by a real attempt, not assumed: `console.hetzner.cloud`
301s to `console.hetzner.com`, and `accounts.hetzner.com/login` redirects to **`/_ray/pow`
returning HTTP 429** — a proof-of-work anti-bot gate that rate-limits a non-browser client
before a login form ever renders. Compounding it: `GET /v1/limits` → **404** (no API to
read or raise a quota), **no Hetzner Console credentials exist in Doppler** (only
`HCLOUD_TOKEN`, an API token that cannot reach the limits form), and the persistent
playwright-mcp profile holds 65 domains — Cloudflare, Better Stack, Sentry, Resend, GitHub,
Google — and **zero Hetzner**, so there was no session to reuse.

**Detection of approval is impossible by construction, and that is stated rather than
papered over.** `/v1/limits` re-probed post-request: still 404. No follow-through can be
enrolled (no signal to read); `action-required` has no sweeper. The fleet is at **4**, so
the only empirical test is a create that would exceed 5 — which for the CX line would
currently fail on *stock* anyway, confounding the signal. **The raise is therefore
consumer-discovered:** whoever next needs an additive host finds out then, via a clean
non-destructive `resource_limit_exceeded`. Acceptable because the stock preflight means a
*recreate* never depended on the cap — the raise only buys back the additive/probe-host
option (#6416's gap).

## Acceptance Criteria

- [x] `hcloud server list` returns 4 — **done 2026-07-15**
- [ ] Snapshot `408787015` has a retention expiry set (open remainder of G1)
- [ ] `expenses.md` has no `active` rows for non-existent resources (git-data `:14-16`
      → `approved-not-billing`); web-2 `:17-19` reads fsn1
- [ ] `AGENTS.core.md:26` names the no-rollback danger; rule id unchanged
- [x] Server limit raise **requested** 2026-07-15 (operator; Console PoW-gated — evidence in G3 above). Approval is **not** verifiable by API (`/v1/limits` 404) — consumer-discovered at the next additive create.
- [ ] Residency validation covers `var.location` + `var.registry_location`
- [ ] Stock preflight shipped **or** explicitly dropped with the API finding recorded

## Open Risks

- **TOCTOU** — stock can evaporate between check and apply; the tripwire narrows a
  window it cannot close.
- **Fresh-boot reliability** — three postmortems in two weeks show fresh boots fail
  *silently* while health gates read green. Any born-new strategy inherits this.
- **`hermes-agent` purpose is unknown** — the snapshot makes the destroy reversible,
  which is what makes proceeding acceptable.
</content>
