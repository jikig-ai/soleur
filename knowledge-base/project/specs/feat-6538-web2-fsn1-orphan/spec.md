---
feature: web-2 retire (fsn1 orphan)
date: 2026-07-16
lane: cross-domain
brand_survival_threshold: single-user incident
closes: [6538, 6463]
related: [6393, 6453, 6457, 6459, 6460]
brainstorm: knowledge-base/project/brainstorms/2026-07-16-web2-retire-fsn1-orphan-brainstorm.md
status: ready-for-plan
---

# Spec — Retire web-2 (fsn1 orphan)

## Problem Statement

`soleur-web-2` (cx33 @ fsn1) is simultaneously:

1. **Un-rebuildable** — `cx33` is orderable in exactly one datacenter globally (`hel1-dc2`),
   so a `web-2-recreate` dispatch aborts at the stock preflight (working as designed, PR #6457).
2. **Dark** — 0 Better Stack log lines in 24 h (web-1 ships 17,987). It was created
   2026-07-13, one day before the ungated `soleur-vector-install` landed in cloud-init;
   cloud-init runs first-boot only and `ignore_changes = [user_data]` means a user_data
   change never reaches a running host. Only a recreate installs Vector — and (1) blocks that.
3. **Structurally excluded from the target topology** — `placement_group_id` is set by a
   ternary gated on co-location with web-1 AND listed in `ignore_changes`, making it
   **create-time only**. A host born in fsn1 can never join `hcloud_placement_group.web_spread`.

Meanwhile it has **never served traffic** (no load balancer resource exists anywhere in the
repo), its 20 GB `/workspaces` volume is **empty**, and the capability it exists for is
gated by ADR-068 §(c) behind `soleur-git-data`, a host that **has never existed** on a type
(`cax11`) orderable in **0 of 3 EU DCs**.

It costs €8.49/mo and occupies **1 of 5** server slots at the account cap (#6453).

## Goals

- **G1** — Remove web-2 from the fleet: delete its `var.web_hosts` entry and destroy the
  host + its empty volume via a **guarded** destroy path.
- **G2** — Leave `main` in a state where no `web["web-2"]` reference strands.
- **G3** — Correct the Art. 30 register, which describes web-2 as *"(CX33, `hel1`)"*
  (a §5(2) accuracy defect introduced when PR #6393 moved it without amending the register).
- **G4** — Reconcile `expenses.md` (and `cost-model.md`) with the live fleet.
- **G5** — Resolve #6538 and #6463 with the recorded operator decision.

## Non-Goals

- **NG1** — Making web-2 recreatable (cpx32 @ fsn1, +€27/mo). Rejected: buys observability
  of a host barred from serving.
- **NG2** — Moving web-2 to hel1 (cx33). Rejected: reverts PR #6393's documented cross-DC
  decision and re-bets on a SKU orderable in one DC today, zero yesterday.
- **NG3** — Fixing the empty/inert placement group. Separate issue (deferred; see below).
- **NG4** — Birthing `git-data` / choosing its replacement server type. Separate brainstorm —
  moving off ARM invalidates ADR-068's *"git/sshd are ARM-native"* rationale.
- **NG5** — Building the load balancer or any active-active ingress. That is #6459 + ADR-068 §(c).
- **NG6** — Reaping `soleur-grok-dogfood` (live but ledgered as *"not born"*). Feeds #6460.

## Functional Requirements

- **FR1** — Remove the `"web-2"` key from `var.web_hosts` in `apps/web-platform/infra/variables.tf`,
  including its now-obsolete cross-DC rationale comment.
- **FR2** — Destroy `hcloud_server.web["web-2"]`, `hcloud_volume.workspaces["web-2"]`,
  `hcloud_server_network.web["web-2"]`, and `hcloud_volume_attachment.workspaces["web-2"]`
  via a guarded `workflow_dispatch` path (`hcloud_server.web` is **excluded** from push-apply,
  so a merge alone will not destroy it — see TR1).
- **FR3** — Sweep every `web["web-2"]` / `web-2` reference in `apps/web-platform/infra/**`
  and `.github/workflows/**` (incl. `scheduled-inngest-health.yml`, `web2-recreate-preflight.sh`,
  the `web-2-recreate` dispatch target and its gate lib + tests) and remove or re-scope each.
- **FR4** — Amend `knowledge-base/legal/article-30-register.md` §(d)/§(e) to strike the web-2
  clause; likewise `compliance-posture.md`.
- **FR5** — Update `knowledge-base/operations/expenses.md`: remove the three web-2 rows
  (`CX33 (web-2) 15.37`, `Volume (web-2, 20 GB) 0.88`, `Primary IPv4 (web-2) 0.54`); correct
  web-1 `15.37 → ~9.17` (cx33 = €8.49) and its `160 GB` spec → `80 GB`; correct the registry
  row `CX33 / 9.17 → CX23 / ~5.93`.
- **FR6** — Refresh `knowledge-base/finance/cost-model.md` Product COGS, which omits web-2,
  registry, and inngest (~$50/mo of active rows).
- **FR7** — Close #6538 and #6463 referencing this PR and the brainstorm's decision record.

## Technical Requirements

- **TR1 — Guarded destroy, no `[ack-destroy]` bypass.** Mirror `registry-region-migrate`'s
  shape: a `workflow_dispatch` menu-ack target whose gate asserts from the **saved plan JSON**
  that `out_of_scope == 0` against an exact-equality allow-set of web-2's own addresses.
  Authorization is the menu-ack dispatch, never a commit trailer
  (`hr-menu-option-ack-not-prod-write-auth`).
- **TR2 — web-1 must be provably untouched.** The gate must assert **zero** create/update/
  destroy actions on any `web["web-1"]` address, any volume other than
  `workspaces["web-2"]`, and any secret. Reuse the sourced-gate-lib pattern
  (`tests/scripts/lib/*-gate.sh` sourced by BOTH CI and its test, *"so the CI decision logic
  is the SAME bytes the test exercises"*).
- **TR3 — Fail-closed.** An unreadable token or unparseable plan aborts. No green-on-unknown.
- **TR4 — Volume destroy is intentional here.** Unlike `web-2-recreate`'s AC15 (data volume
  **0-destroy**), this path **must** permit exactly one destroy of
  `hcloud_volume.workspaces["web-2"]` — justified because the volume is verified empty and
  holds host-local derived state (ADR-068 §1: worktrees are host-local; GitHub is the durable
  rehydration source). The gate must assert the destroy set contains **only** that volume.
- **TR5 — Tests before implementation** (`cq-write-failing-tests-before`): a
  `test-web2-retire-gate.sh` exercising the same gate lib, with fixtures for the happy path,
  an out-of-scope web-1 touch, and a stray-volume destroy. Fixtures synthesized, not captured
  from prod (`cq-test-fixtures-synthesized-only`).
- **TR6 — Cite content anchors, not line numbers**, in all comments/PR prose
  (`cq-cite-content-anchor-not-line-number`).
- **TR7 — Post-destroy verification, self-pulled.** Confirm via the Hetzner API that the
  server + volume are gone and the fleet is 4/5; confirm no new `SOLEUR_*` error markers in
  Better Stack. Do not ask the operator to check a dashboard
  (`hr-no-dashboard-eyeball-pull-data-yourself`).
- **TR8 — Record the expense change before PR-ready**
  (`wg-record-recurring-vendor-expense-before-ready`).

## Acceptance Criteria

- **AC1** — `var.web_hosts` contains only `web-1`; `terraform validate` + `fmt` clean.
- **AC2** — The destroy gate rejects a plan touching web-1, and rejects a plan destroying any
  volume other than `workspaces["web-2"]` (proven by tests, not by inspection).
- **AC3** — Live Hetzner API shows `soleur-web-2` and `soleur-web-platform-data-web-2` absent;
  server count = 4.
- **AC4** — `git grep -n 'web-2\|web\["web-2"\]' apps/web-platform/infra .github/workflows`
  returns only historical/learning prose, no live wiring.
- **AC5** — Art. 30 register and `compliance-posture.md` contain no stale web-2 claim.
- **AC6** — `expenses.md` matches the live fleet; `cost-model.md` Product COGS reconciled.
- **AC7** — web-1 remains `running` and serving throughout; no reboot, no resize.
- **AC8** — #6538 and #6463 closed with the decision recorded.

## Deferred (file as issues)

- **D1** — `web_spread` is empty and unreachable-by-design while `placement-group.tf` claims it
  *"guarantees the web hosts land on DIFFERENT physical servers."* After retiring web-2 it has
  **zero possible members, ever**. Config advertising HA that cannot engage — same class as
  ADR-068's "routing lie". €0 to fix (placement groups are free); correctness/docs defect.
- **D2** — `git-data` is pinned to `cax11`, orderable in 0 of 3 EU DCs, and is the root blocker
  of ADR-068 §(c) → active-active. Needs a server-type decision that revisits the
  *"git/sshd are ARM-native"* rationale. **This is the next brainstorm.**
- **D3** — Feed `fleet-sku-orderability-audit` (assert every IaC-pinned `server_type` is
  *orderable* in its pinned location) into #6460.
