---
title: "feat(workspace): reconcile single-owner ownership RPCs to the multi-owner-by-design model + dedicated ADR"
type: feature
issue: 5756
branch: feat-one-shot-5756-multi-owner-ownership-rpcs
date: 2026-06-30
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_adrs: [ADR-038, ADR-044]
related_prs_context: [4520, 5733]
status: draft
---

# feat(workspace): reconcile single-owner ownership RPCs to the multi-owner-by-design model + dedicated ADR

## Enhancement Summary

**Deepened:** 2026-06-30 · **Agents (all 5 returned):** data-integrity-guardian, security-sentinel, architecture-strategist, code-simplicity-reviewer, verify-the-negative (Explore/sonnet).

**Premise verification:** all 10 negative-verification claims CONFIRMED against the codebase (no `workspaces.owner_user_id` column; no single-owner constraint; mig 094 dropped the promotion block; at-least-one-owner guard at 094:227-233; only `transfer` writes `organizations.owner_user_id` among the RPCs; invite-route owner-gate fires before role; no existing single-owner verify sentinel; 117/ADR-072 free; `COMMENT ON FUNCTION public.` precedent in 20+ migrations).

**Folded in:**
1. **verify/117 grant-lock widened** (security, HIGH): invite-as-owner is the *canonical* grant path but `create_workspace_invitation` + `accept_workspace_invitation` have **no** verify sentinel today — both are forgeable-override `service_role`-only RPCs. Lock their grants in verify/117 + add the **3-arg `update_workspace_member_role` drop-check** (symmetry with verify/092 check 3).
2. **Exact constraint-absence query** (data-integrity): check 1 targets a **partial UNIQUE index** + an **EXCLUDE constraint** (NOT a plain CHECK — row-local, can't enforce cross-row cardinality). Trigger-vector + message-text-proxy limits noted in the sentinel header.
3. **Third `owner_user_id` writer surfaced** (architecture, MEDIUM): `anonymise_organization_membership` (mig 081) also re-points `owner_user_id` AND promotes the **oldest remaining MEMBER** to owner (not a preferred existing co-owner) — an N-owner wart. Added to ADR-072 inventory + carve-outs + the Phase-6 trigger.
4. **Derived invariant + consumer contract** (architecture + data-integrity): ADR-072 states "`owner_user_id` references a *current* owner because every product-reachable writer maintains it"; names "a product-reachable owner-demote/remove-of-the-pointer-target route" as the explicit Phase-6 breakage trigger; records the **demote→remove strands the pointer with no repoint primitive** dead-end (transfer rejects an already-owner target, 092:104-107). Consumers MUST tolerate the pointer referencing a non-owner/non-member.
5. **Phase 0 risk downgrade** (data-integrity): 092:193 + 094:278 already `COMMENT ON FUNCTION` these exact functions and apply green — apply-role risk near-zero. Capture the **verbatim** current COMMENT strings (092's is a multi-line adjacent-string concatenation with no inserted space) for `.down.sql`.
6. **C4: one-line citation refresh** (architecture, MINOR): `model.c4:9` cites only ADR-038 for "MULTIPLE Owners" → refresh to `(ADR-038, ADR-072)`. Citation only, no topology edit; re-run c4 tests.
7. **Simplicity trims:** verify check 4 (comment prose) kept but explicitly **secondary/droppable**; the 094 grant-lock lives in 117 while `transfer`'s lock stays in verify/092 (no duplication); default to **extending** an existing ownership test; **name** the negative-test fixture so the sentinel's non-no-op proof isn't skipped.
8. **Framing** (architecture): ADR-072 resolves the pre-existing **ADR-038 (multi-owner) vs mig-075 (single-owner-strict) contradiction**, not merely "supersedes 075."

> ✨ **Headline:** Promote the ADR-044 2026-06-30 *amendment* ("workspaces support N co-owners by design") into a **dedicated decision-of-record (ADR-072)** that ALSO pins the undefined `organizations.owner_user_id` meaning under N owners, and reconcile the **stale single-owner-strict assertions** that still live in the ownership-RPC migration corpus — so the recorded architecture stops lying about a model the running system already implements.

## Overview

Issue #5756 asks us to "reconcile the single-owner ownership RPCs to the multi-owner-by-design model + write a dedicated ADR." The founder confirmed (under #5733) that **workspaces support N co-owners by design**, superseding the single-owner-strict model asserted in migration `075` (#4520).

Premise validation found that the **functional multi-owner capability already exists end-to-end and is product-reachable today** — so the RPC-comment reconciliation is largely a consistency fix. But the engineering CTO review surfaced the **deeper, undefined reconciliation surface**: `organizations.owner_user_id` (a single-valued FK, mig 053) is dual-written by `transfer_workspace_ownership` but **not** by the promotion / invite-as-owner grant paths, so under N owners it silently means "whichever single owner last ran transfer / created the org" — and it has live consumers (workspace-resolver, DSAR export, account-delete). **Defining that column's meaning IS the real architecture decision** ADR-072 must record, beyond promoting the amendment.

Verified facts (HEAD of `apps/web-platform`):

- The **invite-as-owner grant path is LIVE + product-reachable**: `components/settings/invite-member-modal.tsx` owner/member radio → `POST /api/workspace/invite-member` (accepts `role:"owner"`) → `createWorkspaceInvitation` → RPC `create_workspace_invitation(p_role)` → `accept_workspace_invitation` inserts `workspace_members` with the invitation's role.
- The DB **already permits N owners**: `workspace_members.role IN ('owner','member')`, **no** UNIQUE/CHECK on owner rows, **no** `workspaces.owner_user_id` column.
- `update_workspace_member_role` (current def = **migration 094**, 4-arg, `service_role`-only, no live route) was rebased on mig 067 and **silently dropped the mig-075 "direct promotion to owner is not allowed" block** — HEAD already permits `member→owner` promotion. Its retained "cannot demote the last owner" guard (`count(owner) <= 1`, mig 094:227-233) is *exactly* the correct at-least-one-owner invariant.
- `transfer_workspace_ownership` (current def = **migration 092**, 4-arg, `service_role`-only) is promote-then-demote **hand-off-and-step-down**, multi-owner-safe (promote-before-demote never violates at-least-one-owner). It **dual-writes `organizations.owner_user_id`** (mig 092:145-147); the promotion + invite paths do not.
- Downstream artifacts are **already** multi-owner-aware: ADR-044's 2026-06-30 amendment records the direction; `domain-model.md` rule **BR-WS-3** documents N co-owners + cites #5756; the C4 `founder` actor (`model.c4:9`) already says "Workspaces may have MULTIPLE Owners."

**What is still inconsistent** (the actual work): (a) the migration corpus + live DB `COMMENT ON FUNCTION` metadata still assert "Single-owner strict: exactly one owner per workspace at all times"; (b) there is **no dedicated ADR** (only an amendment buried in ADR-044) and **`organizations.owner_user_id`'s meaning under N owners is undefined**; (c) there is **no runtime sentinel** locking the at-least-one-owner invariant + `service_role`-only grants so a future migration cannot silently re-introduce single-owner enforcement or flip a grant.

**Decision (this plan):** make **NO behavior change to any RPC**. Deliver: (1) **ADR-072** as the standalone decision-of-record — supersede single-owner-strict **and pin `organizations.owner_user_id` semantics** (primary/billing/DSAR-owner pointer) under N owners; (2) **migration 117** = `COMMENT ON FUNCTION` corrections only; (3) **verify/117** locking the at-least-one-owner guard presence + `service_role`-only grants (durable) + corrected comment (secondary); (4) a **test** proving two `owner` rows coexist, `member→owner` promotion succeeds, and last-owner demote raises; (5) cross-link `domain-model.md` BR-WS-3 + the ADR-044 amendment → ADR-072. **Deferred (follow-up issue, gated on the ADR decision):** any *data* reconciliation of `organizations.owner_user_id` (backfill / junction table) — out of scope here.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Codebase reality (HEAD) | Plan response |
|---|---|---|
| `update_workspace_member_role` (mig **075:206-210**) raises on any direct promotion to owner | Current def is **migration 094** (4-arg, `service_role`-only). 094 rebased on mig 067 and **dropped** the 075 owner-promotion block. HEAD **permits** `member→owner` promotion. | Document in ADR-072 that direct promotion is *permitted* (the additive co-owner primitive). No code change. Verify sentinel asserts the 094 4-arg shape + grant + guard unchanged. |
| "a second owner cannot be added via the supported API today" | **False.** Invite-as-owner is live end-to-end. | Confirm invite-as-owner as the **sanctioned, product-reachable** grant path (scope item 3). Documented in ADR-072; no new RPC. |
| "cannot demote the last owner" guard at **075:217-222** | Guard now at **mig 094:227-233** (`count(owner) <= 1`). Correct at-least-one-owner invariant for N owners. | **Keep verbatim.** verify/117 locks its *presence*. Re-confirmed in ADR-072 as the retained invariant. |
| `transfer_workspace_ownership` lives at mig 075 | Current def is **migration 092** (4-arg `service_role`-only); 075's 3-arg form DROPped. | Target 092's COMMENT in mig 117. Preserve 092 `COALESCE` + `service_role`-only invariants — do NOT re-emit the body. |
| Single-owner verify sentinels "if any assert single-owner" | **No** verify sentinel asserts single-owner (grep of `supabase/verify/` found none). | Nothing to remove. **Add** verify/117 to *lock* the multi-owner invariant. |
| (not in issue) `organizations.owner_user_id` is the single-owner pointer | Single-valued FK (mig 053:51, `SET NULL` since 065). **Three writers:** `transfer` dual-writes (092:145-147); `anonymise_organization_membership` (mig 081:52-75) re-points + promotes oldest member; promotion + invite-as-owner do **not** touch it. Consumers: `workspace-resolver.ts:298,491-516`, `dsar-export.ts:975`, `account-delete.ts:708-741`. | **ADR-072 DECIDES its meaning** (primary/billing/DSAR pointer) + states the derived "references-a-current-owner" invariant + consumer-tolerance contract + the mig-081 promote-oldest wart. Any *data* backfill/junction = deferred follow-up (Phase 6), gated on the ADR. |
| "business-rules register will document the rule — link when filed" | **Already filed:** `domain-model.md` BR-WS-3. | Update BR-WS-3 source cite → ADR-072. |

**Premise Validation note:** #5756 is **OPEN**. Migration `075` exists but its function defs are **superseded by 092/094** (issue's line citations are 075-era). ADR-044 amendment + mig 058 invite/attestation flow exist + live. #5733 is **CONTEXT only** (its open work is the git-strand/owner-canary investigation — NOT a co-target). The premise "single-owner is still enforced" is **partially stale**; the plan reframes accordingly.

## User-Brand Impact

**If this lands broken, the user experiences:** a malformed migration-117 `COMMENT ON FUNCTION` or an over-eager verify/117 sentinel **fails the CI verify-migrations gate**, blocking the `apps/web-platform` deploy — caught pre-merge. The insidious failure: an ADR or sentinel that *mis-states the at-least-one-owner invariant* could let a future migration re-introduce a last-owner-demote path that **administratively locks a founder out of their own workspace** (every owner-gated RPC returns 42501), or a sentinel that fails to lock the `service_role`-only grant could let a future migration flip a forgeable-override RPC to `authenticated` (the #4762 **forged co-owner / tenant-takeover** class).

**If this leaks, the user's data/workflow is exposed via:** N/A for new exposure — this plan adds **no new access vector**. Multi-owner access to a workspace's connected repo + derived KB **already exists and is intended** (ADR-044 / mig 058 attestation consent-of-record, unchanged).

**Brand-survival threshold:** `single-user incident` — the artifacts govern the ownership/access invariant (administrative lockout + forged-co-owner are per-user catastrophes). `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review-time.

## Implementation Phases

### Phase 0 — Preconditions
- Confirm next migration index = **117** (`ls apps/web-platform/supabase/migrations/ | grep -oE '^[0-9]+' | sort -n | tail -1` → 116) and next ADR = **ADR-072** (`...decisions/ | grep -oE 'ADR-[0-9]+' | sort -u | tail -1` → ADR-071).
- `git rev-parse origin/main:apps/web-platform/supabase/migrations/092_transfer_ownership_caller_override.sql` exists.
- **`COMMENT ON FUNCTION` apply-role — risk near-zero (deepen-verified).** Migrations **092:193** and **094:278** already `COMMENT ON FUNCTION` these exact two functions and apply green today; the apply role *created* them (092:48, 094:184) and no later `ALTER FUNCTION ... OWNER` exists — ownership is guaranteed. The probe stays as a cheap precondition (`git grep -n 'COMMENT ON FUNCTION public' apps/web-platform/supabase/migrations/` → 20+ hits), but the **fallback** (ADR-072 + inline migration prose, drop the structured `COMMENT ON FUNCTION`) is unlikely to be needed. Do NOT fall back to a `CREATE OR REPLACE` re-emit (would risk the 092/094 `COALESCE` + `service_role`-only FORWARD-REFERENCE invariants).
- **Capture the verbatim current COMMENT strings** for `.down.sql`: read `obj_description` source at **092:193-198** and **094:278-283**. Note 092's COMMENT is a **multi-line adjacent-string-literal concatenation** (`'…organizations.'` + `'owner_user_id,…'` → `organizations.owner_user_id`, NO inserted space); the down need not split lines identically but MUST reproduce the same final string value. No apostrophes inside either comment → no escaping pitfalls.
- Read-only research the `organizations.owner_user_id` consumers (`workspace-resolver.ts:298,491-516`, `dsar-export-allowlist.ts:218`, `dsar-export.ts:975`, `account-delete.ts:708-741`) AND the THREE writers — `transfer_workspace_ownership` (092:145-147), `anonymise_organization_membership` (**mig 081:52-75**, re-points + promotes oldest member), and (none in promotion/invite) — to ground the ADR's pointer-semantics decision. **No edits to these in this PR.**

### Phase 1 — ADR-072 (the headline deliverable)
Author `knowledge-base/engineering/architecture/decisions/ADR-072-workspaces-support-n-co-owners.md` via `soleur:architecture` create (fires the ADR→register wiring). Recommended title: **"Multi-owner workspaces and the `organizations.owner_user_id` primary-owner pointer."** Frontmatter modelled on ADR-044 (`adr`, `title`, `status: accepted`, `date`, `amends: [ADR-038, ADR-044]`, `related: [5756, 5733, 4520]`, `related_plans`, `brand_survival_threshold: single-user incident`). Body:
- **Context:** single-owner-strict (mig 075 / #4520) vs founder's N-co-owners ruling (#5733); the ADR-044 amendment; the residual inconsistencies (RPC comments + undefined `owner_user_id`).
- **Decision:**
  - Workspaces support **≥1 owner**; ownership recorded ONLY as `workspace_members(role='owner')` rows; no UNIQUE/CHECK single-owner constraint.
  - **Sanctioned additive grant path** = invite-as-owner (live) + `update_workspace_member_role(p_new_role='owner')` (RPC primitive, `service_role`-only, no live route — defense-in-depth).
  - **`transfer_workspace_ownership`** = atomic **hand-off-and-step-down** (the *primary-pointer* transfer), NOT the only owner path.
  - **`organizations.owner_user_id`** = the **single primary/billing/DSAR owner pointer** (one of N co-owners), maintained by `transfer`; co-owners added via promotion/invite are full `workspace_members` owners but do NOT change the pointer. State this explicitly so the divergence is **intentional**, not accidental. (Whether to backfill / migrate to a junction is a **deferred** follow-up — see Alternatives.)
  - **Three writers of `owner_user_id`** (the complete inventory — deepen-verified): (i) `transfer_workspace_ownership` (092:145-147) dual-writes it promote-before-demote; (ii) `anonymise_organization_membership` (**mig 081:52-75**, account-self-delete path) re-points it to the **oldest remaining MEMBER and promotes that member to owner** (`ORDER BY m.created_at ASC LIMIT 1`) — an N-owner **wart**: it can mint a brand-new owner on a workspace that already had co-owners instead of preferring an existing one; (iii) the promotion + invite-as-owner paths do NOT touch it. ADR-072 must enumerate all three and rule on the mig-081 promote-oldest-member behavior under N owners (acceptable for now / Phase-6 trigger).
  - **Derived invariant (state it explicitly):** "`owner_user_id` references a *current* owner (or NULL for a true orphan) because every **product-reachable** writer maintains it." This holds today *only* because the one path that could strand it at a non-owner — `update_workspace_member_role` demote — is `service_role`-only with no live route. **Naming this makes the breakage trigger explicit:** exposing a product-reachable owner-demote / owner-removal-of-the-pointer-target route promotes the Phase-6 data reconciliation from deferred to required.
  - **Consumer-side contract:** consumers (`workspace-resolver.ts`, `dsar-export.ts:975`, `account-delete.ts:741`) MUST tolerate `owner_user_id` referencing a non-owner / non-member and MUST NOT assume it is an active owner.
  - **At-least-one-owner invariant** (the retained mig-094 guard) — the ONLY ownership-cardinality rule.
  - **Known limitations to record** (carve-outs): `transfer` rejects a target already an owner (092:104-107) — a multi-owner wart that also means **there is no RPC to re-point a stranded `owner_user_id` to a surviving co-owner** (the dead-end above); `remove_workspace_member` rejects removing *any* owner (094:115-118) so the demote-allows-N-1 vs remove-blocks-all asymmetry is intentional.
- **C4 note:** one-line citation refresh on `model.c4:9` (ADR-038 → ADR-038, ADR-072); no structural/topology edit (see Architecture Decision section).
- **Framing / Supersession:** ADR-072 **resolves the pre-existing ADR-038 (multi-owner) vs migration-075/#4520 (single-owner-strict) contradiction** — it is a clarification consistent with ADR-038, not a reversal — and supersedes the single-owner-strict assertion of #4520 / mig 075.

### Phase 2 — migration 117 (COMMENT-only; CONTRACT phase — before the test phase)
`apps/web-platform/supabase/migrations/117_reconcile_ownership_rpc_comments_multi_owner.sql`:
- Header prose: multi-owner reconciliation + ADR-072 reference.
- `COMMENT ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text, uuid)` — replace "Single-owner strict: ..." with hand-off-and-step-down + primary-pointer wording; cite ADR-072 / #5756.
- `COMMENT ON FUNCTION public.update_workspace_member_role(uuid, uuid, text, uuid)` — state `member→owner` promotion is permitted (additive co-owner primitive) and the retained guard is the at-least-one-owner invariant; cite ADR-072.
- **No `CREATE OR REPLACE`, no grant change, no behavior change.**
- `117_*.down.sql`: restore the prior COMMENT strings **verbatim** (the values captured in Phase 0; reproduce 092's concatenated final value exactly). Header note: down + verify/117 are **version-paired** (rolling back 117 re-installs the "single-owner strict" COMMENT, which would red verify/117 check 4 if the sentinel stayed applied — fine because the Supabase pipeline is forward-only and down files are manual-rollback artifacts).

### Phase 3 — verify/117 sentinel (lock the DURABLE invariant)
`apps/web-platform/supabase/verify/117_reconcile_ownership_rpc_comments_multi_owner.sql` (contract: each row returns `check_name` + `bad`; any `bad>0` fails CI). Assert **signature + grant + guard presence**, not just comment prose. **Sentinel header MUST note two known limits:** (a) a single-owner rule re-introduced via a *trigger* (not constraint/index) is invisible to check 1 — check 2 is the durable behavioral backstop; (b) check 2's ILIKE on the RAISE *message* is a proxy for the `count(*) <= 1` predicate — a future migration could keep the message while neutering the condition.
1. **No single-owner-enforcing constraint** on `workspace_members`. A plain CHECK is row-local and *cannot* enforce cross-row cardinality — so target the realistic vectors: a **partial UNIQUE index** and an **EXCLUDE/UNIQUE constraint**. `bad=0` when none:
   ```sql
   SELECT 'no_single_owner_unique_index' AS check_name, count(*)::int AS bad
   FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid
   JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname='workspace_members'
     AND i.indisunique
     AND pg_get_expr(i.indpred,i.indrelid) ILIKE '%owner%'
     AND pg_get_indexdef(i.indexrelid) ILIKE '%workspace_id%'
   UNION ALL
   SELECT 'no_single_owner_constraint', count(*)::int
   FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid
   JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname='workspace_members'
     AND con.contype IN ('u','x')
     AND pg_get_constraintdef(con.oid) ILIKE '%owner%';
   ```
2. **At-least-one-owner guard present**, pinned to the 4-arg signature so a stale overload cannot satisfy it: `pg_get_function_identity_arguments = 'p_workspace_id uuid, p_user_id uuid, p_new_role text, p_caller_user_id uuid'` AND `pg_get_functiondef(...) ILIKE '%cannot demote the last owner%'` → `bad=0`.
3. **`service_role`-only grants intact** (the #4762 forge-vector lock) — `has_function_privilege('authenticated', '<sig>', 'EXECUTE')` must be false for **all four owner-granting RPCs**, because the no-forge guarantee rests on every one staying off `authenticated`:
   - `update_workspace_member_role(uuid, uuid, text, uuid)` — **new coverage** (mig 094 has no existing verify sentinel).
   - `create_workspace_invitation(uuid, text, text, text, text, uuid)` — **new coverage**; this is the canonical co-owner grant path and takes a forgeable `p_caller_user_id` (085:344).
   - `accept_workspace_invitation(uuid, uuid)` — **new coverage**.
   - `transfer_workspace_ownership(uuid, uuid, text, uuid)` — already locked by **verify/092**; OPTIONAL belt-and-suspenders re-assert here (don't duplicate if keeping the sentinel minimal).
4. **3-arg drop-check** (symmetry with verify/092 check 3): the old `update_workspace_member_role(uuid, uuid, text)` overload (DROPped at 094:182) must NOT reappear — a recreated 3-arg `authenticated`-granted overload is the same forge-class the 4-arg grant-lock wouldn't catch.
5. (Secondary, **droppable**) `transfer_workspace_ownership` 4-arg COMMENT NOT ILIKE `%single-owner strict%` — couples to migration 117's exact string; keep only as a low-value confirmation that the migration ran, or drop to decouple the sentinel from the migration.

### Phase 4 — test (prove the invariant; AFTER the contract migration)
First **`git grep -l "two owner\|role='owner'.*owner\|coexist" apps/web-platform/test/`** + read `workspace-invitations-accept.integration.test.ts` to confirm two-owner coexistence is not already characterized (avoid a duplicate). **Default: extend an existing ownership test, don't add a new file.** **Verify runner + path against `apps/web-platform/vitest.config.ts` include globs** (`test/**/*.test.ts`) before fixing the path; run `cd apps/web-platform && ./node_modules/.bin/vitest run <path>` (NOT `npm run -w`). Existing `transfer-ownership-wrapper.test.ts` is **mocked**; `workspace-invitations-accept.integration.test.ts` is **integration** (live test DB). Pick per convention:
- **Preferred (integration):** seed workspace with owner A + member B; `update_workspace_member_role(p_new_role='owner')` for B; assert **two** `workspace_members(role='owner')` coexist (no raise); demote one of two → SUCCEEDS; demote the sole remaining owner → RAISES "cannot demote the last owner". Document expected `organizations.owner_user_id` behavior when the pointed-to owner is demoted while others remain (stays pinned / no change — per ADR-072 decision).
- **Fallback (mocked wrapper):** assert `updateWorkspaceMemberRole({newRole:'owner'})` forwards `p_new_role:'owner'` + `p_caller_user_id` and does not reject 'owner' at the wrapper guard; the DB invariant is carried by verify/117.
- **Sentinel negative proof (don't skip — names where it lives):** a sentinel that never returns `bad>0` is worthless. Prove verify/117 fires either (a) inline in the integration test by `CREATE UNIQUE INDEX ... WHERE role='owner'` inside a `BEGIN; ...; ROLLBACK;` and asserting check 1 returns `bad>0`, or (b) a committed fixture SQL under `apps/web-platform/test/fixtures/` that re-adds a constraint / flips a grant. Name the chosen location in Files to Create.

### Phase 5 — cross-link the register + amendment + C4 citation
- `knowledge-base/engineering/architecture/domain-model.md` BR-WS-3 source cite → add ADR-072.
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` 2026-06-30 "Owner model note" → replace "dedicated ADR to follow" with the concrete ADR-072 reference.
- `knowledge-base/engineering/architecture/diagrams/model.c4:9` — refresh the `founder` actor's "MULTIPLE Owners" citation from `(ADR-038 team workspaces)` to also cite ADR-072 (citation text only — no element/relationship/topology change). Re-run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Phase 6 — deferred follow-up issue
File a GitHub issue: "reconcile `organizations.owner_user_id` data under N co-owners (backfill or junction)" — gated on ADR-072's pointer-semantics decision. **Re-eval triggers (concrete):** (a) a product-reachable owner-demote or owner-removal-of-the-pointer-target route is exposed → the derived "pointer references a current owner" invariant breaks → reconciliation becomes **required**; (b) the mig-081 promote-oldest-member behavior produces a wrong primary owner that DSAR/billing/account-delete keying surfaces; (c) DSAR/billing correctness requires a non-pointer owner *set*. Label `domain/engineering`, `type/feature`. (A deferral without a tracking issue is invisible.)

## Files to Create
- `knowledge-base/engineering/architecture/decisions/ADR-072-workspaces-support-n-co-owners.md`
- `apps/web-platform/supabase/migrations/117_reconcile_ownership_rpc_comments_multi_owner.sql`
- `apps/web-platform/supabase/migrations/117_reconcile_ownership_rpc_comments_multi_owner.down.sql`
- `apps/web-platform/supabase/verify/117_reconcile_ownership_rpc_comments_multi_owner.sql`
- A test under `apps/web-platform/test/server/` (name/shape per Phase 4) — **default: extend an existing ownership test** (`workspace-invitations-accept.integration.test.ts`) rather than a new file.
- (If chosen per Phase 4) a negative-proof fixture under `apps/web-platform/test/fixtures/` — OR an inline `BEGIN;...ROLLBACK;` block in the test (name the choice).

## Files to Edit
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — amendment links ADR-072.
- `knowledge-base/engineering/architecture/domain-model.md` — BR-WS-3 source cite → ADR-072.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — line 9 `founder` actor citation `(ADR-038)` → `(ADR-038, ADR-072)` (citation text only, no topology change).

## Acceptance Criteria

### Pre-merge (PR)
- [x] `ADR-072-...md` exists, `status: accepted`; `## Decision` names: invite-as-owner grant path, `update_workspace_member_role` promotion primitive, `transfer` hand-off-and-step-down, the at-least-one-owner invariant, **and the `organizations.owner_user_id` primary-pointer meaning under N owners**.
- [x] Migration 117 contains **only** `COMMENT ON FUNCTION` statements: `grep -cE '^\s*(CREATE|ALTER|GRANT|REVOKE|DROP|UPDATE)' 117_*.sql` returns 0 (verified).
- [x] `117_*.down.sql` restores the prior COMMENT text (reversibility) — 092 + 094 strings reproduced verbatim.
- [x] verify/117 locks the `service_role`-only grant on ALL of `update_workspace_member_role` (4-arg), `create_workspace_invitation` (6-arg), `accept_workspace_invitation` (2-arg), AND asserts the 3-arg `update_workspace_member_role` overload does not exist.
- [ ] verify/117 returns `bad=0` for every sentinel on a freshly-migrated DB, and **fails** (`bad>0`) on the named negative fixture — DEFERRED to the release migrate+verify path (no live DB in this env). Negative fixture authored at `test/fixtures/verify-117-single-owner-negative.sql`.
- [x] Multi-owner test: static SQL-shape test green (15/15). Behavioral coexist/promote/demote-last invariants locked by verify/117 at apply-time (not DB-exercised here — no live DB).
- [x] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (exit 0); new test passes via `./node_modules/.bin/vitest run`; `c4-code-syntax.test.ts` + `c4-render.test.ts` green (23/23) after the model.c4 citation refresh.
- [x] ADR-044 amendment + domain-model.md BR-WS-3 + model.c4:9 all cite ADR-072.
- [x] ADR-072 enumerates all THREE `owner_user_id` writers (transfer, mig-081, none-in-promotion/invite), states the derived "references-a-current-owner" invariant + its Phase-6 breakage trigger, and records the demote→remove no-repoint dead-end.
- [x] Deferred `owner_user_id` follow-up issue filed (Phase 6) with re-eval criteria — **#5805**.
- [ ] PR body uses `Closes #5756` — PR not opened by this pipeline phase.
- [ ] CPO sign-off recorded (threshold = single-user incident).

### Post-merge (operator/automation)
- [ ] Migration 117 + verify/117 apply on the `web-platform-release.yml` migrate+verify path (the merge IS the apply). Confirm verify-migrations job green post-deploy via the CI run — no SSH.

## Architecture Decision (ADR/C4)

### ADR
**Create ADR-072** — the dedicated decision-of-record superseding single-owner-strict (#4520 / mig 075) AND pinning `organizations.owner_user_id` semantics under N owners. In-scope Phase 1 deliverable, authored via `soleur:architecture`. Not deferred.

### C4 views
**No structural/topology C4 edit; one-line citation refresh only** (architecture-strategist MINOR). Cardinality invariants ("at-least-one-owner") and column semantics ("primary pointer") are domain rules belonging in `domain-model.md` (BR-WS-3/BR-WS-4), not in a C4 actor description — putting them in `model.c4` would be a category error. Completeness enumeration (read against `model.c4` / `views.c4` / `spec.c4`):
- **External human actors:** only `founder` (`model.c4:8-9`), whose description **already** says "Workspaces may have MULTIPLE Owners (ADR-038 team workspaces)." Structurally correct; but it cites only ADR-038 — refresh the citation to `(ADR-038, ADR-072)` for cross-link consistency with BR-WS-3 + the ADR-044 amendment (Phase 5). Citation text only; no element/relationship change.
- **External systems / vendors:** none introduced.
- **Containers / data-stores:** none added; `workspace_members` + `organizations` are existing tables; no schema change.
- **Actor↔surface access relationships:** Owner-shared reads already modelled (`model.c4:272`); no access-topology change.
The only C4 change is the one-line citation refresh; re-run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing
Decision is **already true** of the running system; ADR-072 ships `status: accepted` immediately — no soak gate.

## Observability

```yaml
liveness_signal:
  what: CI verify-migrations job runs verify/117 sentinels post-migrate
  cadence: every web-platform-release.yml run (merge to main touching apps/web-platform)
  alert_target: GitHub Actions job status; a verify bad>0 blocks deploy
  configured_in: .github/workflows/web-platform-release.yml (migrate+verify steps)
error_reporting:
  destination: CI job log + GitHub checks (verify bad>0 fails the job)
  fail_loud: true
failure_modes:
  - mode: COMMENT ON FUNCTION apply fails (apply-role does not own the function)
    detection: migration 117 step fails in the release migrate job
    alert_route: release workflow red check
  - mode: verify/117 false-positive (constraint/guard query mis-scoped)
    detection: verify-migrations bad>0 on a correct DB
    alert_route: release workflow red check
  - mode: future migration drops the last-owner guard / flips a grant / re-adds single-owner constraint
    detection: verify/117 checks 1-3 flip bad>0 on that migration's deploy
    alert_route: release workflow red check
logs:
  where: GitHub Actions release-workflow logs (migrate + verify steps)
  retention: GitHub Actions default
discoverability_test:
  command: "gh run list --workflow=web-platform-release.yml --limit 1 --json conclusion"
  expected_output: "conclusion: success (verify-migrations green ⇒ verify/117 bad=0 across all sentinels)"
```

Docs + DB-metadata + verify-sentinel change; no new runtime app code path emits at runtime. The discoverability command uses `gh`, not a remote shell.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)
**Status:** reviewed (engineering CTO domain agent).
**Assessment:** "No RPC behavior change" is the correct minimal default — the DB already permits N owners, the invite-as-owner grant path is live, and a net-new `grant_workspace_co_owner` RPC is **redundant**. The real architecture surface the comment-only scope misses is **`organizations.owner_user_id`** — a single-valued FK (mig 053:51) that `transfer_workspace_ownership` dual-writes (092:145-147) but the promotion + invite paths do not, with live consumers in `workspace-resolver.ts`, `dsar-export-allowlist.ts`/`dsar-export.ts`, `account-delete.ts`. Under N owners it silently means "whichever owner last ran transfer." **ADR-072 must DEFINE its meaning** (primary/billing/DSAR pointer); any data backfill/junction is a separate, deferrable change. The COMMENT-only migration is LOW migration-risk (non-locking, instant, reversible) *iff* the apply-role-ownership probe passes. **Verify sentinel must lock the at-least-one-owner guard + `service_role` grants (durable), not comment prose (rots).** Carve-outs to record in the ADR: `transfer` rejects an already-owner target (092:104-105, a multi-owner wart); `remove_workspace_member` blocks removing *any* owner (094:115-116) so the demote-allows-N-1 vs remove-blocks-all asymmetry is intentional. Brand-survival = `single-user incident` (administrative lockout + forged-co-owner). Complexity: small (hours) as scoped; medium only if the ADR chooses to reconcile `owner_user_id` data now (recommend deferring that to a follow-up). No capability gaps.

### Product/UX Gate
**Not applicable.** No file under `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` is created/edited (invite-as-owner UI already exists). Mechanical UI-surface override does not fire. Product tier = NONE.

## Open Code-Review Overlap

Checked 62 open `code-review` issues against the Files-to-Edit paths. Two matched on `supabase/migrations`: **#3221** (ci: nightly cron for env-gated integration tests) and **#3220** (ci: postmerge verification of trigger-bearing migrations in prd). **Disposition: Acknowledge** — both are CI-infrastructure scope-outs for integration-test cadence / trigger-bearing-migration verification; this plan's migration 117 is a non-trigger `COMMENT ON FUNCTION` change and touches no CI cron workflow. Different concern; the scope-outs remain open. No fold-in. (ADR-044, domain-model.md, supabase/verify/ matched nothing.)

## GDPR / Compliance Gate

Touches `.sql` (sensitive surface) → considered. **No new processing activity:** multi-owner access to a workspace's repo/KB is an EXISTING, intended capability (ADR-044), mig-058 `workspace_member_attestations` is the Art. 5(2) consent-of-record — unchanged. This plan changes docs + DB metadata + a verify sentinel; adds no data flow, recipient, or external transfer. **One watch-item:** DSAR export (`dsar-export.ts:975`) keys on `organizations.owner_user_id`; if the deferred `owner_user_id` reconciliation (Phase 6) ever backfills/junctions it, that follow-up DOES need a `data-integrity-guardian` review + observability-layer citation. Advisory only here; deepen-plan / review formally gate at single-user threshold.

## Test Scenarios
1. Two `owner` rows coexist for one workspace (no constraint raise).
2. `update_workspace_member_role(p_new_role='owner')` promotes a member without raising "direct promotion not allowed".
3. Demote an owner while ≥2 owners exist → succeeds; demote the **last** owner → raises "cannot demote the last owner".
4. verify/117 → `bad=0` on a correct DB; `bad>0` on the named negative fixture/block re-adding a single-owner partial-unique-index, dropping the last-owner guard, or flipping a grant to `authenticated`.
5. `update_workspace_member_role` (4-arg), `create_workspace_invitation` (6-arg), `accept_workspace_invitation` (2-arg) all remain `service_role`-only (NOT `authenticated`-EXECUTE-able); the 3-arg `update_workspace_member_role` overload does not exist.
6. (documented, not necessarily code) `organizations.owner_user_id` behavior when the pointed-to owner is demoted while co-owners remain (per ADR-072: pointer unchanged / no silent re-point); and the demote→remove no-repoint dead-end.

## Alternatives Considered

| Alternative | Verdict | Rationale |
|---|---|---|
| Add a net-new `grant_workspace_co_owner` RPC | **Rejected** | Redundant with invite-as-owner (live) + mig-094 promotion. Adds surface + another single-owner-era comment to sync. |
| Change `transfer` to stop auto-demoting the caller | **Rejected** | That is "add a co-owner," already covered by invite/promotion. `transfer` = deliberate hand-off-and-step-down; promote-before-demote keeps it multi-owner-safe; re-emitting risks the 092 FORWARD-REFERENCE invariants. |
| Add `UNIQUE(workspace_id) WHERE role='owner'` | **Rejected** | Contradicts N-co-owners; breaks live invite-as-owner + existing 2-owner prod rows. |
| Re-emit function bodies via `CREATE OR REPLACE` to fix inline header comments | **Rejected** | Headers are immutable history; only live `COMMENT ON FUNCTION` metadata needs fixing; re-emit risks dropping 092/094 `COALESCE` + `service_role`-only guards. |
| **Reconcile `organizations.owner_user_id` data now** (backfill / junction table) | **Deferred (Phase 6 follow-up)** | Per CTO: the *decision* (pointer meaning) belongs in ADR-072 now; the *data* change is medium-effort and only warranted if DSAR/billing correctness requires a non-pointer owner set. Track it; gate it on the ADR. |
| ADR-only, no migration/verify | **Rejected** | Leaves live DB COMMENT asserting "single-owner strict" + no runtime lock against re-introduction of single-owner enforcement / grant flips. |

## Sharp Edges / Risks
- **`COMMENT ON FUNCTION` apply-role ownership** (learning `2026-05-25-supabase-storage-objects-comment-on-policy-ownership.md`): can fail if the apply role does not own the function. Probe in Phase 0; fallback = ADR-only + inline prose (never a `CREATE OR REPLACE` re-emit).
- **Preserve 092/094 invariants:** keep `COALESCE(p_caller_user_id, auth.uid())` + `service_role`-only grants (FORWARD-REFERENCE warnings). COMMENT-only avoids the body — keep it that way.
- **Sentinel must assert the invariant, not a proxy:** lock the at-least-one-owner *guard presence* + grant + constraint *absence* — NOT a live owner row-count (every solo workspace has count=1 → false-fail). Comment prose is the secondary, rot-prone check.
- **Migration runs in a transaction** (Supabase per-file): `COMMENT ON FUNCTION` is transaction-safe; no `CONCURRENTLY`/`VACUUM`/`ALTER SYSTEM`.
- **Test path must satisfy vitest include globs** (`test/**/*.test.ts`); use `./node_modules/.bin/vitest run`, never `npm run -w`; typecheck via `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- **`organizations.owner_user_id` divergence is deliberately documented, not fixed here** — do not let /work silently widen scope into a backfill; that is Phase 6. The dead-end to record in the ADR: demote the pointer-owner (→ stale pointer) then remove them (→ fully orphaned), and `transfer` rejects an already-owner target, so **no RPC can re-point a stranded pointer** to a surviving co-owner.
- **down.sql must reproduce 092's exact COMMENT value** — it is a multi-line adjacent-string-literal concatenation with NO inserted space between `'…organizations.'` and `'owner_user_id…'`. Capture the source value in Phase 0.
- **Three `owner_user_id` writers, not one** — the headline "pin owner_user_id semantics" deliverable is incomplete unless ADR-072 enumerates `transfer` (092) AND `anonymise_organization_membership` (mig 081, promotes oldest member — a wart) AND the no-op promotion/invite paths.
- **`Closes #5756`** in PR body only (not title).
- A plan whose `## User-Brand Impact` section is empty/`TBD` fails `deepen-plan` Phase 4.6 — it is filled above.
