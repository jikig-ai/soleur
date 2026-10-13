---
title: "BYOK Delegations PR-A — Migration 064 + SQL Resolver + Sentinel Sweep + Cap Enforcement + CLI"
status: planned
issue: 4232
parent_issue: 4229
spec: knowledge-base/project/specs/feat-byok-delegations-4232/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md
branch: feat-byok-delegations-4232
pr: 4290
date: 2026-05-22
revisions:
  - v1 — initial draft
  - "v2 — 3-agent plan-review (DHH+Kieran+Simplicity) applied"
  - "v3 — deepen-plan triad (data-integrity-guardian + security-sentinel + architecture-strategist) applied"
lane: cross-domain
brand_survival_threshold: single-user incident
requires_clo_signoff: true
requires_cpo_signoff: true
requires_cto_signoff: true
requires_adr: true
detail_level: a_lot
estimate_days: "4-5"
---

# Plan: BYOK Delegations PR-A — Foundations + Resolver + Sentinel Sweep + Cap + CLI (v3)

## Overview

PR-A of the byok-delegations feature (#4232). Ships every dependency for the dogfood trigger ("Harry the intern starts; Jean wants to fund Harry's runs") in CLI form, behind `FLAG_BYOK_DELEGATIONS`. PR-B (separate plan) adds UI surfaces + Delegation Consent Side Letter (parallel-tracked); both land before the flag flips ON in prd.

The lease split at `apps/web-platform/server/byok-lease.ts` (PR #4225) was designed for this; the `MissingByokKeyError` ADR comment at `byok-lease.ts:101-112` cites #4232 by number. This work flips that "NEVER falls back" to "only with an active, unexpired, unrevoked, under-cap, same-workspace delegation row."

PR-A is **additive for solo users**: all 5 prod `runWithByokLease` sites currently pass `args.userId` for both fields (N2 invariant). The new resolver returns `(callerUserId, NULL)` for any caller with their own `api_keys` row, preserving solo behavior bit-for-bit.

**Revision history:** v1 → v2 was a 3-agent plan-review pass (DHH+Kieran+Simplicity). v2 → v3 is a deepen-plan triad pass (data-integrity-guardian + security-sentinel + architecture-strategist) that surfaced 7 P0 architectural concerns the earlier reviews missed — chiefly the resolver's wrong-workspace inference (DIG F3), the cap-check concurrency hole (DIG F4), `now()`-vs-`clock_timestamp()` (SS F1), unbounded cap (SS F2), WORM Shape 1 audit-poisoning (DIG F1), no per-founder brake at single-user threshold (Arch A1), and missing reconciliation data substrate (Arch A2).

## Research Reconciliation — Spec vs. Codebase

| # | Spec claim | Codebase reality (verified) | Plan response (v3) |
|---|---|---|---|
| 1 | "5 prod `runWithByokLease` sites need updating" | Confirmed: `cc-dispatcher.ts:890`, `agent-runner.ts:882`, `agent-runner.ts:2401`, `cfo-on-payment-failed.ts:199`, `github-on-event.ts:208`. ALL pass identical `userId` for both fields (N2 invariant). | Sentinel sweep wraps each with `resolveKeyOwnerThenLease`. Resolver fast-path under flag OFF / solo user returns `(userId, NULL)` — zero behavior change. |
| 2 | "Widen `ByokLeaseError.cause` enum" (brainstorm #G10) | `MissingByokKeyError` at `byok-lease.ts:75-113` is sibling-class precedent. | **v2 refinement:** abstract base `ByokDelegationError` + thin siblings (`Revoked`/`Expired`/`CapExceeded`/`CrossTenant`) with `.reason` discriminator. Catch sites: one `instanceof` check. Confirmed sound by architecture-strategist (Arch P1 #4 — "right at 10-month horizon"). |
| 3 | "Extend `record_byok_use_and_check_cap`" (spec G7) | Zero TS callers today. Current cap is per-founder hourly kill-switch grouped by `founder_id`. | **v3 re-architecture:** add NEW `check_and_record_byok_delegation_use` RPC that ATOMICALLY does (a) `SELECT FOR UPDATE` on `byok_delegations` row, (b) grace + expired + hourly cap + daily cap checks, (c) INSERT audit row — all in one txn under the row lock. Merges what v2 had as two separate RPCs (`check_byok_delegation_cap` + `write_byok_audit`) to close the SUM-then-INSERT race window (DIG F4). Per-delegation HOURLY cap (`hourly_usd_cap_cents`, default daily/4) added as secondary brake since the per-founder kill-switch stays unwired in PR-A (Arch A1). `record_byok_use_and_check_cap` itself is NOT touched. |
| 4 | "DB-level CHECK same_workspace" (spec G3) | `is_workspace_member` is plpgsql VOLATILE. | Implement as BEFORE INSERT OR UPDATE TRIGGER. Raises P0001 `byok_delegations:cross-tenant`; Sentry tag `art_33_breach: "true"`. |
| 5 | "WORM precedent is scope_grants mig 048" | Confirmed at mig 048:42-115. Structural-diff bypass. | Mirror. **v3 additions:** (a) Shape 1 audit-attribution constraint `NEW.revoked_by_user_id IN (NEW.grantor_user_id, NEW.grantee_user_id, NEW.created_by_user_id)` — closes audit-ledger poison (DIG F1); (b) Shape 2 also nulls `workspace_id` together — enables future workspace-delete cascade (DIG F6); (c) **new Shape 3: cap-update flip** — `daily_usd_cap_cents` and/or `hourly_usd_cap_cents` may transition via WORM-permitted update accompanied by non-NULL `cap_updated_at` + `cap_updated_by_user_id`; everything else unchanged. Enables "raise Harry's budget" UX without breaking audit chain (Arch A6). |
| 6 | "Workspace ID resolution from userId" | `workspace-resolver.ts:66` `getDefaultWorkspaceForUser`. | **v3 fix:** TS layer derives `workspace_id` via `getDefaultWorkspaceForUser(workspaceContextUserId)` BEFORE calling SQL resolver. `resolve_byok_key_owner` now takes `p_workspace_id uuid NOT NULL` as explicit param (no JOIN inside SQL). Closes DIG F3 (wrong-workspace inference for multi-workspace grantees). The TS layer knows the caller's intended workspace unambiguously; SQL function would have to guess. |
| 7 | "Member-departure auto-revoke" (spec G12) | DELETE on workspace_members only via `remove_workspace_member` RPC (mig 058:320) and anonymise cascade. | DB trigger AFTER DELETE — covers both paths. Sets `revoked_by_user_id = OLD.user_id`. **v3:** the WORM Shape 1 attribution constraint (#5(a)) is satisfied because `OLD.user_id` IS either grantor or grantee of the row (trigger WHERE clause filters by that). |
| 8 | "Art. 17 cascade integration" (spec G13) | `auth.admin.deleteUser` at `account-delete.ts:448`. | Add `anonymise_byok_delegations(p_user_id)` UK-spelled, service-role-only. Wire as phase 5.9 IN-PR per learning `2026-05-16-migration-mandates...`. **v3:** anonymise also nulls `workspace_id` (matches Shape 2 expansion). |
| 9 | "CLI grant/revoke" (spec G11) | `scripts/*.ts` precedents: bun shebang + hand-rolled argv + service-role. | **v3:** PR-A ships **consolidated** `grant_byok_delegation` + `revoke_byok_delegation` RPCs that branch on `auth.uid() IS NULL` (service-role → admin path with `p_actor_user_id`; authenticated → self path with `auth.uid()` enforcement). One RPC per verb, not two (Arch A3 — halves the surface). CLI uses service-role; UI in PR-B uses authenticated. CLI gets interactive confirmation prompt + `--yes` flag for CI (SS F5 — typo at single-user threshold IS the incident). |
| 10 | "Feature flag" (spec G15) | Canonical module + sibling `team-workspace-invite` precedent. | `FLAG_BYOK_DELEGATIONS` + two-key gate with `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS`. Release-time assertion that allowlist parses to UUIDs only with count ≤ N ceiling (SS F8 defense-in-depth). |
| 11 | "pg_default_acl audit" (spec TR4) | Zero existing test. | Folded into main suite as ONE assertion using the canonical query (DIG F8 captured): `SELECT n.nspname, d.defaclrole::regrole, d.defaclobjtype, d.defaclacl FROM pg_default_acl d JOIN pg_namespace n ON d.defaclnamespace = n.oid WHERE n.nspname = 'public'` + `pg_proc aclexplode(proacl)` for new RPCs. |
| 12 | "RLS deny-test dual-shape" (spec TR6) | Pattern exists but undisaggregated. | Canonical strict test in `byok-delegations.test.ts`. |
| 13 | "Migration down.sql" | Established for mig 053+. | Required. |
| 14 | "Sentry tagging on cross-tenant" (spec FR7) | `reportSilentFallback` canonical wrapper. | **v3 hardening:** use HMAC-SHA256 with server-side `SENTRY_TAG_PEPPER` Doppler secret (not raw SHA-256) — small-population reversibility risk per SS F6. Distinct Sentry action shape with `art_33_breach: "true"` per learning `2026-05-17-...-dedup-on-action-match-not-conditions.md`. |
| 15 | "WORM table grants" | mig 048/058 pattern. | Mirror. Single consolidated RPCs (per #9) GRANT EXECUTE to BOTH `authenticated` AND `service_role` since they branch internally on `auth.uid()`. |
| 16 | "Resolver returns one row" | PostgREST `.single()` raises PGRST116 on zero rows. | Use `.maybeSingle()`. |
| 17 | "Cap window: UTC midnight" | Existing kill-switch uses rolling `interval '1 hour'`. | Rolling 24h window matches existing idiom. |
| 18 | "now() vs clock_timestamp() for grace check" | `now()` returns transaction-start timestamp. | **v3 fix:** use `clock_timestamp()` for grace + expires comparisons in `check_and_record_byok_delegation_use` (SS F1). Defense against long-running txn opened pre-revoke seeing "within grace" wrongly. |
| 19 | "Cap upper bound" (spec implied no ceiling) | Table CHECK `> 0` only — admits $10B/day. | **v3 fix:** table CHECK `daily_usd_cap_cents BETWEEN 1 AND 1000000` ($10K/day ceiling) + RPC body guard with distinct SQLSTATE for clean error (SS F2). Brand-survival floor at single-user threshold. |
| 20 | "Per-founder brake on delegated path" | Spec defers to PR-G #3947. | **v3 addition:** `hourly_usd_cap_cents NOT NULL CHECK (BETWEEN 1 AND daily_usd_cap_cents)` column on `byok_delegations` (default daily/4). Same RPC, same FOR UPDATE row lock checks hourly AND daily. Secondary brake without PR-G dependency (Arch A1). |
| 21 | "Reconciliation data substrate" | No way to identify post-grace audit rows. | **v3 addition:** `audit_byok_use.attribution_shift_reason text NULL CHECK IN ('revoked_post_grace','expired')`. Eventual reconciliation flow (post-PR-A) reads this column to know which rows need cost-shift bookkeeping (Arch A2). |
| 22 | "Resolver `p_caller_user_id` trust" | RPC is service-role; trusts TS-supplied value. | **v3 invariant comment:** `byok-resolver.ts` carries a load-bearing comment: `callerUserId` MUST be server-derived (session/JWT), NEVER from request body/params. Write-boundary sentinel sweep in PR body lists `resolveKeyOwnerThenLease` call sites + provenance of `callerUserId` at each (SS F3). |
| 23 | "WORM trigger fail-OPEN on column additions" | Structural-diff trigger enumerates columns explicitly. | **v3 hardening:** WORM column-enumeration smoke test introspects `information_schema.columns` vs `pg_get_functiondef(WORM_trigger)` and fails loudly when they diverge (SS F4). Catches future migrations that add columns without updating the trigger. |

## Research Insights

**Codebase patterns mirrored (all verified):**

- WORM trigger structural-diff: `apps/web-platform/supabase/migrations/048_scope_grants.sql:42-115`
- `is_workspace_member` 2-arg plpgsql VOLATILE: `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql:115-140`
- `write_byok_audit` 6-arg RPC (precedent shape; NOT extended in v3): `apps/web-platform/supabase/migrations/061_byok_audit_workspace_id_rpcs.sql:34-78`
- Cost-writer `persistTurnCost`: `apps/web-platform/server/cost-writer.ts:1-80`
- Anonymise orchestrator: `apps/web-platform/server/account-delete.ts:75-300`
- Feature-flag module: `apps/web-platform/lib/feature-flags/server.ts`
- Workspace resolution: `apps/web-platform/server/workspace-resolver.ts:66`
- ByokLeaseError sibling-class precedent: `MissingByokKeyError` at `byok-lease.ts:75-113`
- CLI script convention: `apps/web-platform/scripts/cla-backfill-evidence.ts`
- Sentry wrapper: `apps/web-platform/server/observability.ts`

**Institutional learnings folded (v1+v2+v3):**

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

**If this leaks, the user's data/workflow/money is exposed via:** RLS or same_workspace trigger gap lets a member of OrgA insert a `byok_delegations` row naming a user in OrgB as grantor; that stranger now leases Jean's Anthropic key. GDPR Art. 33 territory (72h notification clock).

**Brand-survival threshold:** `single-user incident`.

CPO sign-off required. CLO + CTO carry forward from brainstorm. `user-impact-reviewer` agent at PR-review time per `plugins/soleur/skills/review/SKILL.md`.

## Domain Review

**Domains relevant:** Product (CPO), Engineering (CTO), Legal (CLO). Carried forward from brainstorm.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** PR-A is CLI-only, dogfood scope. UI defers to PR-B.

### Engineering (CTO)

**Status:** reviewed (v3 with deepen-plan refinements)
**Assessment:** Resolver-and-table change. v3 refinements: (a) merged atomic `check_and_record_byok_delegation_use` RPC closes cap-check concurrency hole, (b) `clock_timestamp()` not `now()` for grace, (c) TS-layer workspace derivation closes the wrong-workspace inference bug, (d) hourly+daily cap brake closes the missing-per-founder-brake gap, (e) abstract sibling error hierarchy, (f) admin-only RPCs consolidated to single RPCs branching on `auth.uid()`, (g) WORM Shape 3 enables in-place cap updates without breaking audit continuity, (h) WORM column-enumeration smoke catches future fail-OPEN. ADR required (Phase 5).

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Delegation Consent Side Letter + DPD §2.3 + AUP §5.6 ship in PR-B. PR-A migration carries `LAWFUL_BASIS: Art. 6(1)(b)` + `RETENTION: 7y`. Flag-OFF in prd until PR-B + signed Side Letter.

### Product/UX Gate

**Tier:** NONE. PR-A has no UI surface.

**Agents invoked at plan-time:** repo-research-analyst, learnings-researcher (Phase 1); gdpr-gate (Phase 2.7 — zero Critical/Important findings); DHH + Kieran + Simplicity plan-review (v2); data-integrity-guardian + security-sentinel + architecture-strategist deepen-plan (v3 — all applied). user-impact-reviewer at PR-review time.

## Implementation Phases (v3 — 5 phases, collapsed from 8)

### Phase 0 — Preconditions

1. Worktree clean; branch correct.
2. 5 call sites unchanged (`runWithByokLease` grep).
3. `byok-lease.ts:58-75`, `:88-113`, `:182-196` read; sibling-class precedent confirmed.
4. `record_byok_use_and_check_cap` STILL has zero TS callers (v3 path doesn't touch it).
5. `persistTurnCost` 2 known sites confirmed.
6. `lib/feature-flags/server.ts` FLAG_VARS + `isTeamWorkspaceInviteEnabled` two-key gate read.
7. `account-delete.ts:75-300` cascade chain read; phase 5.9 insertion point confirmed.
8. `workspace-resolver.ts:66` `getDefaultWorkspaceForUser` read.
9. `audit_byok_use.invocation_id UNIQUE` constraint verified in mig 037 (R4 idempotency). If absent, add to mig 064.
10. `SENTRY_TAG_PEPPER` exists in Doppler dev + prd (SS F6 prereq); if absent, add to operator-runbook Phase 4 prereq.
11. dev-Supabase shows 053-063 applied; 064 not yet. If 064 already applied with different shape (sibling worktree race), introspect via `mcp__plugin_supabase_supabase__execute_sql` and reconcile before proceeding (DIG F9). **Note (rebase reconciliation 2026-05-22 → 2026-05-23):** plan-time slot was 062; first rebase showed `062_workspace_member_removals_and_remove_rpc_update.sql` landed (renumbered 062→063); second rebase 24h later showed `063_workspace_member_actions.sql` (#4231) AND `063_post_workspace_rpc_repair.sql` (#4339) BOTH landed on the same 063 slot — sibling-PR collision class. Renumbered 063→064 across plan/spec/tasks/brainstorm/ADR/migration filenames/test refs; account-delete.ts phase 3.93 (workspace_member_actions, sibling-owned) preserved + phase 3.94 (byok_delegations, ours) inserted after.
12. Baseline `bun run typecheck` clean; capture `bun test` baseline pass count.

### Phase 1 — Migration 064: Full Schema (Table + All Triggers + All RPCs)

**File:** `apps/web-platform/supabase/migrations/064_byok_delegations.sql`

Migration header: `LAWFUL_BASIS: Art. 6(1)(b) contract` + `RETENTION: 7 years` + trigger-not-CHECK rationale (Research Reconciliation row 4) + WORM-column-enumeration sentinel reminder.

#### Table `public.byok_delegations`

| Column | Type | Notes (v3 changes marked) |
|---|---|---|
| `id` | `uuid PK default gen_random_uuid()` | |
| `grantor_user_id` | `uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT` | |
| `grantee_user_id` | `uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT` | CHECK `<> grantor_user_id` |
| `workspace_id` | `uuid NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT` | |
| `daily_usd_cap_cents` | `int NOT NULL CHECK (BETWEEN 1 AND 1000000)` | **v3:** $10K/day ceiling (SS F2) |
| `hourly_usd_cap_cents` | `int NOT NULL` | **v3:** secondary brake (Arch A1). CHECK `BETWEEN 1 AND daily_usd_cap_cents` |
| `created_by_user_id` | `uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT` | |
| `created_at` | `timestamptz NOT NULL DEFAULT now()` | |
| `expires_at` | `timestamptz NULL` | CHECK `> created_at` |
| `revoked_at` | `timestamptz NULL` | CHECK `>= created_at` |
| `revoked_by_user_id` | `uuid NULL REFERENCES users(id) ON DELETE RESTRICT` | |
| `revocation_reason` | `text NULL CHECK IN (...)` | values: `grantor_revoke / grantee_decline / member_departed / admin_revoke / art_17_anonymise` |
| `cap_updated_at` | `timestamptz NULL` | **v3:** Shape 3 update marker (Arch A6) |
| `cap_updated_by_user_id` | `uuid NULL REFERENCES users(id) ON DELETE RESTRICT` | **v3:** Shape 3 actor |

Indexes:
- Partial unique `(grantor_user_id, grantee_user_id, workspace_id) WHERE revoked_at IS NULL`. **v3:** drop the `expires_at > now()` clause from the predicate per DIG F10 — Postgres doesn't re-evaluate partial-index predicates against `now()` after INSERT, so the v2 form would stay stale and block re-grant after expiry.
- `(grantee_user_id, workspace_id) WHERE revoked_at IS NULL` for resolver hot path.

#### `audit_byok_use` column additions

```sql
ALTER TABLE public.audit_byok_use
  ADD COLUMN delegation_id uuid NULL REFERENCES public.byok_delegations(id) ON DELETE RESTRICT,
  ADD COLUMN attribution_shift_reason text NULL
    CHECK (attribution_shift_reason IS NULL OR attribution_shift_reason IN ('revoked_post_grace','expired'));

CREATE INDEX audit_byok_use_delegation_ts_idx
  ON public.audit_byok_use (delegation_id, ts)
  WHERE delegation_id IS NOT NULL;
```

#### Same-workspace trigger `byok_delegations_check_same_workspace()` (BEFORE INSERT OR UPDATE OF grantor, grantee, workspace_id)

Calls `is_workspace_member` for both grantor and grantee. Raises P0001 `byok_delegations:cross-tenant: <role> % is not a member of workspace %`. SET search_path; REVOKE ALL.

#### WORM trigger `byok_delegations_no_mutate()` — v3 with Shapes 1-3

```sql
CREATE OR REPLACE FUNCTION public.byok_delegations_no_mutate() RETURNS trigger
  LANGUAGE plpgsql SET search_path = public, pg_temp
AS $$
BEGIN
  -- Shape 2 (Art. 17 anonymise): both user_id columns + created_by + revoked_by +
  -- workspace_id all non-NULL → NULL together; cap/timestamp/reason unchanged.
  -- v3 additions: workspace_id participates in nullification (DIG F6).
  IF OLD.grantor_user_id IS NOT NULL AND NEW.grantor_user_id IS NULL
     AND OLD.grantee_user_id IS NOT NULL AND NEW.grantee_user_id IS NULL
     AND OLD.created_by_user_id IS NOT NULL AND NEW.created_by_user_id IS NULL
     AND OLD.workspace_id IS NOT NULL AND NEW.workspace_id IS NULL
     AND NOT (OLD.daily_usd_cap_cents IS DISTINCT FROM NEW.daily_usd_cap_cents)
     AND NOT (OLD.hourly_usd_cap_cents IS DISTINCT FROM NEW.hourly_usd_cap_cents)
     AND NOT (OLD.created_at IS DISTINCT FROM NEW.created_at)
     AND NOT (OLD.expires_at IS DISTINCT FROM NEW.expires_at)
     AND NOT (OLD.revoked_at IS DISTINCT FROM NEW.revoked_at)
     AND NOT (OLD.revocation_reason IS DISTINCT FROM NEW.revocation_reason)
     AND NOT (OLD.cap_updated_at IS DISTINCT FROM NEW.cap_updated_at)
     AND (NEW.revoked_by_user_id IS NULL OR OLD.revoked_by_user_id = NEW.revoked_by_user_id)
     AND (NEW.cap_updated_by_user_id IS NULL OR OLD.cap_updated_by_user_id = NEW.cap_updated_by_user_id)
  THEN RETURN NEW; END IF;

  -- Shape 1 (revoke flip): revoked_at + revoked_by_user_id + revocation_reason all
  -- NULL → non-NULL together; everything else unchanged. v3 attribution constraint
  -- (DIG F1): revoked_by_user_id MUST be one of the actor cols of THIS row.
  IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL
     AND OLD.revoked_by_user_id IS NULL AND NEW.revoked_by_user_id IS NOT NULL
     AND OLD.revocation_reason IS NULL AND NEW.revocation_reason IS NOT NULL
     AND NEW.revoked_by_user_id IN (NEW.grantor_user_id, NEW.grantee_user_id, NEW.created_by_user_id)
     AND NOT (OLD.grantor_user_id IS DISTINCT FROM NEW.grantor_user_id)
     AND NOT (OLD.grantee_user_id IS DISTINCT FROM NEW.grantee_user_id)
     AND NOT (OLD.workspace_id IS DISTINCT FROM NEW.workspace_id)
     AND NOT (OLD.daily_usd_cap_cents IS DISTINCT FROM NEW.daily_usd_cap_cents)
     AND NOT (OLD.hourly_usd_cap_cents IS DISTINCT FROM NEW.hourly_usd_cap_cents)
     AND NOT (OLD.created_by_user_id IS DISTINCT FROM NEW.created_by_user_id)
     AND NOT (OLD.created_at IS DISTINCT FROM NEW.created_at)
     AND NOT (OLD.expires_at IS DISTINCT FROM NEW.expires_at)
     AND NOT (OLD.cap_updated_at IS DISTINCT FROM NEW.cap_updated_at)
     AND NOT (OLD.cap_updated_by_user_id IS DISTINCT FROM NEW.cap_updated_by_user_id)
  THEN RETURN NEW; END IF;

  -- Shape 3 (v3 — cap update flip): daily_usd_cap_cents and/or hourly_usd_cap_cents
  -- may change accompanied by cap_updated_at + cap_updated_by_user_id non-NULL;
  -- everything else unchanged. Preserves audit continuity for "raise Harry's
  -- budget" UX (Arch A6).
  IF NEW.cap_updated_at IS NOT NULL AND NEW.cap_updated_by_user_id IS NOT NULL
     AND (OLD.daily_usd_cap_cents IS DISTINCT FROM NEW.daily_usd_cap_cents
          OR OLD.hourly_usd_cap_cents IS DISTINCT FROM NEW.hourly_usd_cap_cents)
     AND NOT (OLD.grantor_user_id IS DISTINCT FROM NEW.grantor_user_id)
     AND NOT (OLD.grantee_user_id IS DISTINCT FROM NEW.grantee_user_id)
     AND NOT (OLD.workspace_id IS DISTINCT FROM NEW.workspace_id)
     AND NOT (OLD.created_by_user_id IS DISTINCT FROM NEW.created_by_user_id)
     AND NOT (OLD.created_at IS DISTINCT FROM NEW.created_at)
     AND NOT (OLD.expires_at IS DISTINCT FROM NEW.expires_at)
     AND NOT (OLD.revoked_at IS DISTINCT FROM NEW.revoked_at)
     AND NOT (OLD.revoked_by_user_id IS DISTINCT FROM NEW.revoked_by_user_id)
     AND NOT (OLD.revocation_reason IS DISTINCT FROM NEW.revocation_reason)
  THEN RETURN NEW; END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'byok_delegations is append-only; use anonymise_byok_delegations' USING ERRCODE = 'P0001';
  END IF;
  RAISE EXCEPTION 'byok_delegations: only revoke flip, Art. 17 anonymise, or cap-update flip shapes are permitted' USING ERRCODE = 'P0001';
END;
$$;
REVOKE ALL ON FUNCTION public.byok_delegations_no_mutate() FROM PUBLIC, anon, authenticated, service_role;
-- attach BEFORE UPDATE + BEFORE DELETE
```

#### RLS

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

#### RPCs (consolidated per Arch A3)

**`grant_byok_delegation(p_grantor_user_id uuid NULL, p_grantee_user_id, p_workspace_id, p_daily_usd_cap_cents, p_hourly_usd_cap_cents, p_expires_at, p_actor_user_id uuid NULL) RETURNS uuid`**

Branches on `auth.uid() IS NULL`:
- Service-role (auth.uid() NULL): admin path. Requires `p_grantor_user_id` + `p_actor_user_id` both non-NULL. INSERT with `created_by_user_id = p_actor_user_id`.
- Authenticated (auth.uid() non-NULL): self path. `p_grantor_user_id` and `p_actor_user_id` MUST be NULL or equal `auth.uid()`. Body asserts and INSERTs with `created_by_user_id = auth.uid()`.

Body asserts cap bounds: `daily_usd_cap_cents BETWEEN 1 AND 1000000` AND `hourly_usd_cap_cents BETWEEN 1 AND daily_usd_cap_cents`. RAISE specific SQLSTATE on violation (clean CLI error).

GRANT EXECUTE to BOTH `authenticated` AND `service_role` (the branching is inside the function body).

**`revoke_byok_delegation(p_delegation_id, p_actor_user_id uuid NULL, p_reason text) RETURNS void`**

Similar branching. Constraint: `p_reason IN ('grantor_revoke','grantee_decline','admin_revoke')` only — `member_departed` and `art_17_anonymise` are reserved for the trigger / cascade (SS F9). UPDATE sets revoked_at + revoked_by_user_id + revocation_reason; relies on WORM Shape 1 attribution check enforcing `revoked_by_user_id IN (grantor, grantee, created_by)`.

**`resolve_byok_key_owner(p_caller_user_id, p_workspace_id) RETURNS TABLE(key_owner_user_id uuid, delegation_id uuid)`**

**v3 signature: `p_workspace_id` is now explicit param** (DIG F3). No JOIN inside SQL.

Body:
1. EXISTS on `api_keys WHERE user_id = p_caller_user_id` → return `(p_caller_user_id, NULL)`.
2. SELECT active delegation `WHERE grantee_user_id = p_caller_user_id AND workspace_id = p_workspace_id AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > clock_timestamp()) ORDER BY created_at DESC LIMIT 1`.
3. If found → `(grantor_user_id, id)`. Else no row.

SECURITY DEFINER service-role only.

**`check_and_record_byok_delegation_use(p_delegation_id, p_invocation_id, p_token_count, p_unit_cost_cents, p_caller_user_id, p_agent_role text) RETURNS void`** — **v3 merged atomic RPC** (DIG F4)

Body (single txn, all under one row lock):

1. `SELECT ... FOR UPDATE FROM byok_delegations WHERE id = p_delegation_id`.
2. **Grace check (v3 `clock_timestamp()`):** if `revoked_at IS NOT NULL AND clock_timestamp() > revoked_at + interval '60 seconds'`:
   - INSERT into audit_byok_use with `founder_id = p_caller_user_id, delegation_id = p_delegation_id, attribution_shift_reason = 'revoked_post_grace'`
   - RAISE EXCEPTION `byok_delegations:revoked_post_grace` SQLSTATE P0001
3. **Expired check (clock_timestamp()):** if `expires_at IS NOT NULL AND clock_timestamp() > expires_at`:
   - Same audit-write with `attribution_shift_reason = 'expired'`
   - RAISE `byok_delegations:expired`
4. **Hourly cap check:** SUM `audit_byok_use WHERE delegation_id = p_delegation_id AND ts > clock_timestamp() - interval '1 hour'`. If `spent + (token_count * unit_cost_cents) > hourly_usd_cap_cents`: RAISE `byok_delegations:hourly_cap_exceeded` (no audit row).
5. **Daily cap check:** same SUM with `interval '24 hours'` and `daily_usd_cap_cents`. If exceeded: RAISE `byok_delegations:daily_cap_exceeded` (no audit row).
6. **Pass:** INSERT audit_byok_use with `founder_id = grantor_user_id, delegation_id = p_delegation_id` (normal attribution; no shift reason).

plpgsql SECURITY DEFINER `SET search_path = public, pg_temp`. REVOKE PUBLIC/anon/authenticated; GRANT EXECUTE to service_role only.

**`anonymise_byok_delegations(p_user_id uuid) RETURNS void`**

UPDATE sets `grantor_user_id = grantee_user_id = created_by_user_id = revoked_by_user_id = NULL` AND **v3 also `workspace_id = NULL`** where user appears. WORM Shape 2 allows.

**v3 active-row guard (SS F7):** body first identifies rows where `revoked_at IS NULL`; for each, performs Shape 1 revoke-flip with `revocation_reason = 'art_17_anonymise'` + `revoked_by_user_id = p_user_id` (satisfies Shape 1 attribution constraint since p_user_id IS one of grantor/grantee). THEN performs Shape 2 anonymise. Single txn.

#### Member-departure cascade trigger

```sql
CREATE OR REPLACE FUNCTION public.byok_delegations_on_member_delete() RETURNS trigger
  LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  UPDATE public.byok_delegations
     SET revoked_at         = clock_timestamp(),
         revoked_by_user_id = OLD.user_id,
         revocation_reason  = 'member_departed'
   WHERE (grantor_user_id = OLD.user_id OR grantee_user_id = OLD.user_id)
     AND workspace_id      = OLD.workspace_id
     AND revoked_at IS NULL;
  RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION public.byok_delegations_on_member_delete() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER workspace_members_byok_delegations_revoke
  AFTER DELETE ON public.workspace_members FOR EACH ROW
  EXECUTE FUNCTION public.byok_delegations_on_member_delete();
```

Shape 1 attribution constraint is satisfied: `OLD.user_id` IS one of `grantor_user_id` or `grantee_user_id` (the WHERE clause filters by that).

#### Down migration

`apps/web-platform/supabase/migrations/064_byok_delegations.down.sql` — reverse order; restores `audit_byok_use` columns and drops table/triggers/functions cleanly.

### Phase 2 — TS Layer: byok-resolver.ts + Abstract Error Hierarchy + Type Widening + Sentry HMAC

**Files:** `apps/web-platform/server/byok-resolver.ts` (NEW) + `apps/web-platform/server/byok-lease.ts` (EDIT) + `apps/web-platform/server/observability.ts` (EDIT for HMAC helper).

#### byok-resolver.ts

```typescript
import { runWithByokLease, MissingByokKeyError, type ByokLease } from "./byok-lease";
import { createServiceClient } from "@/lib/supabase/service";
import { createChildLogger } from "@/server/logger";
import { isByokDelegationsEnabled } from "@/lib/feature-flags/server";
import { getDefaultWorkspaceForUser } from "./workspace-resolver";

const log = createChildLogger("byok-resolver");

// Abstract base — catch sites use one `instanceof ByokDelegationError` clause.
// All siblings carry .reason discriminator + shared structured fields.
export abstract class ByokDelegationError extends Error {
  public abstract readonly reason:
    | 'revoked_post_grace' | 'expired' | 'hourly_cap_exceeded' | 'daily_cap_exceeded' | 'cross_tenant';
  public readonly delegationId?: string;
  public readonly workspaceIdHash?: string;
}

export class ByokDelegationRevokedError extends ByokDelegationError { reason = 'revoked_post_grace' as const; }
export class ByokDelegationExpiredError extends ByokDelegationError { reason = 'expired' as const; }
export class ByokDelegationHourlyCapError extends ByokDelegationError { reason = 'hourly_cap_exceeded' as const; }
export class ByokDelegationDailyCapError extends ByokDelegationError { reason = 'daily_cap_exceeded' as const; }
export class ByokDelegationCrossTenantError extends ByokDelegationError { reason = 'cross_tenant' as const; }

/**
 * Resolve the BYOK key owner and run `fn`. Behavior:
 *   - Flag OFF: direct runWithByokLease (fully inert).
 *   - Flag ON: derive workspace_id from `workspaceContextUserId`, then SQL resolver.
 *   - On resolver returning own-key → standard lease.
 *   - On resolver returning delegation → lease with grantor + delegationId.
 *   - On no row → MissingByokKeyError (from lease body).
 *
 * SECURITY INVARIANT (SS F3): `callerUserId` MUST be derived from authenticated
 * session/JWT, NEVER from request body/params. Passing user-controlled input
 * here would let an attacker name an arbitrary user as caller and harvest
 * delegations targeted at that user. The 5 prod call sites pass `args.userId`
 * which IS server-derived; sentinel-sweep in PR body enumerates the provenance
 * of `callerUserId` at every call site. Future call sites MUST preserve this
 * invariant.
 */
export async function resolveKeyOwnerThenLease<T>(
  callerUserId: string,
  workspaceContextUserId: string,
  fn: (lease: ByokLease) => Promise<T>,
): Promise<T>;
```

Body:
1. `isByokDelegationsEnabled(orgIdResolvedFromCallerContext) === false` → direct `runWithByokLease({keyOwnerUserId: callerUserId, workspaceContextUserId}, fn)`.
2. Otherwise: derive `workspaceId` via `await getDefaultWorkspaceForUser(workspaceContextUserId, supabase)`. If null → direct lease (lease body raises MissingByokKeyError if no own key).
3. Call `supabase.rpc('resolve_byok_key_owner', {p_caller_user_id: callerUserId, p_workspace_id: workspaceId}).maybeSingle()`.
4. On error: log + fall through to direct lease.
5. On data null: direct lease.
6. On data: `runWithByokLease({keyOwnerUserId: data.key_owner_user_id, workspaceContextUserId, delegationId: data.delegation_id ?? undefined}, fn)`.

#### byok-lease.ts edits

1. `ByokLeaseArgs` (line 58) — add `delegationId?: string`.
2. `ByokLease` (line 198) — add `readonly delegationId?: string`.
3. `runWithByokLease` (line 338) — thread `args.delegationId` into the lease slot.
4. **No changes** to `ByokLeaseError.cause` enum.

#### observability.ts edits (SS F6)

Add helper `hashUserIdForSentryTag(userId: string): string` that uses `crypto.createHmac('sha256', process.env.SENTRY_TAG_PEPPER).update(userId).digest('hex').slice(0, 16)`. Used for all delegation-related Sentry tags (workspace_id_hash, grantor_user_id_hash, grantee_user_id_hash, delegation_id_hash). Replace SHA-256 raw at `byok-lease.ts:140-168` in a separate commit-within-PR if scope allows; otherwise file as follow-up.

### Phase 3 — Sentinel Sweep + cost-writer Threading + Cascade Wire-Up

**Files:** 5 lease-call-site files + `cost-writer.ts` + `account-delete.ts`.

#### Sentinel sweep (5 sites)

| # | Site | Conversion |
|---|------|------------|
| 1 | `agent-runner.ts:882` | `runWithByokLease({wcu, kou}, ...)` → `resolveKeyOwnerThenLease(userId, userId, ...)` |
| 2 | `agent-runner.ts:2401` | same |
| 3 | `cc-dispatcher.ts:890` | same |
| 4 | `cfo-on-payment-failed.ts:199` | same |
| 5 | `github-on-event.ts:208` | same |

PR body MUST enumerate provenance of `callerUserId` at each (SS F3): all 5 receive `args.userId` from a server-side session/JWT context — none from request body.

#### cost-writer.ts (v3 — single RPC call)

`persistTurnCost` extended with optional `delegationId?: string` + `callerUserId?: string`:

1. **If `delegationId !== undefined`:** call `supabase.rpc('check_and_record_byok_delegation_use', {p_delegation_id, p_invocation_id, p_token_count, p_unit_cost_cents, p_caller_user_id, p_agent_role})`. SINGLE atomic RPC (v3 — merged).
   - On SQLSTATE P0001 with `^byok_delegations:revoked_post_grace` → throw `ByokDelegationRevokedError` + `reportSilentFallback({feature:"byok-delegations", op:"revoke-past-grace", level:"warning", tags:{delegation_id_hash}})`. Audit row IS written (with attribution_shift_reason) by the RPC itself.
   - On `^byok_delegations:expired` → throw `ByokDelegationExpiredError`. Audit row written.
   - On `^byok_delegations:hourly_cap_exceeded` → throw `ByokDelegationHourlyCapError`. NO audit row.
   - On `^byok_delegations:daily_cap_exceeded` → throw `ByokDelegationDailyCapError`. NO audit row.
   - On success: nothing to do; audit row written.
2. **Else (delegationId undefined):** continue calling `write_byok_audit` (mig 061 6-arg form unchanged). Solo behavior preserved.
3. Update 2 known `persistTurnCost` callers:
   - `agent-runner.ts:1891` — thread `lease.delegationId` + `lease.workspaceContextUserId` (caller derived from lease scope)
   - `cc-dispatcher.ts onResult` — same

#### account-delete.ts (phase 5.9)

Insert between phase 5.8 and phase 6: call `supabase.rpc("anonymise_byok_delegations", { p_user_id: userId })` with sibling error-handling shape. Update docstring header at lines 75-82.

### Phase 4 — CLI grant/revoke + Feature Flag + WORM Smoke Test + Tests + ADR

#### CLI scripts

**`scripts/byok-grant.ts`** (NEW) — bun shebang; hand-rolled argv:

```
Usage:
  doppler run -p soleur -c dev -- bun run byok-grant -- \
    --actor jean@jikigai.com \
    --grantor jean@jikigai.com --to harry@jikigai.com \
    --workspace auto --cap-cents 2000 --hourly-cap-cents 500 \
    [--expires-in 30d] [--yes]
```

**v3 confirmation prompt** (SS F5): after resolving emails to userIds and resolving workspace, prints:

```
Granting:
  grantor: jean@jikigai.com (uuid-here)
  grantee: harry@jikigai.com (uuid-here)
  workspace: jikigai-dev (uuid-here)
  daily cap: $20.00/day  hourly cap: $5.00/hr
  expires: 2026-06-22 (30 days)
  actor: jean@jikigai.com

Confirm? [y/N]: _
```

Requires interactive `y` (default N) unless `--yes` flag (for CI / discoverability test). On any non-y → exit 1 with "aborted". Full resolution chain logged to pino at info level for forensics.

**`scripts/byok-revoke.ts`** (NEW) — mirror shape; `--reason` constrained to `admin_revoke` for CLI (matches RPC); `--yes` for CI.

**`package.json`** scripts entries:

```json
"byok-grant": "bun scripts/byok-grant.ts",
"byok-revoke": "bun scripts/byok-revoke.ts"
```

#### Feature flag

`lib/feature-flags/server.ts`: add `"byok-delegations": "FLAG_BYOK_DELEGATIONS"` + `isByokDelegationsEnabled(orgId?)` two-key gate. Doppler dev=1, prd=0 (until PR-B + Side Letter).

#### Tests (3 files + WORM smoke)

**`test/server/byok-delegations.test.ts`** — table-driven; `beforeEach` TRUNCATEs + synthesizes fixtures:
- RLS dual-shape (42501 + 42P17)
- Cross-tenant trigger violation + Sentry `art_33_breach` capture
- WORM Shape 1 / 2 / 3 valid transitions pass; partial Shape 1 (2-of-3 NULL→non-NULL) rejected
- **v3 attribution constraint:** revoke with `revoked_by_user_id` outside `(grantor, grantee, created_by)` is rejected (DIG F1)
- WORM DELETE rejected
- Revoke-grace timing: token at clock_timestamp +30s = grantor attribution; +90s = caller attribution + `attribution_shift_reason='revoked_post_grace'` (uses controlled clock — `pg_sleep` with documented technique)
- Hourly cap (v3): exceeds at $5/hr; daily cap exceeds at $20/day; both raise distinct SQLSTATE
- Member-departure trigger: revoked_by_user_id = OLD.user_id satisfies Shape 1 attribution
- Anonymise: revokes active rows first (Shape 1), then anonymises (Shape 2 with workspace_id NULL)
- pg_default_acl audit assertion using canonical query (DIG F8): `SELECT n.nspname, d.defaclrole::regrole, d.defaclobjtype, d.defaclacl FROM pg_default_acl d JOIN pg_namespace n ON d.defaclnamespace = n.oid WHERE n.nspname = 'public'` AND `pg_proc + aclexplode(proacl)` for new RPCs
- Cap upper-bound enforcement: $1,000,001 cents → P0001 from RPC body guard (SS F2)
- Confirmation prompt: CLI w/o `--yes` requires interactive y

**`test/server/byok-resolver.test.ts`** — resolver semantics:
- Own-key + no delegation → `(callerUserId, NULL)`
- No own-key + active delegation → `(grantorUserId, delegationId)`
- Own-key + active delegation → `(callerUserId, NULL)` [precedence]
- Multi-workspace grantee: resolver with explicit `p_workspace_id = W_A` returns delegations from W_A only; with `p_workspace_id = W_B` returns W_B's delegations only (DIG F3 regression test)
- No own-key + no delegation → no row; lease body raises `MissingByokKeyError`
- Flag OFF: resolver bypasses delegation lookup entirely

**`test/server/byok-delegations-worm-column-enum.test.ts`** (v3 — SS F4) — WORM trigger column-enumeration sentinel:
- Query `SELECT column_name FROM information_schema.columns WHERE table_name='byok_delegations'`
- Query `pg_get_functiondef(oid)` for `byok_delegations_no_mutate` function
- Assert every column from #1 appears in #2's body text
- Fails loudly if a future migration adds a column to `byok_delegations` without updating the WORM trigger

**`test/migration/064_byok_delegations.migration.test.ts`** — apply → down → re-apply cycle.

#### ADR

Run `/soleur:architecture create "BYOK delegations: per-workspace grantor-funded runs"` capturing all v3 decisions.

### Phase 5 — PR Body + Verification

PR body:
- Title: `feat(byok): PR-A — byok_delegations migration + SQL resolver + sentinel sweep + cap enforcement + CLI (Ref #4232)`
- `Ref #4232` (NOT `Closes` — PR-B pending)
- Sentinel sweep enumeration (5 sites + `callerUserId` provenance per site)
- Type widening sweep result
- Migration 064 LAWFUL_BASIS + RETENTION inline
- ADR link
- "v3 deepen-plan refinements" note (merged atomic RPC, clock_timestamp, hourly+daily caps, $10K ceiling, WORM attribution constraint, Shape 3, TS-layer workspace resolution, HMAC pepper, WORM column-enum smoke)

Verification checklist:
- `bun run typecheck` exits 0
- `bun test` exits 0
- `mcp__plugin_supabase_supabase__apply_migration` against dev shows clean apply
- Down.sql reverses cleanly
- CLI E2E with confirmation prompt works
- WORM column-enum smoke passes (current cols match trigger)
- `doppler secrets get FLAG_BYOK_DELEGATIONS -c prd` returns `0`
- `doppler secrets get SENTRY_TAG_PEPPER -c prd` returns a non-empty value

## Files to Create

| Path | Purpose | Phase |
|------|---------|-------|
| `apps/web-platform/supabase/migrations/064_byok_delegations.sql` | Full schema + RPCs (v3 merged) | 1 |
| `apps/web-platform/supabase/migrations/064_byok_delegations.down.sql` | Reverse | 1 |
| `apps/web-platform/server/byok-resolver.ts` | TS wrapper + abstract error hierarchy + provenance invariant | 2 |
| `apps/web-platform/scripts/byok-grant.ts` | CLI grant (consolidated RPC; confirmation prompt) | 4 |
| `apps/web-platform/scripts/byok-revoke.ts` | CLI revoke | 4 |
| `apps/web-platform/test/server/byok-delegations.test.ts` | Table-driven RLS/WORM/revoke/cap/anonymise/pg_default_acl | 4 |
| `apps/web-platform/test/server/byok-resolver.test.ts` | Resolver semantics + multi-workspace regression | 4 |
| `apps/web-platform/test/server/byok-delegations-worm-column-enum.test.ts` | WORM column-enumeration sentinel (v3 — SS F4) | 4 |
| `apps/web-platform/test/migration/064_byok_delegations.migration.test.ts` | Migration smoke | 4 |
| `knowledge-base/project/adrs/<NN>-byok-delegations-resolver-and-grace.md` | ADR | 4 |

## Files to Edit

| Path | Edits | Phase |
|------|-------|-------|
| `apps/web-platform/server/byok-lease.ts` | Widen ByokLeaseArgs + ByokLease with `delegationId?: string`; thread into lease slot | 2 |
| `apps/web-platform/server/observability.ts` | Add `hashUserIdForSentryTag` HMAC helper (SS F6) | 2 |
| `apps/web-platform/server/agent-runner.ts` | 2 sentinel sweep sites + cost-writer call args | 3 |
| `apps/web-platform/server/cc-dispatcher.ts` | 1 sentinel sweep site + cost-writer call args | 3 |
| `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` | 1 sentinel sweep site | 3 |
| `apps/web-platform/server/inngest/functions/github-on-event.ts` | 1 sentinel sweep site | 3 |
| `apps/web-platform/server/cost-writer.ts` | Extend `persistTurnCost`; call `check_and_record_byok_delegation_use` (single RPC); throw sibling errors | 3 |
| `apps/web-platform/server/account-delete.ts` | Add phase 5.9 anonymise-byok-delegations call | 3 |
| `apps/web-platform/package.json` | Add `byok-grant`, `byok-revoke` scripts | 4 |
| `apps/web-platform/lib/feature-flags/server.ts` | Add FLAG_BYOK_DELEGATIONS + isByokDelegationsEnabled | 4 |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Migration 064 applies cleanly to dev-Supabase via `mcp__plugin_supabase_supabase__apply_migration`
- [ ] Down migration reverses cleanly
- [ ] All 5 `runWithByokLease` call sites wrapped; PR body enumerates each + `callerUserId` provenance
- [ ] Type widening sweep: ByokLeaseArgs.delegationId + ByokLease.delegationId added; consumer grep recorded in PR body
- [ ] `mapByokLeaseCauseToErrorCode` UNCHANGED — sibling error hierarchy adopted
- [ ] CLI E2E (with `--yes` in CI): grant + revoke succeed in dev
- [ ] WORM column-enumeration smoke test passes (current cols match trigger)
- [ ] WORM Shape 1 attribution: revoke with `revoked_by_user_id` outside (grantor, grantee, created_by) rejected with P0001
- [ ] WORM Shape 3: cap-update flip with `cap_updated_at` + `cap_updated_by_user_id` passes; without them rejected
- [ ] Cap upper-bound enforcement: $1M cents accepted; $1M+1 rejected
- [ ] Hourly cap test: exceeds at hourly_usd_cap_cents; daily cap test: exceeds at daily_usd_cap_cents; both raise distinct SQLSTATE
- [ ] Revoke-grace timing: clock_timestamp +30s = grantor attribution; +90s = caller attribution + `attribution_shift_reason='revoked_post_grace'`
- [ ] Resolver with explicit `p_workspace_id` returns correct delegation for multi-workspace grantee (DIG F3 regression)
- [ ] Cross-tenant trigger violation test + Sentry event with `art_33_breach: "true"` tag (HMAC-pepper hash)
- [ ] Member-departure auto-revoke + Shape 1 attribution constraint satisfied
- [ ] `pg_default_acl` audit assertion passes (canonical query)
- [ ] Art. 17 cascade: anonymise calls Shape 1 then Shape 2; account-delete.ts phase 5.9 invokes anonymise_byok_delegations before phase 6
- [ ] ADR created and committed
- [ ] `bun run typecheck` exits 0
- [ ] `bun test` exits 0
- [ ] CPO sign-off acknowledged in PR body
- [ ] CLO + CTO sign-offs carry-forward cited
- [ ] `FLAG_BYOK_DELEGATIONS=0` verified in prd Doppler
- [ ] `SENTRY_TAG_PEPPER` verified non-empty in prd Doppler
- [ ] PR body uses `Ref #4232`

### Post-merge (operator + auto)

- [ ] Migration 064 applied to prd via `web-platform-release.yml#migrate` (auto-triggered)
- [ ] PostgREST schema reload (container restart)
- [ ] Sentry alert rule for `art_33_breach=true` with distinct action shape (one-time)
- [ ] Release-time assertion: `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS` parses to UUIDs only, count ≤ N ceiling (SS F8)
- [ ] Issue #4232 stays OPEN until PR-B lands

## Test Strategy

- **Runner**: vitest
- **Real-DB integration** against dev-Supabase only (`hr-dev-prd-distinct-supabase-projects`)
- **Fixture isolation**: every test file `beforeEach` TRUNCATEs + synthesizes (`cq-test-fixtures-synthesized-only`)
- **RLS dual-shape**: 42501 vs 42P17 explicit
- **Time-boundary**: controlled clock via `pg_sleep` + `clock_timestamp()` semantics (NOT `now()`); test header documents technique
- **WORM column-enumeration smoke**: introspects information_schema vs pg_get_functiondef; fails fast on future drift

## Risks

- **R1 (HIGH).** Cross-tenant grant via RLS or trigger gap → Art. 33 72h. **Mitigation:** TRIGGER + Sentry HMAC-pepper hash + integration test.
- **R2 (HIGH).** Revoke-grace timing on `clock_timestamp()` boundary. **Mitigation:** v3 uses `clock_timestamp()` (not `now()`); per-write check inside merged atomic RPC.
- **R3 (HIGH).** Cost-attribution shift is a **ledger fiction**. Anthropic charges grantor's key. **Mitigation:** explicit documentation; `audit_byok_use.attribution_shift_reason` column (v3 — Arch A2) provides data substrate for eventual reconciliation flow.
- **R4 (MEDIUM).** Cap-check + audit-write atomicity. **Mitigation:** v3 single merged RPC `check_and_record_byok_delegation_use` under one FOR UPDATE row lock (DIG F4). `audit_byok_use.invocation_id UNIQUE` for Inngest-retry idempotency.
- **R5 (MEDIUM).** New error class catch-site fan-out. **Mitigation:** abstract `ByokDelegationError` base — one `instanceof` clause per site.
- **R6 (LOW).** `pg_default_acl` audit miss. **Mitigation:** test asserts canonical query.
- **R7 (LOW — dissolved in v3).** Per-founder hourly kill-switch unwired. **v3 mitigation:** per-delegation `hourly_usd_cap_cents` column + check (Arch A1) provides secondary brake without PR-G dependency.
- **R8 (LOW).** CLI admin RPC abuse. **Mitigation:** `p_actor_user_id` required; persists in `created_by_user_id`. Sentry breadcrumb on resolver activation (SS F8 partial).
- **R9 (LOW).** Doppler flag flip needs redeploy.
- **R10 (LOW).** PostgREST schema-cache stale post-apply.
- **R11 (LOW — v3).** WORM trigger fail-OPEN on future column additions. **Mitigation:** column-enumeration smoke test fails loudly when `information_schema.columns` diverges from `pg_get_functiondef` (SS F4).
- **R12 (LOW — v3).** Sentry tag hash reversal for small populations. **Mitigation:** HMAC-SHA256 with server-side `SENTRY_TAG_PEPPER` (SS F6).
- **R13 (LOW — v3).** Resolver callerUserId trust. **Mitigation:** load-bearing invariant comment + PR-body provenance enumeration for every call site (SS F3).

## Observability

```yaml
liveness_signal:
  what: byok-resolver dispatch count + check_and_record_byok_delegation_use invocation rate
  cadence: per-turn (one resolver + zero-or-one cap+audit RPC call per turn)
  alert_target: Sentry transaction telemetry + pino → Better Stack
  configured_in: apps/web-platform/server/byok-resolver.ts (childLogger "byok-resolver") + apps/web-platform/server/cost-writer.ts

error_reporting:
  destination: Sentry via reportSilentFallback wrapper
  fail_loud: yes

failure_modes:
  - mode: cross-tenant insert attempted
    detection: P0001 from byok_delegations_check_same_workspace; TS throws ByokDelegationCrossTenantError
    alert_route: Sentry feature=byok-delegations op=cross-tenant-violation level=error tags={art_33_breach: "true"} (HMAC-pepper hashes) → distinct Slack channel
  - mode: delegation revoked past 60s grace
    detection: P0001 ^byok_delegations:revoked_post_grace; TS throws ByokDelegationRevokedError
    alert_route: Sentry feature=byok-delegations op=revoke-past-grace level=warning
  - mode: delegation expired during turn
    detection: P0001 ^byok_delegations:expired
    alert_route: Sentry feature=byok-delegations op=expired level=warning
  - mode: hourly cap exceeded
    detection: P0001 ^byok_delegations:hourly_cap_exceeded
    alert_route: Sentry feature=byok-delegations op=hourly-cap-exceeded level=info
  - mode: daily cap exceeded
    detection: P0001 ^byok_delegations:daily_cap_exceeded
    alert_route: Sentry feature=byok-delegations op=daily-cap-exceeded level=info
  - mode: member-departure auto-revoke fired
    detection: byok_delegations.revocation_reason='member_departed'
    alert_route: pino breadcrumb (info)
  - mode: resolver SQL failure
    detection: byok-resolver.ts catches non-PGRST errors; falls back to direct lease
    alert_route: reportSilentFallback feature=byok-resolver op=sql-failure level=warning

logs:
  where: pino childLogger "byok-resolver" + "cost-writer" + "byok-lease"
  retention: 30d (existing Better Stack ingestion)

discoverability_test:
  command: |
    doppler run -p soleur -c dev -- bash -c '
      set -euo pipefail
      grant=$(bun run byok-grant -- --yes --actor jean@jikigai.com --grantor jean@jikigai.com --to harry@jikigai.com --workspace auto --cap-cents 100 --hourly-cap-cents 25 2>&1)
      id=$(echo "$grant" | jq -r .delegation_id)
      [[ -n "$id" && "$id" != "null" ]] && echo "grant_success: $id"
      bun run byok-revoke -- --yes --id "$id" --actor jean@jikigai.com --reason admin_revoke 2>&1 | grep -q revoke_success && echo "revoke_success: $id"
    '
  expected_output: |
    grant_success: <uuid>
    revoke_success: <uuid>
```

No `ssh ` in `discoverability_test.command`.

## Open Code-Review Overlap

- **#3243** — Acknowledge. Decomp is separate cycle.
- **#3242** — Acknowledge. PR-A doesn't touch WS events.

## Infrastructure (IaC)

- `FLAG_BYOK_DELEGATIONS=0` in prd, `=1` in dev (Doppler)
- `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS=<jikigai-org-uuid>` in both
- **v3:** `SENTRY_TAG_PEPPER=<32-byte hex>` in both (SS F6) — operator-set one-time
- Release-time assertion: `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS` parses to valid UUIDs, count ≤ N (SS F8)

## Sharp Edges

- **WORM trigger structural-diff is load-bearing.** v3 has 3 shapes (revoke flip + Art. 17 anonymise + cap-update flip). Every legitimate field-change combo must be enumerated. WORM column-enumeration smoke test fails fast on future drift.
- **`byok-resolver.ts` must complete SQL call BEFORE opening the ALS scope.** Do NOT `await` inside `runWithByokLease` body.
- **`callerUserId` provenance is load-bearing.** Per the invariant comment in `byok-resolver.ts`: callerUserId MUST be server-derived (session/JWT), NEVER from request body/params. Every new `resolveKeyOwnerThenLease` call site MUST be enumerated in PR body with provenance.
- **`clock_timestamp()` not `now()` for absolute-time comparisons.** Inside the merged RPC, `clock_timestamp()` is the real-time signal; `now()` would be transaction-start and admit long-txn attacks (SS F1). The grace window, expires comparison, and time-windowed SUM all use `clock_timestamp()`.
- **`check_and_record_byok_delegation_use` atomicity is load-bearing.** SELECT FOR UPDATE row lock + cap-check + INSERT all in one transaction. Splitting this back into two RPCs reintroduces the cap-race hole (DIG F4).
- **Cap-exceeded path does NOT insert an audit row.** Audit row insert happens in the success branch + the post-grace/expired branches (with `attribution_shift_reason` set). Cap-exceeded blocks before any Anthropic call → no charge → no ledger entry.
- **WORM Shape 1 attribution constraint requires `revoked_by_user_id IN (grantor, grantee, created_by)`.** Admin-form RPCs that pass arbitrary `p_actor_user_id` MUST ensure the actor is one of these three. CLI flow does this naturally (the operator IS one of the three by definition). Future RPCs that revoke MUST honor this.
- **Abstract `ByokDelegationError` catch sites:** every `catch (err)` site handling `ByokLeaseError` or `MissingByokKeyError` needs an additional `instanceof ByokDelegationError` clause. The `.reason` discriminator distinguishes 5 cases. PR body enumerates every site.

## Non-Goals

- NG1: Per-action ACLs.
- NG2: Time-window auto-expiry scheduler.
- NG3: Multi-grantor delegations.
- NG4: `prefer_delegation` boolean.
- NG5: Out-of-band reimbursement.
- NG6: Mid-token stream abort.
- NG7: Per-grantee dashboard.
- NG8: Cap aggregation across multiple delegations from same grantor.
- NG9: Materialized view for active delegations.
- NG10: UI grant-from-global-settings.
- NG11 (v2): `_as_self` form RPCs — v3 consolidates with `_as_admin` into single branching RPCs; no separate self-form needed in PR-A or PR-B.
- NG12 (v2): Per-founder hourly kill-switch GLOBAL wiring (deferred to PR-G #3947); the per-delegation hourly cap (v3 — Arch A1) provides PR-A's brake.
- NG13: `byok_admin_audit` caller-IP/host table.
- **NG14 (v3):** Multiple concurrent delegations to same (grantor, grantee, workspace) triple — the partial unique index enforces one-active; raising the cap mid-life uses Shape 3 cap-update flip instead.
- **NG15 (v3):** Replacing existing `byok-lease.ts:140-168` SHA-256 hash with HMAC pepper — v3 introduces the helper for new code; sweep of existing site is separate follow-up.

PR-B Non-Goals additionally apply.

## References

- Spec: `knowledge-base/project/specs/feat-byok-delegations-4232/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md`
- Issue: #4232 · Draft PR: #4290
- Lease cite: `apps/web-platform/server/byok-lease.ts:101-112`
- WORM precedent: `apps/web-platform/supabase/migrations/048_scope_grants.sql`
- RLS helper: `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql:115-140`
- Cap-RPC precedent (NOT extended; v3 adds dedicated `check_and_record_byok_delegation_use`): `apps/web-platform/supabase/migrations/061_byok_audit_workspace_id_rpcs.sql:81-148`
- Anonymise orchestrator: `apps/web-platform/server/account-delete.ts:75-300`
- Feature-flag module: `apps/web-platform/lib/feature-flags/server.ts`
- Workspace resolver: `apps/web-platform/server/workspace-resolver.ts:66`
- CLI precedent: `apps/web-platform/scripts/cla-backfill-evidence.ts`
- Sentry wrapper: `apps/web-platform/server/observability.ts`
- Plan-review findings (v2): DHH + Kieran + Simplicity — all applied
- Deepen-plan findings (v3): data-integrity-guardian + security-sentinel + architecture-strategist — all applied (operator decision "Apply all (P0+P1+P2)" 2026-05-22)
