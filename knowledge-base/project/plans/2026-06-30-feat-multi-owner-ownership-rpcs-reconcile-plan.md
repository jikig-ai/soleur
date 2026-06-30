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
| (not in issue) `organizations.owner_user_id` is the single-owner pointer | Single-valued FK (mig 053:51, `SET NULL` since 065). `transfer` dual-writes it (092:145-147); promotion + invite-as-owner do **not**. Consumers: `workspace-resolver.ts:298,504,515`, `dsar-export-allowlist.ts:218`, `dsar-export.ts:975`, `account-delete.ts:741`. | **ADR-072 DECIDES its meaning** under N owners (primary/billing/DSAR pointer). Any *data* backfill/junction = deferred follow-up issue, gated on the ADR. |
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
- **`COMMENT ON FUNCTION` apply-role probe** (learning `2026-05-25-supabase-storage-objects-comment-on-policy-ownership.md`): `COMMENT ON FUNCTION` needs the apply role to OWN the function. Grep for precedent: `git grep -n 'COMMENT ON FUNCTION public' apps/web-platform/supabase/migrations/`. If precedent applies cleanly, proceed; if none, deepen-plan/preflight MUST validate apply-role ownership. **Fallback** = ADR-072 + inline migration prose comment, drop the structured `COMMENT ON FUNCTION`. Do NOT fall back to a `CREATE OR REPLACE` re-emit (would risk the 092/094 `COALESCE` + `service_role`-only FORWARD-REFERENCE invariants).
- Read-only research the `organizations.owner_user_id` consumers (`workspace-resolver.ts:298,504,515`, `dsar-export-allowlist.ts:218`, `dsar-export.ts:975`, `account-delete.ts:741`) to ground the ADR's pointer-semantics decision. **No edits to these in this PR.**

