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
- **Building durable automation for the Console limit-raise.** A real browser attempt
  reached the live login form: the `/_ray/pow` interstitial **auto-cleared** and
  `accounts.hetzner.com/login` rendered. The gate is that **no Hetzner Console credential
  exists** — Doppler holds only `HCLOUD_TOKEN` (an API token that cannot reach the limits
  form) across `prd_terraform`/`prd`/`dev`, and the account password lives solely in the
  operator's personal password manager. Storing a root infra-account password for an agent
  to use is an operator **security decision**, not a blocker to route around. Negative ROI
  for a once-ever action. Filed as **#6481** on 2026-07-15.
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

It was verified operator-only by a real attempt, not assumed — and the **first recorded
reason was wrong**. This spec previously claimed `accounts.hetzner.com/login` redirects to
`/_ray/pow` returning **HTTP 429**, an anti-bot wall blocking the run. **Not reproducible
on 2026-07-15:** the PoW interstitial **auto-cleared on the first attempt** and the run
reached the real login form (client-number + password fields, no active session). The
conclusion survives; the reason does not.

`playwright-attempt: navigated https://console.hetzner.cloud/ (301 → console.hetzner.com).
The /_ray/pow interstitial at accounts.hetzner.com AUTO-CLEARED and the run reached
accounts.hetzner.com/login. Gate reached: a CREDENTIAL WALL with no credential in
existence — Doppler holds only HCLOUD_TOKEN across prd_terraform/prd/dev, an API token
that cannot reach the limits form; the persistent playwright-mcp profile holds 65 domains
(Cloudflare, Better Stack, Sentry, Resend, GitHub, Google) and ZERO Hetzner, so there was
no session to reuse. GET /v1/limits → 404 while GET /v1/pricing → 200 with the same token,
proving the 404 is a real absence and not an auth artifact. The account password lives only
in the operator's personal password manager.`

"No credential exists" is **not** one of the enumerated human gates
(CAPTCHA/OTP/TOTP/passkey/push-MFA/card/hardware). It is operator-only because storing the
root infra-account password in Doppler for an agent to use is a **security decision for the
operator** — not a technical blocker. Recorded this way deliberately: had the 429 claim
been taken at face value, the standing reason would have been fiction.

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

> **The plan is authoritative for the ACs** — see
> `knowledge-base/project/plans/2026-07-15-chore-hetzner-cap-headroom-plan.md`
> (`## Acceptance Criteria`, trimmed 16 → 9 at plan-review). This list is the
> goal-level view; each box below was re-verified against the tree at ship, not
> ticked from the plan's prose.

- [x] `hcloud server list` returns 4 — **done 2026-07-15**
- [x] ~~Snapshot `408787015` has a retention expiry set~~ — **obsolete, not open.**
      FR1 was dropped: the snapshot was **deleted in-session** (operator decision), which
      satisfies the CLO's expiry requirement with zero machinery. There is no retention to
      set on an object that no longer exists. G1 is CLOSED.
- [x] `expenses.md` has no `active` rows for non-existent resources (git-data
      → `approved-not-billing`); web-2 reads fsn1
      — verified: git-data `active` rows = **0**; web-2 rows = **3**, all fsn1.
- [x] `AGENTS.core.md` names the no-rollback danger; rule id unchanged (occurrences = **1**),
      with the ADR-092 / AP-017 hash-bound body ack appended (`rule-body-lint` is an
      always-run **required** check).
- [x] Server limit raise **requested** 2026-07-15 (operator). Gate was a **missing Console
      credential**, not the PoW wall — evidence in G3 above. Approval is **not** verifiable
      by API (`/v1/limits` 404) — consumer-discovered at the next additive create.
      Tracked as **#6481** (`action-required`).
- [x] Residency validation covers `var.location` + `var.registry_location`
      (`variables.tf:47-50`, `:61-64`).
- [x] Stock preflight **shipped** — `tests/scripts/lib/stock-preflight-gate.sh` wired into
      all **five** destroy-shaped paths, with a hermetic synthesized-fixture suite
      registered in `scripts/test-all.sh`.

**Post-merge (operator, not a merge blocker):**

- [ ] **AC13** — Hetzner Console limit raise (servers 5 → 10, plus the volume limit).
      Vendor-side and **unverifiable by construction**; filed as **#6481**. See G3 for the
      attempt evidence and why no tracker can poll it.

## Open Risks

- **TOCTOU** — stock can evaporate between check and apply; the tripwire narrows a
  window it cannot close.
- **Fresh-boot reliability** — three postmortems in two weeks show fresh boots fail
  *silently* while health gates read green. Any born-new strategy inherits this.
- **`hermes-agent` purpose is unknown and the destroy is NOT reversible.** An earlier
  draft of this line read *"the snapshot makes the destroy reversible, which is what makes
  proceeding acceptable"* — that is **false as of 2026-07-15**: snapshot `408787015` was
  deleted the same day (operator decision, FR1 dropped). **THERE IS NO ROLLBACK.** What
  makes proceeding acceptable is no longer reversibility but the deliberate trade recorded
  in G1 — retaining an unaudited 40 GB disk of unknown provenance with no expiry is
  continued processing (CLO), and every enforcement mechanism available was worse than the
  risk. If something breaks and the cause is unclear, **suspect this host first — it cannot
  be restored.** Disclosed in `expenses.md`.
</content>
