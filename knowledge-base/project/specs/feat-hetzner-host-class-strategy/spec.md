---
feature: hetzner-host-class-strategy
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-08-06
brainstorm: knowledge-base/project/brainstorms/2026-08-06-hetzner-host-class-strategy-brainstorm.md
related_issues: [7309, 7287, 7247, 7027]
---

# Spec — Hetzner host-class resilience

## Problem Statement

A single hardcoded `server_type` default per host converts a Hetzner inventory flap into a hard
block on unrelated work, and each flap is then written into a `.tf` comment as a durable fact
that the next issue quotes after it has expired.

This has now happened three times (#6966 web-2, #6178 inngest, #7309 registry). The live probe
of 2026-08-06 shows #7309's blocking premise already false — `cx23` is orderable in all three EU
DCs — two days after it was recorded.

Two consequences, both measured (see brainstorm § headline / § cost):

1. Work blocks on a condition that is transient and unowned.
2. The fleet carries a standing **≈€28.00/mo (≈€336/yr)** premium from stock-forced `cpx22`
   pins made during outages that have since reversed, with nothing to re-evaluate them.

## Goals

- **G1** A stock flap must never again hard-block a host create. It should degrade to a
  transient price change on that one boot.
- **G2** Stock availability must be observable over time, so decisions stop being argued from
  expired point-in-time snapshots.
- **G3** The two issues carrying stale readings (#7309, #7287) must be corrected, because
  #7287's blocking table gates a destructive dispatch.

## Non-Goals

- **NG1** Moving web-2 / inngest off `cpx22` to recover the ≈€28/mo. Deferred — each is a
  destroy-and-recreate of a live host, and inngest holds a Redis AOF volume (the exact
  stranding risk #6393/#6463 motivated the stock gate for). Own issue.
- **NG2** Any provider migration. Position and triggers are recorded in the brainstorm (D5);
  none are met today.
- **NG3** Firing any registry recreate. Blocked on #7278 + the five REQUIRED pre-first-fire
  re-verifications (brainstorm D8/D9/D10). Not this feature's scope.
- **NG4** Changing the registry's *sizing*. If a fallback is ever forced, `cx33` is preferred
  over `cpx22` (D2), but no repin is proposed here.

## Functional Requirements

- **FR1** Replace the single-value `server_type` pin with an ordered, cheapest-orderable-first
  **preference list** per host, e.g.
  `registry_server_type_preference = ["cx23", "cx33", "cpx22"]`.
- **FR2** Selection is evaluated **at create time only**, against live
  `/v1/datacenters` `.server_types.available` for the host's target location.
- **FR3** Each host gains `lifecycle { ignore_changes = [server_type] }` so a returning cheaper
  SKU never proposes a destroy-and-recreate to move back. **Load-bearing:** without it, stock
  recovering is strictly worse than the outage it fixes.
- **FR4** Extend `tests/scripts/lib/stock-preflight-gate.sh` to **select** from a preference
  list, not only **assert** on one type. It already owns fail-closed probing, shape-guarding,
  and the `.available`-never-`.supported` discipline; today it only answers yes/no about a type
  someone else picked.
- **FR5** The selected type must be surfaced in the plan/apply log so an operator can see which
  preference tier was taken and at what price.
- **FR6** A scheduled workflow probes EU DC availability for the fleet's candidate types and
  emits a monitored `SOLEUR_HCLOUD_STOCK` stdout marker (Better Stack), per
  `hr-no-dashboard-eyeball-pull-data-yourself` and `hr-observability-layer-citation`.
- **FR7** Correct #7309 (premise expired; `cx33` dominates `cpx22` if a fallback is forced) and
  #7287 (flip the "Hetzner stock — not closable by any issue" row; PR #7300 is **merged**, not
  an open draft).

## Technical Requirements

- **TR1** Arch stays derived from the selected type's prefix (`cax*` → arm64, else amd64). The
  preference list must **not** mix arches within one host's list unless the cloud-init render is
  verified on both arms — `cax` is excluded from all default lists anyway (out in 3/3 EU DCs at
  every recorded probe).
- **TR2** The ADR-062 registry memory cap is **derived** (`memory × 1024 − 1024`). A preference
  list spanning different RAM sizes moves the cap (3072m on 4 G, 7168m on 8 G). The derivation
  already reads the live catalog, so this is consistent by construction — but it must be
  asserted by a test, not assumed.
- **TR3** `user_data` must not re-render as a side effect of adding `ignore_changes`
  (`hcloud_server.registry` deliberately has **no** `ignore_changes = [user_data]`; that must be
  preserved exactly — it is what makes a code change reach this cloud-init-only host).
- **TR4** Adding `ignore_changes = [server_type]` to an existing resource is a no-op on state;
  confirm with a plan that shows **zero** changes for hosts already on their top preference.
- **TR5** No secret may reach logs; the probe reads `HCLOUD_TOKEN` from Doppler
  `soleur/prd_terraform` read-only.
- **TR6** The scheduled probe must fail **visibly** — a probe that silently exits 0 on an
  unreachable API reproduces the "empty query reads as all-clear" defect. Absence of stock data
  must be distinguishable from absence of stock.

## Acceptance Criteria

- [ ] A host whose top-preference type is out of stock still creates, on the next available
      tier, with the tier and price logged (FR1, FR2, FR5).
- [ ] Stock returning for a cheaper tier produces a **zero-change** plan for an existing host
      (FR3, TR4).
- [ ] `stock_preflight_gate` selects and still fails closed on an unreachable API (FR4, TR6).
- [ ] `SOLEUR_HCLOUD_STOCK` is queryable in Better Stack and the marker is in the Vector
      allowlist — verified by an actual query returning rows, not by the workflow exiting 0
      (FR6, TR6).
- [ ] #7309 and #7287 updated; #7287's stock row no longer reads "not closable by any issue"
      (FR7, G3).
- [ ] No recurring cost added. If any is, it is stated in €/mo and accepted before ready
      (`wg-record-recurring-vendor-expense-before-ready`).

## User-Brand Impact

- **Artifact:** the fleet's `server_type` selection path across
  `apps/web-platform/infra/*.tf` + `tests/scripts/lib/stock-preflight-gate.sh`.
- **Vector:** a selection bug that picks an un-orderable type authorizes a destroy whose create
  then fails, stranding a host with its volume detached (#6393/#6463 precedent) — for the
  registry that means the release path is dark; for git-data it would mean every connected
  user's source code host. An `ignore_changes` omission converts stock *recovering* into an
  unplanned destroy-and-recreate of a healthy host.
- **Threshold:** `single-user incident`.