### Phase 1 — ADR-072 (the headline deliverable)
Author `knowledge-base/engineering/architecture/decisions/ADR-072-workspaces-support-n-co-owners.md` via `soleur:architecture` create (fires the ADR→register wiring). Recommended title: **"Multi-owner workspaces and the `organizations.owner_user_id` primary-owner pointer."** Frontmatter modelled on ADR-044 (`adr`, `title`, `status: accepted`, `date`, `amends: [ADR-038, ADR-044]`, `related: [5756, 5733, 4520]`, `related_plans`, `brand_survival_threshold: single-user incident`). Body:
- **Context:** single-owner-strict (mig 075 / #4520) vs founder's N-co-owners ruling (#5733); the ADR-044 amendment; the residual inconsistencies (RPC comments + undefined `owner_user_id`).
- **Decision:**
  - Workspaces support **≥1 owner**; ownership recorded ONLY as `workspace_members(role='owner')` rows; no UNIQUE/CHECK single-owner constraint.
  - **Sanctioned additive grant path** = invite-as-owner (live) + `update_workspace_member_role(p_new_role='owner')` (RPC primitive, `service_role`-only, no live route — defense-in-depth).
  - **`transfer_workspace_ownership`** = atomic **hand-off-and-step-down** (the *primary-pointer* transfer), NOT the only owner path.
  - **`organizations.owner_user_id`** = the **single primary/billing/DSAR owner pointer** (one of N co-owners), maintained by `transfer`; co-owners added via promotion/invite are full `workspace_members` owners but do NOT change the pointer. State this explicitly so the divergence is **intentional**, not accidental. (Whether to backfill / migrate to a junction is a **deferred** follow-up — see Alternatives.)
  - **At-least-one-owner invariant** (the retained mig-094 guard) — the ONLY ownership-cardinality rule.
  - **Known limitations to record** (CTO carve-outs): `transfer` rejects a target already an owner (092:104-105) — a wart under multi-owner; `remove_workspace_member` rejects removing *any* owner (094:115-116) so the demote-allows-N-1 vs remove-blocks-all asymmetry is intentional.
- **C4 note:** "No C4 model edit" WITH the enumeration citation (see Architecture Decision section).
- **Supersession:** ADR-072 supersedes the single-owner-strict assertion of #4520 / mig 075.

### Phase 2 — migration 117 (COMMENT-only; CONTRACT phase — before the test phase)
`apps/web-platform/supabase/migrations/117_reconcile_ownership_rpc_comments_multi_owner.sql`:
- Header prose: multi-owner reconciliation + ADR-072 reference.
- `COMMENT ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text, uuid)` — replace "Single-owner strict: ..." with hand-off-and-step-down + primary-pointer wording; cite ADR-072 / #5756.
- `COMMENT ON FUNCTION public.update_workspace_member_role(uuid, uuid, text, uuid)` — state `member→owner` promotion is permitted (additive co-owner primitive) and the retained guard is the at-least-one-owner invariant; cite ADR-072.
- **No `CREATE OR REPLACE`, no grant change, no behavior change.**
- `117_*.down.sql`: restore the prior COMMENT strings verbatim.

### Phase 3 — verify/117 sentinel (lock the DURABLE invariant)
`apps/web-platform/supabase/verify/117_reconcile_ownership_rpc_comments_multi_owner.sql` (contract: each row returns `check_name` + `bad`; any `bad>0` fails CI). Per CTO: assert **signature + grant + guard presence**, not just comment prose (prose rots):
1. **No single-owner-enforcing constraint** on `workspace_members` (no UNIQUE index / CHECK whose expression restricts owner rows to one-per-`workspace_id`) — query `pg_constraint`/`pg_index`; `bad=0` when none. (Assert constraint *absence*, NOT a live owner row-count — a solo workspace legitimately has count=1.)
2. **At-least-one-owner guard present** in `update_workspace_member_role`: `pg_get_functiondef(...)` ILIKE `%cannot demote the last owner%` (the durable behavioral lock).
3. **`service_role`-only grants intact**: both 4-arg RPCs are NOT EXECUTE-able by `authenticated` (mirrors verify/092 checks 1-2). The #4762 forge-vector regression lock.
4. (Secondary) `transfer_workspace_ownership` 4-arg COMMENT NOT ILIKE `%single-owner strict%`.

### Phase 4 — test (prove the invariant; AFTER the contract migration)
**Verify runner + path against `apps/web-platform/vitest.config.ts` include globs** (`test/**/*.test.ts`) before fixing the path; run `cd apps/web-platform && ./node_modules/.bin/vitest run <path>` (NOT `npm run -w`). Existing `transfer-ownership-wrapper.test.ts` is a **mocked** wrapper test; `workspace-invitations-accept.integration.test.ts` is an **integration** test against a live test DB. Pick per convention:
- **Preferred (integration):** seed workspace with owner A + member B; `update_workspace_member_role(p_new_role='owner')` for B; assert **two** `workspace_members(role='owner')` coexist (no raise); demote one of two → SUCCEEDS; demote the sole remaining owner → RAISES "cannot demote the last owner". Document expected `organizations.owner_user_id` behavior when the pointed-to owner is demoted while others remain (stays pinned / no change — per ADR-072 decision).
- **Fallback (mocked wrapper):** assert `updateWorkspaceMemberRole({newRole:'owner'})` forwards `p_new_role:'owner'` + `p_caller_user_id` and does not reject 'owner' at the wrapper guard; the DB invariant is carried by verify/117.

### Phase 5 — cross-link the register + amendment
- `knowledge-base/engineering/architecture/domain-model.md` BR-WS-3 source cite → add ADR-072.
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` 2026-06-30 "Owner model note" → replace "dedicated ADR to follow" with the concrete ADR-072 reference.

### Phase 6 — deferred follow-up issue
File a GitHub issue: "reconcile `organizations.owner_user_id` data under N co-owners (backfill or junction)" — gated on ADR-072's pointer-semantics decision; re-eval criteria = "if DSAR/billing correctness requires a non-pointer owner set." Label `domain/engineering`, `type/feature`. (A deferral without a tracking issue is invisible.)

## Files to Create
- `knowledge-base/engineering/architecture/decisions/ADR-072-workspaces-support-n-co-owners.md`
- `apps/web-platform/supabase/migrations/117_reconcile_ownership_rpc_comments_multi_owner.sql`
- `apps/web-platform/supabase/migrations/117_reconcile_ownership_rpc_comments_multi_owner.down.sql`
- `apps/web-platform/supabase/verify/117_reconcile_ownership_rpc_comments_multi_owner.sql`
- A test under `apps/web-platform/test/server/` (name/shape per Phase 4) — or extend an existing ownership test.

## Files to Edit
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — amendment links ADR-072.
- `knowledge-base/engineering/architecture/domain-model.md` — BR-WS-3 source cite → ADR-072.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `ADR-072-...md` exists, `status: accepted`; `## Decision` names: invite-as-owner grant path, `update_workspace_member_role` promotion primitive, `transfer` hand-off-and-step-down, the at-least-one-owner invariant, **and the `organizations.owner_user_id` primary-pointer meaning under N owners**.
- [ ] Migration 117 contains **only** `COMMENT ON FUNCTION` statements: `grep -cE '^\s*(CREATE|ALTER|GRANT|REVOKE|DROP|UPDATE)' 117_*.sql` returns 0.
- [ ] `117_*.down.sql` restores the prior COMMENT text (reversibility).
- [ ] verify/117 returns `bad=0` for every sentinel on a freshly-migrated DB, and **fails** (`bad>0`) on a fixture that re-introduces a single-owner constraint, removes the last-owner guard, or flips a grant to `authenticated` (negative test).
- [ ] Multi-owner test passes: two `owner` rows coexist; `member→owner` promotion does not raise; demoting the **last** owner raises.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; new test passes via `./node_modules/.bin/vitest run <path>`.
- [ ] ADR-044 amendment + domain-model.md BR-WS-3 both cite ADR-072.
- [ ] Deferred `owner_user_id` follow-up issue filed (Phase 6) with re-eval criteria.
- [ ] PR body uses `Closes #5756`.
- [ ] CPO sign-off recorded (threshold = single-user incident).

### Post-merge (operator/automation)
- [ ] Migration 117 + verify/117 apply on the `web-platform-release.yml` migrate+verify path (the merge IS the apply). Confirm verify-migrations job green post-deploy via the CI run — no SSH.

## Architecture Decision (ADR/C4)

### ADR
**Create ADR-072** — the dedicated decision-of-record superseding single-owner-strict (#4520 / mig 075) AND pinning `organizations.owner_user_id` semantics under N owners. In-scope Phase 1 deliverable, authored via `soleur:architecture`. Not deferred.

### C4 views
**No C4 model edit.** Completeness enumeration (read against `model.c4` / `views.c4` / `spec.c4`):
- **External human actors:** only `founder` (`model.c4:8-9`), whose description **already** says "Workspaces may have MULTIPLE Owners (ADR-038 team workspaces)." Already correct.
- **External systems / vendors:** none introduced.
- **Containers / data-stores:** none added; `workspace_members` + `organizations` are existing tables; no schema change.
- **Actor↔surface access relationships:** Owner-shared reads already modelled (`model.c4:272`); no access-topology change.
"No C4 impact" is supported by the enumeration. (If deepen-plan's C4 check decides `founder`'s description should additionally name the at-least-one-owner invariant or the primary-pointer, that is a one-line `model.c4` description edit + `c4-code-syntax`/`c4-render` tests — current description is accurate, so none planned.)

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

Docs + DB-metadata + verify-sentinel change; no new runtime app code path emits at runtime. No `ssh ` in any discoverability command.

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
4. verify/117 → `bad=0` on a correct DB; `bad>0` on a fixture re-adding a single-owner constraint, dropping the last-owner guard, or flipping a grant to `authenticated`.
5. `transfer_workspace_ownership` 4-arg + `update_workspace_member_role` 4-arg remain `service_role`-only.
6. (documented, not necessarily code) `organizations.owner_user_id` behavior when the pointed-to owner is demoted while co-owners remain (per ADR-072: pointer unchanged / no silent re-point).

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
- **`organizations.owner_user_id` divergence is deliberately documented, not fixed here** — do not let /work silently widen scope into a backfill; that is Phase 6.
- **`Closes #5756`** in PR body only (not title).
- A plan whose `## User-Brand Impact` section is empty/`TBD` fails `deepen-plan` Phase 4.6 — it is filled above.
