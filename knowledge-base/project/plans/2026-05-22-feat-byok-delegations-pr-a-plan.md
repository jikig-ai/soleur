---
title: "BYOK Delegations PR-A — Migration 062 + SQL Resolver + Sentinel Sweep + Cap Enforcement + CLI"
status: planned
issue: 4232
parent_issue: 4229
spec: knowledge-base/project/specs/feat-byok-delegations-4232/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md
branch: feat-byok-delegations-4232
pr: 4290
date: 2026-05-22
revised: 2026-05-22
revision_note: "v2 incorporates 3-agent plan-review findings — kill-switch re-architecture (don't extend record_byok_use_and_check_cap; add dedicated check_byok_delegation_cap), abstract error base class, drop _as_self RPCs for PR-A, rolling 24h cap window, 3 test files instead of 8."
lane: cross-domain
brand_survival_threshold: single-user incident
requires_clo_signoff: true
requires_cpo_signoff: true
requires_cto_signoff: true
requires_adr: true
detail_level: a_lot
estimate_days: "3-4"
---

# Plan: BYOK Delegations PR-A — Foundations + Resolver + Sentinel Sweep + Cap + CLI (v2)

## Overview

PR-A of the byok-delegations feature (#4232). Ships every dependency for the dogfood trigger ("Harry the intern starts; Jean wants to fund Harry's runs") in CLI form, behind `FLAG_BYOK_DELEGATIONS`. PR-B (separate plan) adds UI surfaces + Delegation Consent Side Letter (parallel-tracked); both land before the flag flips ON in prd.

The lease split at `apps/web-platform/server/byok-lease.ts` (PR #4225) was designed for this; the `MissingByokKeyError` ADR comment at `byok-lease.ts:101-112` cites #4232 by number ("the future opt-in remediation. NEVER falls back to another user's key"). This flips that "NEVER" to "only with an active, unexpired, unrevoked, under-cap, same-workspace delegation row."

PR-A is **additive for solo users**: all 5 prod `runWithByokLease` sites currently pass `args.userId` for both fields (N2 invariant). The new resolver returns `(callerUserId, NULL)` for any caller with their own `api_keys` row, preserving solo behavior bit-for-bit.

## Research Reconciliation — Spec vs. Codebase

| # | Spec claim | Codebase reality (verified) | Plan response (v2) |
|---|---|---|---|
| 1 | "5 prod `runWithByokLease` sites need updating" | Confirmed: `cc-dispatcher.ts:890`, `agent-runner.ts:882`, `agent-runner.ts:2401`, `cfo-on-payment-failed.ts:199`, `github-on-event.ts:208`. ALL five pass identical `userId` for both fields (N2 invariant). | Sentinel sweep wraps each with `resolveKeyOwnerThenLease`. Resolver fast-path under flag OFF / solo user returns `(userId, NULL)` — zero behavior change. |
| 2 | "Widen `ByokLeaseError.cause` enum" (brainstorm decision #G10) | `MissingByokKeyError` at `byok-lease.ts:75-113` is a **sibling class** to `ByokLeaseError`. Missing-precondition errors are siblings, not lease-internal failures. | **Refine brainstorm #G10 (v2 update):** abstract base `ByokDelegationError` + thin siblings (`Revoked`/`Expired`/`CapExceeded`/`CrossTenant`) extending it. Catch sites get ONE `instanceof ByokDelegationError` clause + `.reason` discriminator. Kieran's hierarchy pattern — Rails `StandardError`-shape. v1 of this plan proposed 4 disconnected siblings; v2 collapses to a base hierarchy after the plan-review fan-out concern. |
| 3 | "Extend `record_byok_use_and_check_cap` for cap+grace+revoke" (spec G7) | `mig 061:81-148`: 6-arg RPC; **zero TS callers in production today** (only stub comments at `cfo-on-payment-failed.ts:195` and `github-on-event.ts:202`). Current cap is per-founder hourly kill-switch grouped by `founder_id`. | **Re-architect (v2):** do NOT extend `record_byok_use_and_check_cap`. Instead add a dedicated `check_byok_delegation_cap(p_delegation_id, p_token_count, p_unit_cost_cents)` RPC that ONLY enforces per-delegation daily cap + revoke (60s grace) + expired checks. `write_byok_audit` extended with `p_delegation_id` (7th arg) writes the audit row. Per-founder hourly kill-switch stays unwired in PR-A (defers cleanly to PR-G #3947). **Why:** v1 extension would mix grantor's hourly SUM across grantee-debit flips (Kieran P0 #1 — semantic bug). |
| 4 | "DB-level CHECK constraint enforcing same_workspace" (spec G3) | `is_workspace_member` is plpgsql VOLATILE (mig 053:115-140). CHECK constraints in Postgres only safely call IMMUTABLE functions. | **Spec G3 correction:** implement as `BEFORE INSERT OR UPDATE TRIGGER`. Raises P0001 with `byok_delegations:cross-tenant` SQLSTATE; `reportSilentFallback` tags with `art_33_breach: "true"`. |
| 5 | "WORM precedent is scope_grants mig 048" | Confirmed at mig 048:42-115. **Structural-diff bypass** (per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing`). | Mirror exactly: Shape 1 = revoke flip; Shape 2 = anonymise. **v2 simplification:** member-departure trigger sets `revoked_by_user_id = OLD.user_id` (departing user is the actor for ledger purposes) instead of NULL — collapses to 2 WORM shapes (v1 had 3). |
| 6 | "Workspace ID resolution from userId" | `workspace-resolver.ts:66`: `getDefaultWorkspaceForUser(userId, supabase)`. N2 invariant confirmed in mig 053:63/240. | CLI `byok-grant` resolves workspace via `getDefaultWorkspaceForUser` if `--workspace` arg omitted. SQL resolver scopes delegation lookup by `(grantee_user_id, workspace_id)` where workspace_id is inferred from `workspaceContextUserId` via the same JOIN. |
| 7 | "Member-departure auto-revoke transactionally" (spec G12) | DELETE on `workspace_members` only inside `remove_workspace_member` RPC (mig 058:320) and `anonymise_organization_membership` cascade. | DB trigger AFTER DELETE ON workspace_members — covers both DELETE paths; txn-atomic; no future site can bypass. |
| 8 | "Art. 17 cascade integration" (spec G13) | `auth.admin.deleteUser` at `account-delete.ts:448`; existing UK-spelled cascade chain spans `:75-300`. | Add `anonymise_byok_delegations(p_user_id)` matching that pattern. **Wire into `account-delete.ts` as phase 5.9 BEFORE phase 6 IN THIS PR** (per learning `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md` — don't repeat mig 044's documented-but-unwired anti-pattern). |
| 9 | "CLI grant/revoke" (spec G11) | `scripts/*.ts` precedents (cla-backfill-evidence.ts etc.): bun shebang + hand-rolled argv + service-role client. | **v2 simplification:** PR-A ships **admin-form RPCs ONLY** (`grant_byok_delegation`/`revoke_byok_delegation`). UI's authenticated `_as_self` variants ship in PR-B atomically with their UI consumers (same learning as #8). Admin-form takes `p_actor_user_id uuid NOT NULL` — security audit chain (Kieran P1: who issued the admin write). |
| 10 | "Feature flag `BYOK_DELEGATIONS_ENABLED`" (spec G15) | Canonical module `apps/web-platform/lib/feature-flags/server.ts` FLAG_VARS; sibling `team-workspace-invite` uses `FLAG_TEAM_WORKSPACE_INVITE` + two-key gate with `*_ALLOWLIST_ORG_IDS`. | **Spec G15 rename:** `FLAG_BYOK_DELEGATIONS` (env) + `byok-delegations` (lookup key) + `isByokDelegationsEnabled(orgId?)` two-key gate. When flag OFF, resolver short-circuits — surface fully inert. |
| 11 | "pg_default_acl audit" (spec TR4) | Zero existing test. Learning `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md` is uncodified. | **v2 fold:** single `pg_default_acl` query lives as ONE assertion in the main `byok-delegations.test.ts` suite (not a dedicated file). Generic-audit generalization deferred to follow-up. |
| 12 | "RLS deny-test dual-shape (42501 vs 42P17)" (spec TR6) | Pattern exists but no test asserts both shapes distinctly. | New canonical test in `byok-delegations.test.ts` covers both. |
| 13 | "Migration down.sql" | Convention established for migrations 053+. | `062_byok_delegations.down.sql` required. |
| 14 | "Sentry tagging on cross-tenant" (spec FR7) | Canonical wrapper: `reportSilentFallback` (apps/web-platform/server/observability.ts). | Cross-tenant trigger raises P0001 → TS catches and calls `reportSilentFallback({feature: "byok-delegations", op: "cross-tenant-violation", level: "error", tags: {art_33_breach: "true", ...hashes}})`. Distinct action shape prevents Sentry dedup collapse per learning `2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md`. |
| 15 | "WORM table grants" | mig 048/058 pattern: `REVOKE UPDATE, DELETE FROM PUBLIC, anon, authenticated`; SELECT via RLS; trigger function REVOKEd from all. | Mirror. Admin-form RPCs `GRANT EXECUTE TO service_role` only. |
| 16 | "Resolver returns one row" | PostgREST `.single()` raises PGRST116 on zero rows. | **v2 fix:** use `.maybeSingle()` in `byok-resolver.ts`; handle `data === null` as "no row" explicitly per Kieran P0 #2. |
| 17 | "Cap window: UTC midnight" (spec implies) | Existing kill-switch uses rolling `interval '1 hour'`. | **v2 change:** rolling 24h window (`ts > now() - interval '24 hours'`) — matches existing idiom; drops Decision 8 + R6 timezone documentation. |

## Research Insights

**Codebase patterns mirrored (all verified):**

- WORM trigger structural-diff: `apps/web-platform/supabase/migrations/048_scope_grants.sql:42-115`
- `is_workspace_member` 2-arg plpgsql VOLATILE: `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql:115-140`
- `write_byok_audit` 6-arg RPC: `apps/web-platform/supabase/migrations/061_byok_audit_workspace_id_rpcs.sql:34-78`
- Cost-writer `persistTurnCost`: `apps/web-platform/server/cost-writer.ts:1-80` (currently calls `write_byok_audit` only)
- Anonymise cascade orchestrator: `apps/web-platform/server/account-delete.ts:75-300` (8 phases, UK spelling)
- Feature-flag module: `apps/web-platform/lib/feature-flags/server.ts` (FLAG_VARS + two-key gate precedent)
- Workspace resolution: `apps/web-platform/server/workspace-resolver.ts:66`
- ByokLeaseError sibling-class precedent: `MissingByokKeyError` at `byok-lease.ts:75-113`
- CLI script convention: `apps/web-platform/scripts/cla-backfill-evidence.ts`
- Sentry wrapper: `apps/web-platform/server/observability.ts` (`reportSilentFallback`)

**Institutional learnings folded into plan (cited inline below):**

- `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md`
- `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`
- `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`
- `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`
- `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`
- `2026-04-18-cf-cache-purge-on-share-revoke.md`
- `2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md`
- `2026-05-19-doppler-env-hot-reload-limitation.md`
- `2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes.md`
- `2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape.md`
- `2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md`
- `2026-05-17-mocked-tests-miss-shared-table-schema-gaps.md`

## User-Brand Impact

`USER_BRAND_CRITICAL=true` (carried forward from brainstorm).

**If this lands broken, the user experiences:** Jean clicks "revoke" on Harry's delegation; the resolver's stale read keeps using Jean's key for the next 30 minutes of Harry's runs; Jean's Anthropic invoice shows hundreds of dollars Jean didn't authorize.

**If this leaks, the user's data/workflow/money is exposed via:** an RLS predicate bug or same_workspace trigger gap lets a member of OrgA insert a `byok_delegations` row naming a user in OrgB as grantor; that stranger now leases Jean's Anthropic key at will. GDPR Art. 33 territory (unauthorized disclosure of prompt content to a controller outside consent scope, 72h notification clock).

**Brand-survival threshold:** `single-user incident`.

CPO sign-off required at plan time (this section + threshold). CLO + CTO sign-offs carry forward from brainstorm. `user-impact-reviewer` agent invoked at PR-review time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Domain Review

**Domains relevant:** Product (CPO), Engineering (CTO), Legal (CLO). Carried forward from brainstorm. Marketing/Sales/Ops/Support/Finance not relevant.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** PR-A is CLI-only, dogfood scope. UI surfaces (member-row grant, cost panes, banner) defer to PR-B. CPO's load-bearing decisions (USD/day cap as v1, grantee's own key wins by default, per-workspace grant scope, instant revoke) are encoded as plan phases. CPO's failure-mode matrix becomes PR-B's test plan.

### Engineering (CTO)

**Status:** reviewed (v2 with plan-review refinements)
**Assessment:** Resolver-and-table change. v2 plan-review refinements layered on top of brainstorm: (a) spec G3 CHECK → TRIGGER, (b) brainstorm #G10 cause-widen → abstract error base + thin siblings, (c) cap path → dedicated `check_byok_delegation_cap` RPC (not `record_byok_use_and_check_cap` extension; avoids the grantor-vs-grantee SUM-window attribution bug), (d) admin-form RPCs only for PR-A (self-form lands with UI in PR-B), (e) admin-form takes `p_actor_user_id` for audit chain, (f) rolling 24h cap window matches existing kill-switch idiom, (g) `.maybeSingle()` on resolver, (h) member-departure trigger sets `revoked_by_user_id = OLD.user_id` (collapses WORM shapes from 3 to 2). ADR required (Phase 8).

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Existing ToS 2.2.0 + AUP §5.5 + workspace-member Side Letter (PR #4225) does NOT cover delegation. PR-B parallel-tracks: Delegation Consent Side Letter, DPD §2.3 addendum (joint controllership Art. 26), AUP §5.6. PR-A's GDPR surface (this plan): migration 062 carries `LAWFUL_BASIS: Art. 6(1)(b) contract` + `RETENTION: 7 years`. Cross-tenant CHECK violation = Art. 33 trigger; distinct Sentry action shape with `art_33_breach=true`. Flag-OFF in prd until PR-B + signed Side Letter land — joint-controller surface fully inert in prd until then.

### Product/UX Gate

**Tier:** NONE. PR-A creates no `components/**/*.tsx`, no `app/**/page.tsx`. CLI-only.

**Brainstorm-recommended specialists:** spec-flow-analyzer + ux-design-lead recommended by CPO for PR-B. N/A here.

**Agents invoked at plan-time:** repo-research-analyst, learnings-researcher (Phase 1); gdpr-gate (Phase 2.7 — zero `Critical` / zero `Important` findings); DHH + Kieran + Simplicity plan-review (Phase 4 — all findings applied, plan v2). user-impact-reviewer at PR-review time.

## Implementation Phases (v2 — 8 phases, collapsed from 13)

### Phase 0 — Preconditions (verify before any RED step in /work)

1. **Worktree state**: `git status --short` clean; `git rev-parse --abbrev-ref HEAD == feat-byok-delegations-4232`.
2. **5 call sites unchanged** — `git grep -n 'runWithByokLease' apps/web-platform/server/` returns the 5 invocations at expected lines.
3. **`byok-lease.ts` line refs** — read `:58-75` (ByokLeaseArgs), `:88-113` (ByokLeaseError + MissingByokKeyError siblings), `:182-196` (mapByokLeaseCauseToErrorCode exhaustive switch). Confirm sibling-class precedent.
4. **`record_byok_use_and_check_cap` STILL has zero TS callers** — `git grep 'record_byok_use_and_check_cap' apps/web-platform/server/` returns empty. v2 path doesn't touch it; this verifies no drift means new collisions.
5. **`persistTurnCost` callers enumerated** — `git grep -n 'persistTurnCost' apps/web-platform/server/` returns the known 2 sites (`agent-runner.ts:1891`, `cc-dispatcher.ts` `onResult`). Re-anchor Phase 5 if drift.
6. **Feature-flag module shape** — read `apps/web-platform/lib/feature-flags/server.ts` FLAG_VARS + `isTeamWorkspaceInviteEnabled` two-key gate.
7. **account-delete cascade chain** — read `apps/web-platform/server/account-delete.ts:75-300`. Confirm insertion point for phase 5.9 (after 5.8, before phase 6).
8. **`getDefaultWorkspaceForUser` exists** — read `apps/web-platform/server/workspace-resolver.ts:66`.
9. **`audit_byok_use.invocation_id UNIQUE`** — verify in mig 037; required for Inngest-retry idempotency (Risk R4). If absent, add a unique constraint to mig 062.
10. **dev-Supabase mig state** — `mcp__plugin_supabase_supabase__list_migrations` (dev project) shows 053-061 applied; 062 not yet.
11. **Baseline `bun run typecheck` clean** + **`bun test` baseline pass**.

Any precondition failure → re-anchor plan, do not proceed.

### Phase 1 — Migration 062: Table + Triggers + RLS + Indexes + `audit_byok_use.delegation_id`

**File:** `apps/web-platform/supabase/migrations/062_byok_delegations.sql`

Migration header includes `LAWFUL_BASIS: Art. 6(1)(b) contract` + `RETENTION: 7 years` + DEPENDENCY citations + the trigger-not-CHECK rationale citing this plan's Research Reconciliation row 4.

**Table** `public.byok_delegations` columns: `id uuid PK`, `grantor_user_id`, `grantee_user_id`, `workspace_id` (all NOT NULL, FK ON DELETE RESTRICT), `daily_usd_cap_cents int NOT NULL CHECK (> 0)`, `created_by_user_id NOT NULL`, `created_at`, `expires_at NULL`, `revoked_at NULL`, `revoked_by_user_id NULL`, `revocation_reason text NULL CHECK IN ('grantor_revoke','grantee_decline','member_departed','admin_revoke','art_17_anonymise')`. Table-level CHECKs: `grantor_user_id <> grantee_user_id`; `revoked_at >= created_at`; `expires_at > created_at`.

**Indexes:** partial unique `(grantor_user_id, grantee_user_id, workspace_id) WHERE revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now())`; `(grantee_user_id, workspace_id) WHERE revoked_at IS NULL` for resolver hot path.

**Same-workspace trigger** `byok_delegations_check_same_workspace()` BEFORE INSERT OR UPDATE OF (grantor_user_id, grantee_user_id, workspace_id) — calls `is_workspace_member` for both grantor and grantee; raises P0001 `byok_delegations:cross-tenant: <role> % is not a member of workspace %`. Pin `search_path = public, pg_temp`. REVOKE ALL on function.

**WORM trigger** `byok_delegations_no_mutate()` mirroring mig 048 structural-diff bypass — 2 allowed shapes (v2: collapsed from 3 since member-departure now sets revoked_by_user_id = OLD.user_id):

```sql
-- Shape 2 (Art. 17 anonymise): grantor_user_id + grantee_user_id +
-- created_by_user_id + revoked_by_user_id all non-NULL → NULL together;
-- everything else unchanged.
IF OLD.grantor_user_id IS NOT NULL AND NEW.grantor_user_id IS NULL
   AND OLD.grantee_user_id IS NOT NULL AND NEW.grantee_user_id IS NULL
   AND OLD.created_by_user_id IS NOT NULL AND NEW.created_by_user_id IS NULL
   AND NOT (OLD.workspace_id IS DISTINCT FROM NEW.workspace_id)
   AND NOT (OLD.daily_usd_cap_cents IS DISTINCT FROM NEW.daily_usd_cap_cents)
   AND NOT (OLD.created_at IS DISTINCT FROM NEW.created_at)
   AND NOT (OLD.expires_at IS DISTINCT FROM NEW.expires_at)
   AND NOT (OLD.revoked_at IS DISTINCT FROM NEW.revoked_at)
   AND NOT (OLD.revocation_reason IS DISTINCT FROM NEW.revocation_reason)
   AND (NEW.revoked_by_user_id IS NULL OR OLD.revoked_by_user_id = NEW.revoked_by_user_id)
THEN RETURN NEW; END IF;

-- Shape 1 (revoke flip): revoked_at + revoked_by_user_id + revocation_reason
-- all NULL → non-NULL together; everything else unchanged. Member-departure
-- trigger sets revoked_by_user_id = OLD.user_id (the departing user) so this
-- single shape covers ALL revoke paths (no Shape 1' variant needed).
IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL
   AND OLD.revoked_by_user_id IS NULL AND NEW.revoked_by_user_id IS NOT NULL
   AND OLD.revocation_reason IS NULL AND NEW.revocation_reason IS NOT NULL
   AND NOT (OLD.grantor_user_id IS DISTINCT FROM NEW.grantor_user_id)
   AND NOT (OLD.grantee_user_id IS DISTINCT FROM NEW.grantee_user_id)
   AND NOT (OLD.workspace_id IS DISTINCT FROM NEW.workspace_id)
   AND NOT (OLD.daily_usd_cap_cents IS DISTINCT FROM NEW.daily_usd_cap_cents)
   AND NOT (OLD.created_by_user_id IS DISTINCT FROM NEW.created_by_user_id)
   AND NOT (OLD.created_at IS DISTINCT FROM NEW.created_at)
   AND NOT (OLD.expires_at IS DISTINCT FROM NEW.expires_at)
THEN RETURN NEW; END IF;

IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'byok_delegations is append-only; use anonymise_byok_delegations' USING ERRCODE = 'P0001'; END IF;
RAISE EXCEPTION 'byok_delegations: only revoke flip and Art. 17 anonymise shapes are permitted' USING ERRCODE = 'P0001';
```

REVOKE ALL on `byok_delegations_no_mutate()`; create BEFORE UPDATE + BEFORE DELETE triggers.

**RLS:**

```sql
ALTER TABLE public.byok_delegations ENABLE ROW LEVEL SECURITY;

CREATE POLICY byok_delegations_select_for_parties ON public.byok_delegations
  FOR SELECT TO authenticated
  USING (
    public.is_workspace_member(workspace_id, auth.uid())
    AND (grantor_user_id = auth.uid() OR grantee_user_id = auth.uid())
  );

REVOKE INSERT, UPDATE, DELETE ON TABLE public.byok_delegations FROM PUBLIC, anon, authenticated;
```

No owner-INSERT policy (per learning `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass`). All writes via SECURITY DEFINER RPCs in Phase 2.

**`audit_byok_use.delegation_id`:**

```sql
ALTER TABLE public.audit_byok_use
  ADD COLUMN delegation_id uuid NULL REFERENCES public.byok_delegations(id) ON DELETE RESTRICT;

CREATE INDEX audit_byok_use_delegation_ts_idx
  ON public.audit_byok_use (delegation_id, ts)
  WHERE delegation_id IS NOT NULL;
```

### Phase 2 — Migration 062: RPCs

Same migration file. Signatures + rationale (full bodies in the migration file at /work time).

#### `grant_byok_delegation` (admin-form ONLY for PR-A; self-form ships in PR-B with UI consumer)

```sql
grant_byok_delegation(
  p_grantor_user_id     uuid,
  p_grantee_user_id     uuid,
  p_workspace_id        uuid,
  p_daily_usd_cap_cents int,
  p_expires_at          timestamptz,
  p_actor_user_id       uuid    -- v2: who issued the admin write; audit chain
) RETURNS uuid
```

Body: INSERT into `byok_delegations`; `created_by_user_id = p_actor_user_id` (so the audit chain records "operator X granted delegation from Y to Z"). REVOKE ALL FROM PUBLIC/anon/authenticated; GRANT EXECUTE to service_role.

#### `revoke_byok_delegation` (admin-form ONLY for PR-A)

```sql
revoke_byok_delegation(
  p_delegation_id uuid,
  p_actor_user_id uuid,
  p_reason        text   -- in ('grantor_revoke','grantee_decline','admin_revoke')
) RETURNS void
```

UPDATE the row setting `revoked_at = now()`, `revoked_by_user_id = p_actor_user_id`, `revocation_reason = p_reason`. service_role only.

#### `resolve_byok_key_owner` (the load-bearing resolver)

```sql
resolve_byok_key_owner(
  p_caller_user_id            uuid,
  p_workspace_context_user_id uuid
) RETURNS TABLE(key_owner_user_id uuid, delegation_id uuid)
```

Resolution order (precedence #3 from operator):

1. Caller has own `api_keys` row → return `(callerUserId, NULL)`.
2. Resolve workspace_id from `workspaceContextUserId` (JOIN through `workspace_members ⋈ workspaces` ORDER BY created_at LIMIT 1).
3. SELECT active delegation row `WHERE grantee_user_id = caller AND workspace_id = resolved AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now()) ORDER BY created_at DESC LIMIT 1`. If found, return `(grantor_user_id, id)`.
4. Otherwise return no row (TS layer handles via `.maybeSingle()`).

plpgsql SECURITY DEFINER `SET search_path = public, pg_temp`. REVOKE FROM PUBLIC/anon/authenticated. GRANT EXECUTE TO service_role.

#### `check_byok_delegation_cap` (v2 — dedicated cap-enforcement RPC, NOT extension of `record_byok_use_and_check_cap`)

```sql
check_byok_delegation_cap(
  p_delegation_id   uuid,
  p_token_count     int,
  p_unit_cost_cents int,
  p_caller_user_id  uuid   -- caller user_id, for the post-grace attribution branch
) RETURNS TABLE(
  current_spent_cents int,
  cap_cents           int,
  outcome             text   -- 'pass' | 'cap_exceeded' | 'revoked_post_grace' | 'expired'
)
```

Body:
1. `SELECT ... FOR UPDATE` the delegations row by id.
2. If `revoked_at IS NOT NULL AND now() > revoked_at + interval '60 seconds'` → return `outcome = 'revoked_post_grace'` AND raise SQLSTATE P0001 with message `byok_delegations:revoked_post_grace`. **No audit row written** — the audit write happens in `write_byok_audit` AFTER this check passes; the TS layer translates the SQLSTATE into a `ByokDelegationError{reason:'revoked_post_grace'}` and, for the cost-shift case, writes a separate attribution audit row via `write_byok_audit` with `founder_id = p_caller_user_id`. Keeps cap-check separate from audit-write (v2 cleaner separation).
3. If `expires_at IS NOT NULL AND now() > expires_at` → raise SQLSTATE P0001 `byok_delegations:expired`.
4. Otherwise SUM 24h spend: `SELECT COALESCE(SUM(token_count * unit_cost_cents), 0) FROM audit_byok_use WHERE delegation_id = p_delegation_id AND ts > now() - interval '24 hours'`. **Rolling 24h window** (v2 — matches existing kill-switch idiom).
5. If `spent + (p_token_count * p_unit_cost_cents) > p_daily_usd_cap_cents` → raise SQLSTATE P0001 `byok_delegations:cap_exceeded`. Otherwise return `outcome = 'pass'`.

plpgsql SECURITY DEFINER `SET search_path = public, pg_temp`. REVOKE ALL FROM PUBLIC/anon/authenticated; GRANT EXECUTE TO service_role.

**Per-founder kill-switch (`record_byok_use_and_check_cap`) is NOT extended in PR-A.** Wiring of the per-founder hourly cap globally is deferred to PR-G (#3947). PR-A's cap path is per-delegation only.

#### `write_byok_audit` extension (7th arg `p_delegation_id`)

DROP + CREATE the 6-arg form to add `p_delegation_id uuid NULL` as 7th arg. Body: same INSERT but threads `delegation_id`. service_role only.

#### `anonymise_byok_delegations(p_user_id uuid)`

UPDATE rows setting `grantor_user_id` + `grantee_user_id` + `created_by_user_id` + `revoked_by_user_id` to NULL where the user appears in any of those columns. SECURITY DEFINER service_role-only. Matches sibling cascade RPC pattern.

#### Member-departure cascade trigger

`byok_delegations_on_member_delete()` AFTER DELETE ON workspace_members:

```sql
UPDATE public.byok_delegations
   SET revoked_at         = now(),
       revoked_by_user_id = OLD.user_id,     -- v2: departing user IS the actor; collapses WORM Shape 1' edge case
       revocation_reason  = 'member_departed'
 WHERE (grantor_user_id = OLD.user_id OR grantee_user_id = OLD.user_id)
   AND workspace_id      = OLD.workspace_id
   AND revoked_at IS NULL;
```

### Phase 3 — Migration 062 down.sql + Reverse Cascade

**File:** `apps/web-platform/supabase/migrations/062_byok_delegations.down.sql`

DROP order (reverse of UP): cascade trigger, anonymise RPC, check_cap RPC, resolver, revoke + grant RPCs, restore `write_byok_audit` 6-arg form (re-create verbatim from mig 061:34-78), `ALTER audit_byok_use DROP COLUMN delegation_id`, WORM + same-workspace triggers, RPCs' functions, indexes, table.

### Phase 4 — `byok-resolver.ts` + Abstract Error Hierarchy + Type Widening

**Files:** `apps/web-platform/server/byok-resolver.ts` (NEW) + `apps/web-platform/server/byok-lease.ts` (EDIT).

#### byok-resolver.ts

Exports:

```typescript
// Abstract base — catch sites use one `instanceof ByokDelegationError` clause.
export abstract class ByokDelegationError extends Error {
  public abstract readonly reason: 'revoked_post_grace' | 'expired' | 'cap_exceeded' | 'cross_tenant';
  public readonly delegationId?: string;
  public readonly workspaceIdHash?: string;
  // shared structured fields for Sentry tags
}

// Thin siblings extend the base. Each holds reason-specific metadata only.
export class ByokDelegationRevokedError extends ByokDelegationError { reason = 'revoked_post_grace' as const; }
export class ByokDelegationExpiredError extends ByokDelegationError { reason = 'expired' as const; }
export class ByokDelegationCapExceededError extends ByokDelegationError { reason = 'cap_exceeded' as const; }
export class ByokDelegationCrossTenantError extends ByokDelegationError { reason = 'cross_tenant' as const; }

export async function resolveKeyOwnerThenLease<T>(
  callerUserId: string,
  workspaceContextUserId: string,
  fn: (lease: ByokLease) => Promise<T>,
): Promise<T>;
```

Body of `resolveKeyOwnerThenLease`:
1. If `isByokDelegationsEnabled() === false` → direct `runWithByokLease({keyOwnerUserId: callerUserId, workspaceContextUserId}, fn)`. Fully inert.
2. Otherwise: `supabase.rpc('resolve_byok_key_owner', {p_caller_user_id, p_workspace_context_user_id}).maybeSingle()` (v2 — handles zero rows cleanly; no PGRST116).
3. On `error`: log + fall through to direct `runWithByokLease`. Existing MissingByokKeyError contract preserved.
4. On `data === null`: fall through to direct `runWithByokLease` (no own key + no delegation → lease body raises MissingByokKeyError).
5. On `data` present: `runWithByokLease({keyOwnerUserId: data.key_owner_user_id, workspaceContextUserId, delegationId: data.delegation_id ?? undefined}, fn)`.

#### byok-lease.ts edits

1. `ByokLeaseArgs` (line 58) — add `delegationId?: string` (optional; NULL for self-funded).
2. `ByokLease` (line 198) — add `readonly delegationId?: string` (cost-writer reads).
3. `runWithByokLease` (line 338) — thread `args.delegationId` into the lease slot.
4. **No changes** to `ByokLeaseError.cause`, `mapByokLeaseCauseToErrorCode`, or any catch-site mapping. Delegation errors are siblings, NOT a cause-widening (per v2 plan-review).

Per `hr-type-widening-cross-consumer-grep`: even an optional add is cross-consumer. PR body lists each consumer of `ByokLeaseArgs`/`ByokLease`/`ByokLeaseError` and whether it reads/writes the new field.

### Phase 5 — 5-Site Sentinel Sweep + cost-writer Cap-Check + Audit Threading

**Files:** the 5 lease-call-site files + `cost-writer.ts`.

#### Sentinel sweep (5 sites)

| # | Site | Conversion |
|---|------|------------|
| 1 | `agent-runner.ts:882` (startAgentSession) | `runWithByokLease({wcu, kou}, ...)` → `resolveKeyOwnerThenLease(userId, userId, ...)` |
| 2 | `agent-runner.ts:2401` (router sendUserMessage) | same |
| 3 | `cc-dispatcher.ts:890` (realSdkQueryFactory) | same |
| 4 | `cfo-on-payment-failed.ts:199` (Inngest cfo step) | same |
| 5 | `github-on-event.ts:208` (Inngest github step) | same |

Behavior under flag OFF: all 5 sites behave identically to today (resolver fast-path). Behavior under flag ON, solo user: same (api_keys EXISTS check). Behavior under flag ON, delegated path: lease body now reads grantor's key; cost-writer threads `delegationId`.

#### cost-writer.ts edits

Extend `persistTurnCost` signature with optional `delegationId?: string` and `callerUserId?: string` parameters:

1. **Pre-write cap check** (when `delegationId !== undefined`): call `check_byok_delegation_cap(p_delegation_id, p_token_count, p_unit_cost_cents, p_caller_user_id)`.
   - On SQLSTATE P0001 with message `^byok_delegations:cap_exceeded` → throw `ByokDelegationCapExceededError` + `reportSilentFallback({feature:"byok-delegations", op:"cap-exceeded", level:"warning", tags:{delegation_id_hash, ...}})`. **Audit row NOT written** (the cost was blocked).
   - On `^byok_delegations:revoked_post_grace` → throw `ByokDelegationRevokedError`. **Write a SEPARATE attribution audit row via `write_byok_audit(... p_delegation_id, founder_id = callerUserId)`** — cost-shift accounting fiction; Anthropic already charged grantor's key, ledger records caller as attribution.
   - On `^byok_delegations:expired` → throw `ByokDelegationExpiredError`. Same audit-attribution shift to caller.
   - On `pass` (or check_cap returned without raising) → proceed to step 2.

2. **Audit-row write** (always when cap-check passes): `write_byok_audit(invocation_id, founder_id = grantorUserId or callerUserId based on attribution, workspace_id, agent_role, token_count, unit_cost_cents, delegation_id)`.

3. **Update the 2 known callers** of `persistTurnCost`:
   - `agent-runner.ts:1891` — thread `lease.delegationId` + `lease.callerUserId` (callerUserId === workspaceContextUserId in current shape; resolver populates accurately).
   - `cc-dispatcher.ts` `onResult` — same.

4. **Per-founder kill-switch (`record_byok_use_and_check_cap`) is NOT called from PR-A.** Deferred to PR-G #3947. Cost-writer continues using `write_byok_audit` (fire-and-forget) for the audit-row insert.

### Phase 6 — Art. 17 Cascade Wire-Up in account-delete.ts

**File:** `apps/web-platform/server/account-delete.ts` (EDIT)

Add new phase 5.9 between phase 5.8 (`anonymise_organization_membership`) and phase 6 (`auth.admin.deleteUser`). Call `supabase.rpc("anonymise_byok_delegations", { p_user_id: userId })` with the same error-handling shape as siblings (try/catch + `reportSilentFallback` on non-fatal failure). Update docstring header at lines 75-82.

### Phase 7 — CLI grant/revoke + package.json + Feature Flag

**Files:** `apps/web-platform/scripts/byok-grant.ts` (NEW) + `apps/web-platform/scripts/byok-revoke.ts` (NEW) + `apps/web-platform/package.json` (EDIT) + `apps/web-platform/lib/feature-flags/server.ts` (EDIT).

#### byok-grant.ts

```
#!/usr/bin/env bun
// Usage:
//   doppler run -p soleur -c dev -- bun run byok-grant -- \
//     --actor jean@jikigai.com \
//     --grantor jean@jikigai.com --to harry@jikigai.com \
//     --workspace auto --cap-cents 2000 [--expires-in 30d]
```

Hand-rolled argv (`cla-backfill-evidence.ts` precedent). Resolve emails → userIds via `supabase.auth.admin.listUsers`. Resolve workspace via `getDefaultWorkspaceForUser(grantor)` if `--workspace auto`. Call `grant_byok_delegation(p_grantor, p_grantee, p_workspace, p_cap, p_expires, p_actor)`. Print `{delegation_id, cap, expiry, actor}` JSON on success; SQLSTATE + message on error.

`--actor` is required and audit-chain load-bearing (Kieran P1: who issued the admin write).

#### byok-revoke.ts

Same pattern. Calls `revoke_byok_delegation(p_delegation_id, p_actor, p_reason)`.

#### package.json

Add scripts entries:

```json
"byok-grant": "bun scripts/byok-grant.ts",
"byok-revoke": "bun scripts/byok-revoke.ts"
```

#### Feature flag (`lib/feature-flags/server.ts`)

Add `"byok-delegations": "FLAG_BYOK_DELEGATIONS"` to `FLAG_VARS`. Add `isByokDelegationsEnabled(orgId?: string): boolean` mirroring `isTeamWorkspaceInviteEnabled`: env (`FLAG_BYOK_DELEGATIONS === "1"`) AND allowlist (`orgId` in `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS`).

Doppler config:
- dev: `FLAG_BYOK_DELEGATIONS=1`, `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS=<jikigai-org-uuid>`
- prd: `FLAG_BYOK_DELEGATIONS=0` (until PR-B + Side Letter), allowlist seeded with jikigai

Per learning `2026-05-19-doppler-env-hot-reload-limitation.md`: flag flip in prd requires redeploy.

### Phase 8 — Tests + ADR + PR Body

#### Tests (3 files total — v2 consolidated from 8)

**`apps/web-platform/test/server/byok-delegations.test.ts`** (NEW) — single table-driven suite with `beforeEach` TRUNCATE per Kieran P2 (`cq-test-fixtures-synthesized-only`):

- RLS deny dual-shape:
  - INSERT via authenticated client direct: 42501
  - INSERT via admin RPC with cross-tenant pair: P0001 from `byok_delegations_check_same_workspace`; Sentry event captured with `art_33_breach: "true"`
  - SELECT by grantor / by grantee / by third party (same workspace) / by user (different workspace)
  - Direct UPDATE on `revoked_at` outside RPC: 42501 (REVOKE) OR P0001 (WORM trigger)
  - Direct DELETE: P0001 (WORM)
- WORM trigger structural-diff: Shape 1 revoke flip passes; Shape 2 anonymise passes; everything else raises P0001
- Revoke-grace timing:
  - Token at t=+30s after revoke → cap-check passes (within grace); `write_byok_audit` row.founder_id = grantor
  - Token at t=+90s after revoke → `check_byok_delegation_cap` raises P0001 `revoked_post_grace`; TS throws `ByokDelegationRevokedError`; `write_byok_audit` row.founder_id = caller; Sentry warning captured
  - Document the controlled-clock technique (`pg_sleep` + `SET LOCAL TIMEZONE` OR statement-timestamp manipulation) in test header
- Cap-exceeded:
  - Multiple turns summing to $15 against $20 cap: pass
  - Next turn at $10: `check_byok_delegation_cap` raises P0001 `cap_exceeded`; TS throws `ByokDelegationCapExceededError`; **no audit row written**; grantor's spend SUM unchanged
- Member-departure auto-revoke:
  - DELETE workspace_members → byok_delegations row has `revoked_at` set, `revoked_by_user_id = OLD.user_id`, `revocation_reason = 'member_departed'`
- Art. 17 anonymise:
  - Call `anonymise_byok_delegations(U)`; rows nullified per Shape 2; everything else preserved
- pg_default_acl audit (v2 — folded as ONE assertion): query `pg_default_acl` and per-relation grants; assert no `authenticated` EXECUTE on admin-form RPCs, no leaked grants on the table

**`apps/web-platform/test/server/byok-resolver.test.ts`** (NEW):

- Caller has own key → `(callerUserId, NULL)`
- Caller no own key + active delegation → `(grantorUserId, delegationId)`
- Caller has own key AND active delegation → `(callerUserId, NULL)` [precedence #3]
- No own key + no delegation → no row; lease body raises `MissingByokKeyError`
- No own key + expired delegation → no row
- No own key + revoked delegation → no row
- Flag OFF → resolver bypasses delegation lookup; behavior == legacy `runWithByokLease`

**`apps/web-platform/test/migration/062_byok_delegations.migration.test.ts`** (NEW):

- Real-DB integration (NOT mocked) per learning `2026-05-17-mocked-tests-miss-shared-table-schema-gaps.md`. Targets dev-Supabase only (`hr-dev-prd-distinct-supabase-projects`).
- Apply migration; verify table + indexes + triggers + RPCs + RLS enabled
- Apply down.sql; verify clean reversal

#### ADR

Run `/soleur:architecture create "BYOK delegations: per-workspace grantor-funded runs"` after tests pass.

Decisions captured (v2):

1. SQL plpgsql resolver (not TS) for atomic MVCC read vs revoke writes
2. Hybrid WORM via scope_grants (mig 048) structural-diff pattern; `revoked_at` IS the WORM-permitted UPDATE
3. **Abstract `ByokDelegationError` base + thin siblings** (v2 refinement of brainstorm #G10 cause-widen; mirrors `MissingByokKeyError` precedent; one catch-site `instanceof` clause per Kieran)
4. 60s grace post-revoke; tokens after grace debit grantee at LEDGER level (cost-shift accounting fiction — Anthropic charges what it charges; ledger records accountability)
5. Workspace-scoped (not org-scoped) grants
6. Same-workspace enforcement via TRIGGER (not CHECK; `is_workspace_member` VOLATILE)
7. **Dedicated `check_byok_delegation_cap` RPC** for cap enforcement (v2 — NOT extension of `record_byok_use_and_check_cap`; avoids the grantor/grantee per-founder SUM-window attribution bug; per-founder kill-switch wiring globally deferred to PR-G #3947)
8. **Rolling 24h cap window** (v2 — matches existing kill-switch idiom)
9. **Admin-form RPCs only for PR-A** (v2 — self-form ships in PR-B with UI consumer; admin-form requires `p_actor_user_id` for audit chain per Kieran P1)

#### PR body checklist

- Title: `feat(byok): PR-A — byok_delegations migration + SQL resolver + sentinel sweep + cap enforcement + CLI (Ref #4232)`
- `Ref #4232` (NOT `Closes` — PR-B still pending)
- Sentinel sweep enumeration (5 sites)
- Type widening sweep result
- Migration 062 LAWFUL_BASIS + RETENTION inline
- ADR link
- "v2 plan-review refinements" note (kill-switch re-arch, abstract base, admin-only RPCs, rolling 24h)

## Files to Create

| Path | Purpose | Phase |
|------|---------|-------|
| `apps/web-platform/supabase/migrations/062_byok_delegations.sql` | Table + triggers + RPCs | 1-2 |
| `apps/web-platform/supabase/migrations/062_byok_delegations.down.sql` | Reverse migration | 3 |
| `apps/web-platform/server/byok-resolver.ts` | TS wrapper + abstract error hierarchy | 4 |
| `apps/web-platform/scripts/byok-grant.ts` | CLI grant (admin-form) | 7 |
| `apps/web-platform/scripts/byok-revoke.ts` | CLI revoke (admin-form) | 7 |
| `apps/web-platform/test/server/byok-delegations.test.ts` | Table-driven RLS + WORM + revoke + cap + member-departure + anonymise + pg_default_acl | 8 |
| `apps/web-platform/test/server/byok-resolver.test.ts` | Resolver semantics | 8 |
| `apps/web-platform/test/migration/062_byok_delegations.migration.test.ts` | Real-DB migration smoke | 8 |
| `knowledge-base/project/adrs/<NN>-byok-delegations-resolver-and-grace.md` | ADR | 8 |

## Files to Edit

| Path | Edits | Phase |
|------|-------|-------|
| `apps/web-platform/server/byok-lease.ts` | Widen ByokLeaseArgs + ByokLease with `delegationId?: string`; thread into lease slot | 4 |
| `apps/web-platform/server/agent-runner.ts` | 2 sentinel sweep sites (:882, :2401) + cost-writer call args | 5 |
| `apps/web-platform/server/cc-dispatcher.ts` | 1 sentinel sweep site (:890) + cost-writer call args | 5 |
| `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` | 1 sentinel sweep site (:199) | 5 |
| `apps/web-platform/server/inngest/functions/github-on-event.ts` | 1 sentinel sweep site (:208) | 5 |
| `apps/web-platform/server/cost-writer.ts` | Extend `persistTurnCost`; call `check_byok_delegation_cap` then `write_byok_audit` with delegation_id; throw sibling errors | 5 |
| `apps/web-platform/server/account-delete.ts` | Add phase 5.9 anonymise-byok-delegations call | 6 |
| `apps/web-platform/package.json` | Add `byok-grant`, `byok-revoke` scripts | 7 |
| `apps/web-platform/lib/feature-flags/server.ts` | Add FLAG_BYOK_DELEGATIONS + isByokDelegationsEnabled | 7 |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Migration 062 applies cleanly to **dev-Supabase** (via `mcp__plugin_supabase_supabase__apply_migration` against dev project only — NEVER prd per `hr-dev-prd-distinct-supabase-projects`)
- [ ] Migration 062 down.sql reverses cleanly in dev-Supabase
- [ ] All 5 `runWithByokLease` call sites wrapped with `resolveKeyOwnerThenLease`; PR body enumerates each + non-conversion rationale (zero non-conversion expected)
- [ ] Type widening sweep: `ByokLeaseArgs.delegationId` + `ByokLease.delegationId` added; PR body lists every consumer + handling
- [ ] `mapByokLeaseCauseToErrorCode` and `ByokLeaseError.cause` enum UNCHANGED — abstract sibling error hierarchy adopted
- [ ] CLI E2E in dev: `doppler run -p soleur -c dev -- bun run byok-grant -- --actor jean@jikigai.com --grantor jean@jikigai.com --to harry@jikigai.com --workspace auto --cap-cents 2000` returns delegation_id; `byok-revoke -- --id $ID --actor jean@jikigai.com --reason admin_revoke` succeeds
- [ ] `byok-delegations.test.ts` passes (all cases — RLS dual-shape, WORM, revoke-grace timing, cap-exceeded, member-departure, anonymise, pg_default_acl audit)
- [ ] `byok-resolver.test.ts` passes
- [ ] `062_byok_delegations.migration.test.ts` passes (apply + down + re-apply)
- [ ] Art. 17 cascade test: `account-delete.ts` phase 5.9 invokes `anonymise_byok_delegations` before phase 6 `auth.admin.deleteUser`
- [ ] ADR created via `/soleur:architecture create` and committed
- [ ] `bun run typecheck` exits 0
- [ ] `bun test` exits 0
- [ ] CPO sign-off acknowledged in PR body (single-user-incident threshold)
- [ ] CLO + CTO sign-offs carry-forward cited (link to brainstorm `## Domain Assessments`)
- [ ] `FLAG_BYOK_DELEGATIONS` verified `0` in prd Doppler (`doppler secrets get FLAG_BYOK_DELEGATIONS -c prd`)
- [ ] PR body uses `Ref #4232` (NOT `Closes`)

### Post-merge (operator + auto)

- [ ] Migration 062 applied to prd via `web-platform-release.yml#migrate` (auto-triggered; verify with `gh run watch`)
- [ ] PostgREST schema reload post-apply (container restart per learning `2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md`)
- [ ] Sentry alert rule created with distinct action shape for `art_33_breach=true` tag (one-time; automatable via Sentry API in follow-up)
- [ ] Issue #4232 stays OPEN until PR-B lands

## Test Strategy

- **Runner**: vitest (per `package.json scripts.test`; verified Phase 0 step 11)
- **Real-DB integration** required (per learning `2026-05-17-mocked-tests-miss-shared-table-schema-gaps.md`); dev-Supabase only
- **Fixture isolation** (Kieran P2): every test file has `beforeEach` that TRUNCATEs `byok_delegations` + `audit_byok_use` (rows with `delegation_id IS NOT NULL`) + synthesizes its own grantor/grantee/workspace via a fixture helper; documented in test file headers
- **RLS dual-shape**: explicit 42501 (grant) vs 42P17 (policy) per learning `2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape.md`
- **Time-boundary tests**: controlled clock for revoke-grace; document the exact technique used (`pg_sleep` + statement-timestamp manipulation or a clock-mocking helper)
- **pg_default_acl audit**: single assertion in the main test suite; folded per Simplicity P1-5

## Risks

- **R1 (HIGH).** Cross-tenant grant via RLS or trigger gap → Art. 33 72h breach. **Mitigation:** DB-level `byok_delegations_check_same_workspace` TRIGGER + Sentry event with `art_33_breach` tag + dedicated Slack action shape + integration test asserting both rejection AND Sentry capture.
- **R2 (HIGH).** Revoke-grace timing mis-implementation → grantor billed for hours after revoke. **Mitigation:** per-write `check_byok_delegation_cap` re-check; integration test with +30s / +90s timing.
- **R3 (HIGH).** Cost-attribution shift on post-grace path is a **ledger fiction**, NOT actual cost recovery. Anthropic IS charging grantor's key in the moment; debiting caller at ledger level only protects the per-founder kill-switch invariant (which is unwired in PR-A — see R7). The plan body, PR body, and operator-facing UI (PR-B) MUST surface this clearly. **Mitigation:** explicit documentation; eventual reconciliation flow tracked as follow-up issue post-PR-A.
- **R4 (MEDIUM).** Cap accounting double-counts on Inngest retries. **Mitigation:** `audit_byok_use.invocation_id UNIQUE` (Phase 0 step 9 verifies; if absent, mig 062 adds it); `check_byok_delegation_cap` does `SELECT FOR UPDATE` on the delegation row so concurrent calls serialize.
- **R5 (MEDIUM).** New error sibling classes need consumer grep. **Mitigation:** abstract `ByokDelegationError` base + one `instanceof ByokDelegationError` catch clause per site; consumer grep in PR body lists every catch site.
- **R6 (LOW).** `pg_default_acl` audit miss → new RPC EXECUTE-able by `authenticated` by default. **Mitigation:** fold-in audit assertion in `byok-delegations.test.ts` (per Simplicity P1-5) + explicit `REVOKE ALL FROM PUBLIC, anon, authenticated` on every new function.
- **R7 (MEDIUM).** Per-founder hourly kill-switch is NOT wired in PR-A (v2 re-architecture). A pathological agent loop on the delegated path could run to the per-delegation daily cap with no upstream brake. **Mitigation:** per-delegation cap IS the brake; PR-G (#3947) wires the per-founder global cap; operator runbook acknowledges the temporary surface.
- **R8 (LOW).** CLI service-role admin RPC could be abused by compromised CI/agent (Kieran P1). **Mitigation:** `p_actor_user_id` required; persists as `created_by_user_id`; future follow-up adds a `byok_admin_audit` table for caller-IP/host tracking.
- **R9 (LOW).** Doppler flag flip needs redeploy. **Mitigation:** operator runbook documents both steps.
- **R10 (LOW).** PostgREST schema-cache stale post-apply. **Mitigation:** container restart in post-apply runbook.

## Observability

```yaml
liveness_signal:
  what: byok-resolver dispatch count + check_byok_delegation_cap invocation rate
  cadence: per-turn (one resolver call + zero-or-one cap-check call per turn)
  alert_target: Sentry transaction telemetry + pino → Better Stack (existing pipeline per repo convention)
  configured_in: apps/web-platform/server/byok-resolver.ts (pino childLogger "byok-resolver") + apps/web-platform/server/cost-writer.ts (existing pino "cost-writer")

error_reporting:
  destination: Sentry via reportSilentFallback wrapper (apps/web-platform/server/observability.ts)
  fail_loud: yes — no silent swallow on cross-tenant violation, post-grace charge, cap-exceeded, or resolver SQL failure

failure_modes:
  - mode: cross-tenant insert attempted
    detection: P0001 from byok_delegations_check_same_workspace trigger; TS catches and throws ByokDelegationCrossTenantError
    alert_route: Sentry feature=byok-delegations op=cross-tenant-violation level=error tags={art_33_breach: "true"} → dedicated Slack channel
  - mode: delegation revoked past 60s grace
    detection: P0001 ^byok_delegations:revoked_post_grace from check_byok_delegation_cap; TS throws ByokDelegationRevokedError
    alert_route: Sentry feature=byok-delegations op=revoke-past-grace level=warning
  - mode: delegation cap exceeded
    detection: P0001 ^byok_delegations:cap_exceeded; TS throws ByokDelegationCapExceededError
    alert_route: Sentry feature=byok-delegations op=cap-exceeded level=info (expected boundary)
  - mode: member-departure auto-revoke fired
    detection: byok_delegations.revocation_reason='member_departed' UPDATE event
    alert_route: pino breadcrumb (info); no Sentry — expected lifecycle event
  - mode: resolver SQL failure
    detection: byok-resolver.ts catches non-PGRST errors; falls back to direct runWithByokLease
    alert_route: reportSilentFallback feature=byok-resolver op=sql-failure level=warning

logs:
  where: pino childLogger "byok-resolver" + "cost-writer" (existing) + "byok-lease" (existing)
  retention: 30d (existing Better Stack ingestion via pino transport)

discoverability_test:
  command: |
    doppler run -p soleur -c dev -- bash -c '
      set -euo pipefail
      grant=$(bun run byok-grant -- --actor jean@jikigai.com --grantor jean@jikigai.com --to harry@jikigai.com --workspace auto --cap-cents 100 2>&1)
      id=$(echo "$grant" | jq -r .delegation_id)
      [[ -n "$id" && "$id" != "null" ]] && echo "grant_success: $id"
      bun run byok-revoke -- --id "$id" --actor jean@jikigai.com --reason admin_revoke 2>&1 | grep -q revoke_success && echo "revoke_success: $id"
    '
  expected_output: |
    grant_success: <uuid>
    revoke_success: <uuid>
```

No `ssh ` in `discoverability_test.command`.

## Open Code-Review Overlap

- **#3243** (`arch: decompose cc-dispatcher.ts into focused modules`) — **Acknowledge.** PR-A adds 1 line to `cc-dispatcher.ts:890`; decomposition is a separate refactor cycle. #3243 stays open.
- **#3242** (`review: tool_use WS event lacks raw name field`) — **Acknowledge.** PR-A does not touch WS events. #3242 stays open.

## Infrastructure (IaC)

### Doppler-config changes

- New env var `FLAG_BYOK_DELEGATIONS` (`0` in prd, `1` in dev). One-time `doppler secrets set` per Phase 7 — canonical feature-flag convention; not new infrastructure.
- New env var `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS` (jikigai org UUID for day one).

### Apply path

- Migration apply: existing `web-platform-release.yml#migrate` handles mig 062 on merge to main. No new pipeline.

### Distinctness / drift safeguards

- `dev` and `prd` are distinct Supabase projects (existing per `hr-dev-prd-distinct-supabase-projects`).
- `FLAG_BYOK_DELEGATIONS=0` in prd locks the resolver in fast-path; the entire `byok_delegations` table is inert until operator flips.

### Vendor-tier reality check

- Doppler Developer (free) covers new env vars.
- Supabase Pro (existing) covers the new table + indexes + triggers + RPCs.
- Anthropic: no new account/tier.

## Sharp Edges (v2 — trimmed from 8 to 5; cut 3 generic items)

- **WORM trigger structural-diff is load-bearing.** Every legitimate field-change combo (revoke flip + Art. 17 anonymise) must be enumerated. v2 collapses the member-departure variant by setting `revoked_by_user_id = OLD.user_id` instead of NULL — no Shape 1' edge case.
- **`byok-resolver.ts` must complete the SQL call BEFORE opening the ALS scope.** Do NOT `await` inside the `runWithByokLease` body. Per learning `2026-04-27-widen-async-contract-instead-of-deferred-construction-proxy.md`.
- **CLI uses service-role; admin-form RPCs required.** Self-form RPCs are NOT shipped in PR-A. CLI must pass `--actor`; the RPC persists it as `created_by_user_id` for the security audit chain.
- **`check_byok_delegation_cap` cap-exceeded path does NOT insert an audit row.** Audit row inserts via `write_byok_audit` only after cap-check passes (or on the post-grace/expired branches with attribution shifted to caller). Cap-exceeded blocks before the Anthropic call → no charge → no ledger entry. Tests verify both.
- **Abstract `ByokDelegationError` catch sites:** every `catch (err)` site that handles `ByokLeaseError` or `MissingByokKeyError` needs an additional `instanceof ByokDelegationError` clause to capture all delegation-related errors with ONE branch. The `.reason` discriminator distinguishes the four cases inside that branch. PR body enumerates every site.

## Non-Goals (carry from spec)

- NG1: Per-action ACLs.
- NG2: Time-window auto-expiry scheduler (`expires_at` column ships but no auto-cleanup cron).
- NG3: Multi-grantor delegations on same grantee.
- NG4: `prefer_delegation` boolean column.
- NG5: Out-of-band reimbursement workflow.
- NG6: Mid-token stream abort via AbortController.
- NG7: Per-grantee dashboard for grantee.
- NG8: Cap aggregation across multiple delegations from same grantor.
- NG9: Materialized view for `byok_delegations_active`.
- NG10: UI grant-from-global-settings.
- **NG11 (v2):** `_as_self` RPCs (defer to PR-B atomically with UI consumer).
- **NG12 (v2):** Per-founder hourly kill-switch global wiring (defer to PR-G #3947).
- **NG13 (v2):** `byok_admin_audit` caller-IP/host tracking table (R8 follow-up).

PR-B Non-Goals additionally apply (deferred to PR-B plan): UI surfaces (G17-G20), legal docs (G21-G23), DSAR runbook update (G24).

## References

- Spec: `knowledge-base/project/specs/feat-byok-delegations-4232/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md`
- Parent brainstorm: `knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md`
- Issue: #4232 · Parent issue (closed): #4229 · Draft PR: #4290
- Lease cite: `apps/web-platform/server/byok-lease.ts:101-112`
- WORM precedent: `apps/web-platform/supabase/migrations/048_scope_grants.sql`
- RLS helper: `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql:115-140`
- Cap-RPC precedent (NOT extended; v2 adds dedicated `check_byok_delegation_cap` instead): `apps/web-platform/supabase/migrations/061_byok_audit_workspace_id_rpcs.sql:81-148`
- Anonymise orchestrator: `apps/web-platform/server/account-delete.ts:75-300`
- Feature-flag module: `apps/web-platform/lib/feature-flags/server.ts`
- Workspace resolver: `apps/web-platform/server/workspace-resolver.ts:66`
- CLI precedent: `apps/web-platform/scripts/cla-backfill-evidence.ts`
- Sentry wrapper: `apps/web-platform/server/observability.ts`
- Plan-review findings folded: DHH (P0×2, P1×3, P2×2) + Kieran (P0×2, P1×3, P2×2) + Simplicity (P0×3, P1×4, P2×3) — all applied per operator decision "Apply all" 2026-05-22
