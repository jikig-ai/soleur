---
title: Multi-owner workspaces and the organizations.owner_user_id primary-owner pointer
status: accepted
date: 2026-06-30
amends: [ADR-044]
related_adrs: [ADR-038, ADR-044]
related: [5756, 5733, 4520]
related_plans:
  - knowledge-base/project/plans/2026-06-30-feat-multi-owner-ownership-rpcs-reconcile-plan.md
related_specs:
  - knowledge-base/project/specs/feat-one-shot-5756-multi-owner-ownership-rpcs/tasks.md
brand_survival_threshold: single-user incident
---

# ADR-073: Multi-owner workspaces and the `organizations.owner_user_id` primary-owner pointer

## Context

ADR-038 introduced team workspaces (`organizations` + `workspaces` + `workspace_members`) and stated workspaces "may have MULTIPLE Owners." Migration `075` (#4520), however, asserted a **single-owner-strict** model in code and in the live `COMMENT ON FUNCTION` metadata of the ownership RPCs ("Single-owner strict: exactly one owner per workspace at all times"), and its `update_workspace_member_role` raised on any direct promotion to owner. The recorded architecture therefore **contradicted itself**: ADR-038 said N owners, mig 075 said exactly one.

Under #5733 the founder ruled that **workspaces support N co-owners by design**. ADR-044's 2026-06-30 amendment ("Owner model note — supersedes #4520, dedicated ADR to follow") recorded the direction but explicitly deferred the decision-of-record to a dedicated ADR. This is that ADR.

Premise validation against HEAD of `apps/web-platform` found the **functional multi-owner capability already exists end-to-end and is product-reachable** — so reconciling the RPCs is largely a consistency fix, not a behavior change:

- The DB **already permits N owners**: `workspace_members.role IN ('owner','member')` with **no** UNIQUE/CHECK/EXCLUDE constraint on owner rows and **no** `workspaces.owner_user_id` column.
- The **invite-as-owner grant path is LIVE**: the invite-member modal's owner/member radio → `POST /api/workspace/invite-member` (accepts `role:"owner"`) → `create_workspace_invitation(p_role)` → `accept_workspace_invitation` inserts a `workspace_members` row with the invitation's role.
- `update_workspace_member_role` (current def = **migration 094**, 4-arg, `service_role`-only, no live route) was rebased on mig 067 and **silently dropped the mig-075 "direct promotion to owner is not allowed" block** — HEAD already permits `member→owner` promotion. Its retained `count(owner) <= 1` "cannot demote the last owner" guard (094:227-233) is exactly the correct at-least-one-owner invariant.
- `transfer_workspace_ownership` (current def = **migration 092**, 4-arg, `service_role`-only) is a promote-then-demote **hand-off-and-step-down** and is multi-owner-safe (promote-before-demote never violates at-least-one-owner). It is the **only** ownership RPC that dual-writes `organizations.owner_user_id` (092:145-147).

The residual inconsistencies (the actual work of #5756): (a) the migration corpus + live DB `COMMENT ON FUNCTION` metadata still assert "Single-owner strict"; (b) there was no dedicated ADR (only an ADR-044 amendment); (c) the meaning of `organizations.owner_user_id` under N owners is **undefined** — it is a single-valued FK (mig 053, `ON DELETE SET NULL` since mig 065) with **live consumers** (`workspace-resolver.ts`, `dsar-export.ts`, `account-delete.ts`) that is dual-written by `transfer` but **not** by the promotion / invite-as-owner grant paths. Defining that column's meaning IS the real architecture decision this ADR records.

## Considered Options

The chosen option — **Option A: pin the multi-owner model as decision-of-record, make NO RPC behavior change, define `organizations.owner_user_id` as the single primary/billing/DSAR pointer (one of N owners), and lock the invariant + grants in a runtime verify sentinel** (reconciling only the live `COMMENT ON FUNCTION` metadata via migration 117 so the recorded architecture stops lying; deferring any *data* reconciliation to a tracked follow-up) — is detailed in **## Decision** below. The rejected and deferred alternatives are enumerated once in **## Alternatives Considered** (which also folds in two options not worth a separate paragraph: stop `transfer` auto-demoting the caller, and re-emit function bodies via `CREATE OR REPLACE`).

## Decision

Adopt **Option A**. This ADR is the dedicated decision-of-record. **No RPC behavior changes.**

1. **Workspaces support ≥1 owner.** Ownership is recorded ONLY as `workspace_members(role='owner')` rows. There is **no** UNIQUE/CHECK/EXCLUDE single-owner constraint and **no** `workspaces.owner_user_id` column (the canary, per ADR-038 N2 / BR-WS-4: a solo workspace's owner is the self-row `user_id == workspace_id`).

2. **Sanctioned additive grant paths for a co-owner:**
   - **invite-as-owner** (LIVE, product-reachable) — the canonical co-owner grant path: `create_workspace_invitation(p_role='owner')` → `accept_workspace_invitation`.
   - **`update_workspace_member_role(p_new_role='owner')`** — the RPC promotion primitive (mig 094, 4-arg, `service_role`-only, no live route today; defense-in-depth). Direct `member→owner` promotion is **permitted** (the mig-075 block is gone).

3. **`transfer_workspace_ownership` is an atomic hand-off-and-step-down**, NOT the only owner path and NOT a single-owner enforcer: it promotes the target to owner and demotes the caller to member in one transaction (promote-before-demote keeps at-least-one-owner intact). It is the **primary-pointer** transfer (see point 4).

4. **`organizations.owner_user_id` = the single primary/billing/DSAR owner pointer** — one designated owner among the N co-owners. It is maintained by `transfer_workspace_ownership` (which re-points it to the new primary owner). Co-owners added via promotion or invite-as-owner are full `workspace_members` owners but do **NOT** change the pointer. **This divergence is intentional, not accidental**: the pointer names the billing/DSAR-of-record owner, while the owner *set* lives in `workspace_members`. (Whether to backfill or migrate to a junction table is the deferred follow-up — see Alternatives / Sequencing.)

5. **Three paths touch the `owner_user_id` question, exactly TWO of which write the pointer (deepen-verified):**
   - **(i) `transfer_workspace_ownership` — WRITES** (mig 092:145-147) — dual-writes the pointer to the new owner, promote-before-demote.
   - **(ii) `anonymise_organization_membership` — WRITES** (mig 081:52-75, the account-self-delete / Art-17 path) — re-points the pointer to the **oldest remaining member** (`ORDER BY m.created_at ASC LIMIT 1`) **and promotes that member to owner**. This is an N-owner **wart**: it can mint a brand-new owner on a workspace that already had co-owners instead of preferring an existing co-owner. Acceptable for now (the departing user *is* the pointer-of-record owner, and the path is erasure, not routine promotion); promoted to a Phase-6 re-eval trigger if it ever surfaces a wrong primary owner via DSAR/billing.
   - **(iii) the promotion + invite-as-owner paths — DELIBERATELY DO NOT WRITE the pointer** — by design (point 4): they add full `workspace_members` owners but leave the primary pointer unchanged.

6. **Derived invariant (stated explicitly): `owner_user_id` references a *current* owner (or NULL for a true orphan) because every *product-reachable* writer maintains it.** This holds today ONLY because the one path that could strand the pointer at a non-owner — a `update_workspace_member_role` demote of the pointed-to owner — is `service_role`-only with **no live route**. **Naming this makes the breakage trigger explicit:** exposing a product-reachable owner-demote / owner-removal route that can target the pointer's owner promotes the deferred Phase-6 data reconciliation from *deferred* to *required*.

7. **Consumer-tolerance contract:** consumers of `organizations.owner_user_id` (`workspace-resolver.ts`, `dsar-export.ts`, `account-delete.ts`) MUST tolerate the pointer referencing a non-owner / non-member and MUST NOT assume it names an active owner. They read it as a best-effort primary-owner hint, not an authorization fact.

8. **The at-least-one-owner invariant is the ONLY ownership-cardinality rule.** It is enforced by the retained mig-094 guard (`count(owner) <= 1` → "cannot demote the last owner"). A workspace must always have ≥1 owner; there is no upper bound.

### Known limitations / carve-outs to record

- **`transfer_workspace_ownership` rejects a target that is already an owner** (092:104-107). This is a multi-owner wart: it means **there is no RPC to re-point a stranded `owner_user_id` to a surviving co-owner**. Combined with point 6, this produces the **demote→remove no-repoint dead-end**: demote the pointer's owner (→ stale pointer to a non-owner) then remove them (→ fully orphaned pointer), and `transfer` cannot re-point to a surviving co-owner because they are already an owner. No product-reachable route hits this today (demote is `service_role`-only), which is why the derived invariant in point 6 still holds — but it is the precise dead-end the Phase-6 follow-up must resolve if a demote route is ever exposed.
- **`remove_workspace_member` blocks removing *any* owner** (mig 094:115-118 — "cannot remove another owner; only members can be removed"). So the **demote-allows-N-1** (`update_workspace_member_role` lets you demote an owner while ≥2 remain) vs **remove-blocks-all-owners** asymmetry is **intentional**: removal is the harder, ledger-writing operation and is owner-protected; demotion is the softer role change guarded only by at-least-one-owner.

## Consequences

- The recorded architecture stops contradicting the running system (ADR-038-vs-mig-075 resolved; see Framing).
- Migration 117 corrects the live `COMMENT ON FUNCTION` metadata on `transfer_workspace_ownership` + `update_workspace_member_role`; verify/117 locks the durable invariants (no single-owner constraint; the at-least-one-owner guard's presence pinned to the 4-arg signature; `service_role`-only grants on the four owner-granting RPCs; the 3-arg overload stays dropped).
- `organizations.owner_user_id` divergence (pointer vs owner-set) is now **documented as intentional**; the data reconciliation question is tracked, not silently widened into this change.
- No new access vector: multi-owner access to a workspace's repo + derived KB already exists and is intended (ADR-044 / mig 058 attestation consent-of-record, unchanged).

## NFR Impacts

- **Tenant isolation:** unchanged. The verify/117 sentinel *strengthens* the durability of the `service_role`-only grant lock on the four owner-granting RPCs (`update_workspace_member_role`, `create_workspace_invitation`, `accept_workspace_invitation`, and — already locked by verify/092 — `transfer_workspace_ownership`), guarding the #4762 forgeable-override tenant-takeover class against a future migration flipping a grant to `authenticated`.

## Principle Alignment

- **Single source of truth:** the owner *set* is `workspace_members(role='owner')`; `owner_user_id` is explicitly a *pointer* (a derived/designated value), not a second source of truth for "who are the owners." Documenting this prevents the dual-ownership divergence trap.
- **Least privilege:** the owner-granting RPCs stay `service_role`-only; the verify sentinel makes that non-regressable.
- **Deviation from mig-075's single-owner-strict assertion:** documented and superseded here (Framing).

## Framing / Supersession

ADR-073 **resolves the pre-existing ADR-038 (multi-owner) vs migration-075/#4520 (single-owner-strict) contradiction** — it is a clarification *consistent with* ADR-038, not a reversal of it — and **supersedes the single-owner-strict assertion of #4520 / migration 075**. It also concretises the ADR-044 2026-06-30 "Owner model note" deferral (the "dedicated ADR to follow").

## C4

One-line citation refresh only — **no structural / topology edit**. `model.c4:9` (the `founder` actor) already states "Workspaces may have MULTIPLE Owners (ADR-038 team workspaces)"; the citation is refreshed to `(ADR-038, ADR-073)` for cross-link consistency with `domain-model.md` BR-WS-3 and the ADR-044 amendment. Cardinality ("at-least-one-owner") and column semantics ("primary pointer") are domain rules belonging in `domain-model.md` (BR-WS-3/BR-WS-4), not in a C4 actor description — placing them in `model.c4` would be a category error.

## Alternatives Considered

| Alternative | Verdict | Rationale |
|---|---|---|
| Net-new `grant_workspace_co_owner` RPC | Rejected | Redundant with invite-as-owner (live) + mig-094 promotion. |
| Stop `transfer` auto-demoting the caller | Rejected | That is "add a co-owner," already covered by invite/promotion; `transfer` = deliberate hand-off-and-step-down. |
| `UNIQUE(workspace_id) WHERE role='owner'` | Rejected | Contradicts N-co-owners; breaks live invite-as-owner + 2-owner rows. |
| Re-emit function bodies via `CREATE OR REPLACE` to fix inline header comments | Rejected | Headers are immutable history; only live `COMMENT ON FUNCTION` metadata needs fixing; re-emit risks the 092/094 `COALESCE` + `service_role`-only FORWARD-REFERENCE guards. |
| Reconcile `organizations.owner_user_id` data now (backfill / junction) | Deferred (follow-up #5756-followup) | The *decision* belongs here; the *data* change is gated on this ADR and on a re-eval trigger (demote route exposed; mig-081 wrong-primary; DSAR/billing needs an owner set). |
| ADR-only, no migration/verify | Rejected | Leaves the live COMMENT lying + no runtime lock against re-introduction. |

## Sequencing

The decision is **already true** of the running system, so ADR-073 ships `status: accepted` immediately — no soak gate. The deferred `owner_user_id` data reconciliation is tracked as a follow-up issue and is gated on this ADR plus a concrete re-eval trigger (see Decision points 5-6 and the follow-up issue).
