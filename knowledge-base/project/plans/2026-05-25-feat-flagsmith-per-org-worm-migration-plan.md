---
title: "feat: migrate both flags to Flagsmith + per-org capability + WORM audit"
type: feat
date: 2026-05-25
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_adr: ADR-038
follow_on_adr: ADR-043
umbrella_issue: 4456
umbrella_plan: knowledge-base/project/plans/2026-05-25-feat-audit-env-flags-flagsmith-policy-plan.md
pr_sequence_position: "PR-2 of 3"
blocked_by: "PR-1 (#4455, merged as 67c06373)"
spec: knowledge-base/project/specs/feat-audit-env-flags-flagsmith-policy/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-25-audit-env-flags-flagsmith-policy-brainstorm.md
---

# feat: migrate both flags to Flagsmith + per-org capability + WORM audit

## Enhancement Summary

**Deepened on:** 2026-05-26
**Sections enhanced:** 6 (Capability Layer, WORM Migration, Hot-Path, CI, Precedent-Diff, SDK Verification)
**Research passes:** Precedent-diff gate, verify-the-negative, SDK type verification, learnings cross-reference

### Key Improvements
1. **SDK signature confirmed** — `getIdentityFlags(identifier, traits, transient?: boolean)` at `index.d.ts:89-91`; third-arg `transient: true` opts out entire identity from server-side persistence (strongest data-min form)
2. **Trait format clarified** — traits dict accepts both `{ role: "prd" }` (plain value) and `{ orgId: { value: "org-123", transient: true } }` (per-trait config); plan uses third-arg form for blanket opt-out
3. **resolveKeyOwnerThenLease already async** — confirmed at `byok-resolver.ts:117` (`export async function`); callers already await; change is INSIDE the function only
4. **Retention heartbeat canonical path** — Inngest cron (not GH Actions) per ADR-033; 5+ existing `cron-*.ts` functions confirm pattern; plan Phase 5 retention heartbeat (deferred per umbrella plan scope control) should use Inngest when shipped
5. **WORM trigger pattern divergence documented** — mig 043 uses ONE shared function with two triggers; PR-2 uses TWO separate functions (simpler: no Art. 17 GUC bypass needed since flag_flip_audit has no FK to users)

### New Considerations Discovered
- `envOnly()` at byok-resolver.ts:125 is called BEFORE `isByokDelegationsEnabled()` at line 150 — both checks exist; deletion of `envOnly` must not skip the `isByokDelegationsEnabled` check that follows
- `team-workspace-boot.ts:13` calls `getFlag()` directly (not the composite `isTeamWorkspaceInviteEnabled`) — needs different conversion than other consumer sites
- pg_cron retention heartbeat is explicitly deferred in the umbrella plan ("Defers retention-sweep heartbeat table to a Phase-2 sub-task if scope creeps; otherwise inline") — plan correctly omits it to control scope

---

**PR-2 of umbrella #4456.** This is the load-bearing PR: builds the per-org Flagsmith capability (ADR-043), ships the WORM `flag_flip_audit` ledger (migration 071), and migrates both tenant-boundary flags (`team-workspace-invite`, `byok-delegations`) to `RUNTIME_FLAGS` under dual-control architecture.

## Overview

Move `team-workspace-invite` and `byok-delegations` from `ENV_FLAGS` (sync, deploy-time) to `RUNTIME_FLAGS` (async, identity-aware via Flagsmith). Both retain their env-allowlist gates as defense-in-depth (dual-control: Flagsmith boolean AND allowlist must both hold). The per-org targeting capability ships inline with the first consumers that need it, per DHH + Code Simplicity consensus.

Key deliverables in a single PR:
1. **ADR-043** — documents per-org targeting via identity-trait `orgId` + single `org-targeted` segment
2. **Migration 071** — WORM `flag_flip_audit` table with two triggers, retention bypass, writer RPC
3. **Identity widening** — `Identity` type gains `orgId`; `resolveIdentity()` derives from `workspace_members`
4. **LRU cache** — `_roleCache` widened to bounded LRU keyed on `(role, orgId)` composite (N=1000, 30s TTL)
5. **Flag migration** — both flags move to `RUNTIME_FLAGS`; helpers become async with dual-control
6. **Hot-path care** — `byok-delegations` uses `AsyncLocalStorage` memo for Inngest contexts (precedent: `byok-lease.ts:45`)
7. **CI rewrite** — `scheduled-membership-health.yml` HTTP probe replaces `vars.FLAG_*`
8. **LIA doc** — Art. 6(1)(f) legitimate interest assessment for flag-flip audit processing

## Research Reconciliation — Spec vs. Codebase

| Spec / plan claim | Codebase reality (verified 2026-05-25) | Plan response |
|---|---|---|
| `agent-runner.ts` sites at lines 895, 2461 | `resolveKeyOwnerThenLease` at lines **902**, **2468** | Corrected line refs in plan |
| `cc-dispatcher.ts` site at line 890 | `resolveKeyOwnerThenLease` at line **908** | Corrected |
| AsyncLocalStorage needs ADR decision | Already used in `byok-lease.ts:45` (`import { AsyncLocalStorage } from "node:async_hooks"`) | Inline adoption; no ADR needed |
| Migration slot 071 free | Confirmed: `git ls-tree origin/main -- apps/web-platform/supabase/migrations/ | grep 071` returns empty | 071 confirmed |
| ADR-043 slot free | ADR-042 is latest (`ADR-042-anthropic-sdk-inside-inngest-leader-loop.md`) | 043 confirmed |
| `_roleCache` is `Map<Role, ...>` (max 2) | Confirmed at `server.ts:83` | Widening to LRU(1000) correct |
| `Identity = { userId, role }` | Confirmed at `server.ts:49-52` | Needs `orgId` |
| `isTeamWorkspaceInviteEnabled` is sync | Confirmed at `server.ts:165` — calls `getFlag()` (sync) | Must become async |
| `isByokDelegationsEnabled` is sync | Confirmed at `server.ts:192` — calls `getFlag()` (sync) | Must become async |
| `team-workspace-boot.ts:13` uses `getFlag("team-workspace-invite")` | Confirmed — directly calls sync `getFlag`, not `isTeamWorkspaceInviteEnabled` | Needs async conversion |
| `envOnly()` helper in byok-resolver.ts | At line 202-203, used at line 125 | Delete per plan |
| `FLAGSMITH_MANAGEMENT_API_KEY` in Doppler | Confirmed: used by `flag-create/scripts/create.sh:49`, `flag-set-role/scripts/flip.sh:64`, `user-set-role/scripts/set-role.sh:36` — all pull from `soleur/cli_ops` | Available for segment creation |
| `verify-required-secrets.sh` checks flag vars | **No** references to FLAG_TEAM_WORKSPACE_INVITE or FLAG_BYOK_DELEGATIONS found | Must ADD the env-fallback mirror invariant check |
| PR-3 comment block location | Already partially in place at `server.ts:17-28` (merged via earlier commit) | Plan does NOT re-add; only moves flags from ENV_FLAGS dict |
| `strip_log_injection()` in scheduled-realtime-probe.yml | At line 88 | Reuse confirmed |
| Test runner | vitest (package.json `"test": "vitest"`) | All tests use vitest |
| Skill description budgets | `flag-set-role`: 601w, `flag-create`: 448w, `user-set-role`: 526w (cap: 1800w) | Ample headroom for `--target` extension |
| `FLAGSMITH_CACHE_MAX_ENTRIES` env var | Does not exist yet | Must add to server.ts + .env.example |

## Open Code-Review Overlap

Two open scope-outs touch files PR-2 will edit (carried forward from umbrella plan):

- **#3242** — `review: tool_use WS event lacks raw name field for agent consumers` (touches `agent-runner.ts`, `cc-dispatcher.ts`). **Acknowledge:** distinct concern (WS event schema, not flag-gating). PR-2 adds awaits at separate call sites; no field-shape changes. Scope-out remains open.
- **#3243** — `arch: decompose cc-dispatcher.ts into focused modules` (touches `cc-dispatcher.ts`). **Acknowledge:** PR-2 adds 1 await at line 908; safe in either merge order. Scope-out remains open.

## User-Brand Impact

**If this lands broken, the user experiences:** A non-allowlisted org sees the workspace invite UI/API (cross-tenant exposure on `team-workspace-invite`), OR a paying org's BYOK delegation is silently misrouted mid-billing-cycle (cross-tenant billing breach OR locked-out paying user on `byok-delegations`), OR Flagsmith outage drops dev-cohort preview unexpectedly with no audit trail.

**If this leaks, the user's data/workflow/money is exposed via:** Flagsmith segment misconfiguration (fat-finger that includes wrong orgId in `org-targeted` segment), `orgId` identity-trait egress to a third party not disclosed in our sub-processor list (closed by PR-1), mid-cycle flag flip without WORM audit trail, BYOK key delegation misrouted to wrong grantor.

**Brand-survival threshold:** `single-user incident`. CPO sign-off operator-attested in PR body. `user-impact-reviewer` agent runs at PR review per threshold.

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md` | Per-org targeting decision record |
| `apps/web-platform/supabase/migrations/071_flag_flip_audit.sql` | WORM table + triggers + writer RPC |
| `apps/web-platform/supabase/migrations/071_flag_flip_audit.down.sql` | Rollback migration |
| `apps/web-platform/server/byok-delegations-boot.ts` | Sentry boot breadcrumb (parity with team-workspace-boot.ts) |
| `knowledge-base/legal/legitimate-interest-assessments/2026-05-25-flag-flip-audit-lia.md` | Art. 6(1)(f) LIA for audit processing |
| `apps/web-platform/lib/feature-flags/lru-cache.ts` | Bounded LRU cache (extracted for testability) |
| `apps/web-platform/lib/feature-flags/lru-cache.test.ts` | LRU cache unit tests |

## Files to Edit

### Capability Layer

| Path | Change |
|---|---|
| `apps/web-platform/lib/feature-flags/server.ts` | Move both flags to RUNTIME_FLAGS; extend `getRuntimeFlag` with orgId trait; wire LRU cache; make `isTeamWorkspaceInviteEnabled` + `isByokDelegationsEnabled` async with dual-control; add `FLAGSMITH_CACHE_MAX_ENTRIES` env read |
| `apps/web-platform/lib/feature-flags/identity.ts` | Widen `Identity`: add `orgId: string | null`; extend `resolveIdentity()` with workspace_members SELECT |
| `apps/web-platform/lib/feature-flags/server.test.ts` | New tests: orgId trait forwarding, LRU eviction, dual-control truth table, Flagsmith outage fallback |
| `apps/web-platform/lib/feature-flags/identity.test.ts` | Test: resolveIdentity returns orgId from workspace_members |
| `apps/web-platform/.env.example` | Add `FLAGSMITH_CACHE_MAX_ENTRIES=1000` |

### WORM Audit

| Path | Change |
|---|---|
| `plugins/soleur/skills/flag-create/SKILL.md` | Add audit-row-append step (call `audit_flag_flip` before Flagsmith mutation) |
| `plugins/soleur/skills/flag-create/scripts/create.sh` | Wire `audit_flag_flip` RPC call; exit 4 on failure |
| `plugins/soleur/skills/flag-set-role/SKILL.md` | Add audit-row-append step; add `--target role|org` arg |
| `plugins/soleur/skills/flag-set-role/scripts/flip.sh` | Wire `audit_flag_flip` RPC call; exit 4 on failure; add org-target support |
| `plugins/soleur/skills/user-set-role/SKILL.md` | Add audit-row-append step |
| `plugins/soleur/skills/user-set-role/scripts/set-role.sh` | Wire `audit_flag_flip` RPC call; exit 4 on failure |

### Flagsmith Segment Bootstrap

| Path | Change |
|---|---|
| `plugins/soleur/skills/flag-bootstrap/SETUP.md` | Add `org-targeted` segment creation step + segment IDs |

### team-workspace-invite consumers

| Path | Change |
|---|---|
| `apps/web-platform/server/team-membership-resolver.ts` | Propagate await at gate (line 70) |
| `apps/web-platform/server/team-workspace-boot.ts` | Convert `getFlag("team-workspace-invite")` (line 13) to async `getRuntimeFlag` call |
| `apps/web-platform/app/api/workspace/invite-member/route.ts` | Propagate await (line 40) |
| `apps/web-platform/app/api/workspace/remove-member/route.ts` | Propagate await (line 30) |
| `apps/web-platform/app/(dashboard)/dashboard/settings/layout.tsx` | Propagate await (line 22) |

### byok-delegations consumers

| Path | Change |
|---|---|
| `apps/web-platform/server/byok-resolver.ts` | Delete `envOnly()` helper (lines 202-203); widen `resolveKeyOwnerThenLease()` to async flag check with per-request memo; introduce AsyncLocalStorage for Inngest context |
| `apps/web-platform/server/agent-runner.ts` | Propagate await at lines 902, 2468 |
| `apps/web-platform/server/cc-dispatcher.ts` | Propagate await at line 908 |
| `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` | Propagate await (line 203) |
| `apps/web-platform/server/inngest/functions/github-on-event.ts` | Propagate await (line 214) |

### CI + Invariants

| Path | Change |
|---|---|
| `.github/workflows/scheduled-membership-health.yml` | Replace `vars.FLAG_TEAM_WORKSPACE_INVITE` with HTTP probe to `/api/flags?role=prd`; reuse `strip_log_injection()` from scheduled-realtime-probe.yml; fail-closed-to-OFF on 5xx; `curl --max-time 5` |
| `apps/web-platform/scripts/verify-required-secrets.sh` | Add env-fallback mirror invariant for FLAG_TEAM_WORKSPACE_INVITE + FLAG_BYOK_DELEGATIONS |

### Tests

| Path | Change |
|---|---|
| `apps/web-platform/test/team-membership-resolver.test.ts` | Update for async `isTeamWorkspaceInviteEnabled` |
| `apps/web-platform/test/team-workspace-boot.test.ts` | Update for async boot path |
| `apps/web-platform/e2e/team-membership.e2e.ts` | Dual-control truth table E2E |
| `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts` | Update for async boundary |
| `apps/web-platform/test/server/inngest/cfo-on-payment-failed.test.ts` | Update for async boundary |
| `apps/web-platform/test/server/inngest/github-on-event.test.ts` | Update for async boundary |

## Implementation Phases

### Phase 0 — Pre-conditions + ADR-043

**TDD-exempt** (infrastructure/docs)

1. **Pre-merge tenant-DPA guard:** `awk '/^\| /' knowledge-base/legal/tenant-dpa-register.md | grep -c 'status: dpa-signed'` MUST return 0.
2. **Migration slot re-verify:** `git ls-tree origin/main -- apps/web-platform/supabase/migrations/ | grep 071` MUST return empty.
3. **Draft ADR-043:** `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md`
   - Decision: identity-trait `orgId` + single `org-targeted` segment with rule `orgId IN [...]`
   - Rationale: segment-count explosion avoided; per-org rollout = rule-update via skill
   - Alternatives: N per-org segments (rejected: segment explosion), per-user identity overrides (rejected: out-of-scope)
   - Data minimization: `transient: true` on all `getIdentityFlags` calls (no server-side persistence)
4. **File LIA:** `knowledge-base/legal/legitimate-interest-assessments/2026-05-25-flag-flip-audit-lia.md`
   - Art. 6(1)(f) three-part test
   - Purpose: operational evidence of skill-driven flag-flip operations for Art. 32(1)(d) effectiveness-of-TOMs and SOC2 CC8.1 change management
   - Necessity: conversation-history is volatile (clearable, per-session); structured WORM is the minimum evidence standard
   - Balancing: operator-keyed actor (no user PII); 7-year retention matches SOC2 evidence window

### Phase 1 — LRU Cache (RED/GREEN)

**RED:**
5. Write `apps/web-platform/lib/feature-flags/lru-cache.test.ts`:
   - Test: set/get within TTL returns cached value
   - Test: get after TTL expiry returns undefined (cache miss)
   - Test: eviction when at capacity (N=3 for test); LRU entry evicted
   - Test: access refreshes recency (prevents eviction of recently-used)
   - Test: env-tunable max size via constructor arg

**GREEN:**
6. Write `apps/web-platform/lib/feature-flags/lru-cache.ts`:
   - Generic `LRUCache<K, V>` class with `maxSize` and `ttlMs` constructor params
   - `get(key)` / `set(key, value)` / `clear()`
   - Internal `Map<K, {value: V, at: number}>` with LRU eviction on `set` when at cap
   - Eviction removes the entry with the oldest `at` timestamp (true LRU via access-refresh)

### Phase 2 — Identity Widening (RED/GREEN)

**RED:**
7. Write tests in `identity.test.ts`:
   - Test: authenticated user with workspace_members row returns `{ userId, role, orgId }`
   - Test: authenticated user without workspace_members row returns `orgId: null`
   - Test: anonymous returns `ANON_IDENTITY` (orgId: null)

**GREEN:**
8. Edit `apps/web-platform/lib/feature-flags/identity.ts`:
   - Widen export: `Identity = { userId: string | null, role: Role, orgId: string | null }`
   - Update `ANON_IDENTITY` to include `orgId: null`
   - Extend `resolveIdentity()` to SELECT orgId from `workspace_members` (first org for user, or null)
   - Maintain React `cache()` wrapper for per-request amortization

### Phase 3 — Server.ts Capability (RED/GREEN)

**RED:**
9. Write tests in `server.test.ts`:
   - Test: `getRuntimeFlag` passes orgId trait to `getIdentityFlags(..., { role, orgId }, true)` with `transient: true`
   - Test: LRU cache keyed on `(role, orgId)` — same (role, orgId) pair = cache hit; different orgId = cache miss
   - Test: LRU eviction at N=1000 (mock FLAGSMITH_CACHE_MAX_ENTRIES=3 for test)
   - Test: `isTeamWorkspaceInviteEnabled(orgId, identity)` returns `Promise<boolean>`; dual-control truth table
   - Test: `isByokDelegationsEnabled(orgId, identity)` returns `Promise<boolean>`; dual-control truth table
   - Test: Flagsmith outage → env fallback still satisfies dual-control

**GREEN:**
10. Edit `apps/web-platform/lib/feature-flags/server.ts`:
    - Move `team-workspace-invite` and `byok-delegations` from `ENV_FLAGS` to `RUNTIME_FLAGS`
    - Import `LRUCache` from `./lru-cache`
    - Replace `_roleCache = new Map<Role, ...>()` with `_roleCache = new LRUCache<string, ...>(parseInt(process.env.FLAGSMITH_CACHE_MAX_ENTRIES || '1000'), CACHE_TTL_MS)`
    - Cache key: `${role}:${orgId ?? '__anon__'}`
    - Update `fetchRuntimeFlagsFromFlagsmith(role, orgId)` to call `getIdentityFlags(identifier, { role, ...(orgId ? { orgId } : {}) }, true)` — `transient: true` MANDATORY
    - Identifier strategy: `role:${role}` when orgId is null; `org:${orgId}:${role}` when orgId present
    - Convert `isTeamWorkspaceInviteEnabled(orgId: string)` to `async (orgId: string, identity: Identity): Promise<boolean>` — body: `(await getRuntimeFlag('team-workspace-invite', identity)) && getTeamWorkspaceAllowlist().has(orgId)`
    - Convert `isByokDelegationsEnabled(orgId)` to `async (orgId: string | null | undefined, identity: Identity): Promise<boolean>` — body: `(await getRuntimeFlag('byok-delegations', identity)) && getByokDelegationsAllowlist().has(orgId ?? '')`
    - Update `__resetFeatureFlagsForTests()` to call `_roleCache.clear()`
    - Add `FLAGSMITH_CACHE_MAX_ENTRIES` to `.env.example`

### Phase 4 — WORM Migration 071 (RED/GREEN)

**RED:**
11. Write SQL tests (inline vitest using Supabase test-helpers):
    - Test: INSERT succeeds via `audit_flag_flip()` RPC
    - Test: UPDATE raises exception (WORM no_update trigger)
    - Test: DELETE on unexpired row raises exception (no_delete trigger)
    - Test: DELETE on expired row succeeds (row-state bypass: `retention_until < now()`)
    - Test: `actor` CHECK rejects malformed email (`"NOT-AN-EMAIL"`, `"UPPER@CASE.COM"`)
    - Test: `actor` CHECK accepts valid lowercase email
    - Test: RLS has zero policies (`pg_policies` query)

**GREEN:**
12. Write `apps/web-platform/supabase/migrations/071_flag_flip_audit.sql`:
    ```sql
    -- LAWFUL_BASIS: Art. 6(1)(f) legitimate interest
    -- LIA: knowledge-base/legal/legitimate-interest-assessments/2026-05-25-flag-flip-audit-lia.md

    CREATE TABLE public.flag_flip_audit (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      flag_name text NOT NULL,
      env text NOT NULL CHECK (env IN ('dev','prd')),
      target text NOT NULL,
      action text NOT NULL CHECK (action IN ('on','off','create','archive')),
      before_bool bool,
      after_bool bool,
      actor text NOT NULL CHECK (actor ~ '^[a-z0-9._+-]+@[a-z0-9.-]+\.[a-z]{2,}$'),
      created_at timestamptz NOT NULL DEFAULT now(),
      retention_until timestamptz NOT NULL DEFAULT (now() + interval '7 years')
    );
    ALTER TABLE public.flag_flip_audit ENABLE ROW LEVEL SECURITY;

    -- Two separate trigger FUNCTIONS (per Kieran P0-1/P0-2):
    CREATE FUNCTION public.flag_flip_audit_no_update() RETURNS trigger
      LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
    BEGIN
      RAISE EXCEPTION 'flag_flip_audit is WORM (insert-only); UPDATE forbidden';
    END $$;
    REVOKE ALL ON FUNCTION public.flag_flip_audit_no_update() FROM PUBLIC, anon, authenticated, service_role;

    CREATE FUNCTION public.flag_flip_audit_no_delete() RETURNS trigger
      LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
    BEGIN
      IF TG_OP = 'DELETE' AND OLD.retention_until IS NOT NULL AND OLD.retention_until < now() THEN
        RETURN OLD;
      END IF;
      RAISE EXCEPTION 'flag_flip_audit is WORM; DELETE only permitted for retention sweep on expired rows';
    END $$;
    REVOKE ALL ON FUNCTION public.flag_flip_audit_no_delete() FROM PUBLIC, anon, authenticated, service_role;

    CREATE TRIGGER trg_flag_flip_audit_no_update
      BEFORE UPDATE ON public.flag_flip_audit
      FOR EACH ROW EXECUTE FUNCTION public.flag_flip_audit_no_update();

    CREATE TRIGGER trg_flag_flip_audit_no_delete
      BEFORE DELETE ON public.flag_flip_audit
      FOR EACH ROW EXECUTE FUNCTION public.flag_flip_audit_no_delete();

    -- Writer RPC (SECURITY DEFINER — service_role only):
    CREATE FUNCTION public.audit_flag_flip(
      p_flag_name text, p_env text, p_target text, p_action text,
      p_before_bool bool, p_after_bool bool, p_actor text
    ) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
    DECLARE v_id uuid;
    BEGIN
      INSERT INTO public.flag_flip_audit (flag_name, env, target, action, before_bool, after_bool, actor)
      VALUES (p_flag_name, p_env, p_target, p_action, p_before_bool, p_after_bool, lower(p_actor))
      RETURNING id INTO v_id;
      RETURN v_id;
    END $$;
    REVOKE ALL ON FUNCTION public.audit_flag_flip(text,text,text,text,bool,bool,text) FROM PUBLIC, anon, authenticated;
    GRANT EXECUTE ON FUNCTION public.audit_flag_flip(text,text,text,text,bool,bool,text) TO service_role;
    ```

13. Write `apps/web-platform/supabase/migrations/071_flag_flip_audit.down.sql`:
    - DROP TRIGGER trg_flag_flip_audit_no_update
    - DROP TRIGGER trg_flag_flip_audit_no_delete
    - DROP FUNCTION public.flag_flip_audit_no_update()
    - DROP FUNCTION public.flag_flip_audit_no_delete()
    - DROP FUNCTION public.audit_flag_flip(text,text,text,text,bool,bool,text)
    - DROP TABLE public.flag_flip_audit

### Phase 5 — Skill-Side Audit Append

**TDD-exempt** (skill scripts, tested via integration)

14. Edit `plugins/soleur/skills/flag-create/scripts/create.sh`:
    - Before Flagsmith API call, invoke `audit_flag_flip` via Supabase service-role client
    - On audit failure: `echo "FATAL: audit append failed" >&2; exit 4`
    - Actor: `$(doppler secrets get OPERATOR_EMAIL -p soleur -c cli_ops --plain)` with `tr '[:upper:]' '[:lower:]'`

15. Edit `plugins/soleur/skills/flag-set-role/scripts/flip.sh`:
    - Same audit-append pattern
    - Add `--target role|org` argument parsing
    - When `--target org`, pass `org:<orgId>` as target field to `audit_flag_flip`
    - Exit 4 on audit failure

16. Edit `plugins/soleur/skills/user-set-role/scripts/set-role.sh`:
    - Same audit-append pattern before identity-trait write
    - Exit 4 on audit failure

17. Update corresponding SKILL.md files with audit-row documentation.

### Phase 6 — team-workspace-invite Migration (RED/GREEN)

**RED:**
18. Write/update tests:
    - `test/team-membership-resolver.test.ts`: mock `isTeamWorkspaceInviteEnabled` as async; test gate behavior
    - `test/team-workspace-boot.test.ts`: test async boot path with mocked `getRuntimeFlag`
    - `e2e/team-membership.e2e.ts`: dual-control truth table — (Flagsmith=T, allowlist=T)→T; all other combos→F

**GREEN:**
19. Edit consumer sites (propagate await):
    - `server/team-membership-resolver.ts:70` — `if (!(await isTeamWorkspaceInviteEnabled(orgId, identity)))`
    - `server/team-workspace-boot.ts:13` — convert from sync `getFlag("team-workspace-invite")` to async `getRuntimeFlag('team-workspace-invite', identity)`
    - `app/api/workspace/invite-member/route.ts:40` — propagate await
    - `app/api/workspace/remove-member/route.ts:30` — propagate await
    - `app/(dashboard)/dashboard/settings/layout.tsx:22` — propagate await (RSC so already async-capable)

### Phase 7 — byok-delegations Migration (RED/GREEN)

**RED:**
20. Write/update tests:
    - Hot-path latency regression: 10 BYOK ops in one request → assert Flagsmith mock called ≤1 time
    - Inngest memo test: assert ≤1 Flagsmith call per step execution via AsyncLocalStorage
    - `test/server/byok-audit-writer-sweep.test.ts`: update for async boundary
    - `test/server/inngest/cfo-on-payment-failed.test.ts`: propagated await
    - `test/server/inngest/github-on-event.test.ts`: propagated await

**GREEN:**
21. Edit `apps/web-platform/server/byok-resolver.ts`:
    - Delete `envOnly()` helper (lines 202-203) and its call site (line 125)
    - At `resolveKeyOwnerThenLease()` entry: `if (!(await isByokDelegationsEnabled(orgId, identity))) { /* fast-path to direct lease */ }`
    - Per-request memoization: React `cache()` for RSC paths
    - AsyncLocalStorage memo Map for Inngest contexts (precedent: `byok-lease.ts:45,247`)

22. Edit consumer sites (propagate await):
    - `server/agent-runner.ts:902` — already `await resolveKeyOwnerThenLease(...)` (verify it's already async)
    - `server/agent-runner.ts:2468` — same
    - `server/cc-dispatcher.ts:908` — `return resolveKeyOwnerThenLease(...)` already returns Promise; verify caller awaits
    - `server/inngest/functions/cfo-on-payment-failed.ts:203` — verify await
    - `server/inngest/functions/github-on-event.ts:214` — verify await

23. Create `apps/web-platform/server/byok-delegations-boot.ts`:
    - Sentry boot breadcrumb (parity with `team-workspace-boot.ts`)
    - Async check of `isByokDelegationsEnabled` on first org; breadcrumb message

### Phase 8 — CI + Invariants

**TDD-exempt** (workflow YAML, shell script)

24. Rewrite `.github/workflows/scheduled-membership-health.yml`:
    - Remove `FLAG_ON: ${{ vars.FLAG_TEAM_WORKSPACE_INVITE || '0' }}` env var
    - Add step: `curl --max-time 5 -sf "$FLAGS_URL" | jq -r '.["team-workspace-invite"]'`
    - `FLAGS_URL`: `https://soleur.ai/api/flags?role=prd`
    - Reuse `strip_log_injection()` shell fn (copy from scheduled-realtime-probe.yml:88)
    - On 5xx: fail-closed-to-OFF (skip health probe, no page)
    - On `"team-workspace-invite": false`: skip health probe (dormant)
    - On `"team-workspace-invite": true`: proceed with existing health probe

25. Edit `apps/web-platform/scripts/verify-required-secrets.sh`:
    - Add checks: `FLAG_TEAM_WORKSPACE_INVITE` and `FLAG_BYOK_DELEGATIONS` env vars must be defined (env-fallback mirror invariant)
    - Error message: "env-fallback mirror: FLAG_X must be defined to mirror Flagsmith prd-segment state"

### Phase 9 — Flagsmith Segment Bootstrap

**Operator-mediated** (requires Flagsmith Management API)

26. Via `FLAGSMITH_MANAGEMENT_API_KEY` from Doppler `soleur/cli_ops`:
    - Create `org-targeted` segment in dev env (90722)
    - Create `org-targeted` segment in prd env (90721)
    - Rule: `orgId IN []` (empty — segment exists but matches nobody initially)
    - Create `team-workspace-invite` feature in both envs; attach to `org-targeted` segment
    - Create `byok-delegations` feature in both envs; attach to `org-targeted` segment
    - Each feature-create + segment-attach generates an `audit_flag_flip` row (action: 'create')

27. Update `plugins/soleur/skills/flag-bootstrap/SETUP.md` with segment IDs.

## Acceptance Criteria

### Pre-merge (PR)

**Capability layer:**
- [ ] ADR-043 exists at `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md`
- [ ] `Identity` type includes `orgId: string | null`; `tsc --noEmit` green
- [ ] `resolveIdentity()` returns 3 fields (userId, role, orgId)
- [ ] `getRuntimeFlag` calls `getIdentityFlags(..., { role, orgId }, true)` — verify `transient: true` via test spy
- [ ] LRU cache bounded at `parseInt(process.env.FLAGSMITH_CACHE_MAX_ENTRIES || '1000')`; eviction test passes
- [ ] `org-targeted` segment exists in both Flagsmith envs (verify via Management API GET)

**WORM:**
- [ ] Migration 071 + down apply cleanly: `supabase db reset` green
- [ ] `flag_flip_audit` has RLS enabled with ZERO policies: `SELECT polname FROM pg_policies WHERE tablename='flag_flip_audit'` returns 0 rows
- [ ] Two separate triggers visible: `SELECT tgname FROM pg_trigger WHERE tgrelid='flag_flip_audit'::regclass AND NOT tgisinternal` returns 2
- [ ] UPDATE negative test raises exception
- [ ] DELETE on unexpired row raises exception
- [ ] DELETE on expired row succeeds (row-state bypass)
- [ ] `actor` CHECK rejects `UPPER@CASE.COM` and `not-an-email`
- [ ] Skills exit code 4 on audit-row append failure (tested via intentional bad actor string)
- [ ] LIA doc filed

**Dual-control invariants:**
- [ ] `isTeamWorkspaceInviteEnabled` returns `Promise<boolean>`
- [ ] `isByokDelegationsEnabled` returns `Promise<boolean>`
- [ ] E2E: (Flagsmith=T, allowlist=T) → T; (Flagsmith=T, allowlist=F) → F; (Flagsmith=F, allowlist=T) → F
- [ ] E2E: Flagsmith outage → env-fallback path engages, dual-control still holds
- [ ] E2E: Flagsmith misconfig (segment all orgs) → env-allowlist still gates

**Hot path (byok):**
- [ ] Latency regression: 10 BYOK ops in one request → Flagsmith mock called ≤1 time
- [ ] Inngest memo: ≤1 Flagsmith call per step execution

**CI:**
- [ ] `scheduled-membership-health.yml` probes `/api/flags?role=prd`; no `vars.FLAG_*` reference remains
- [ ] `verify-required-secrets.sh` green; checks both FLAG_ env vars

**Env-var sweep:**
- [ ] `git grep -nE 'process\.env\.FLAG_TEAM_WORKSPACE_INVITE' apps/` shows only fallback site in server.ts + test stubs
- [ ] `git grep -nE 'process\.env\.FLAG_BYOK_DELEGATIONS' apps/` shows only fallback site in server.ts + test stubs

**Pre-merge tenant-DPA guard:**
- [ ] `awk '/^\| /' knowledge-base/legal/tenant-dpa-register.md | grep -c 'status: dpa-signed'` returns 0

**Type safety:**
- [ ] `tsc --noEmit` green (no type errors from async propagation)
- [ ] All vitest suites green: `npx vitest run`

### Post-merge (operator)

- [ ] `/api/flags?role=prd` returns `"team-workspace-invite": false` and `"byok-delegations": false`
- [ ] `SELECT count(*) FROM public.flag_flip_audit WHERE flag_name IN ('team-workspace-invite','byok-delegations')` returns >=2
- [ ] Sentry boot breadcrumb fires for `byok-delegations` on first org check
- [ ] `gh variable delete FLAG_TEAM_WORKSPACE_INVITE` (legacy GH Actions Variable now orphaned)
- [ ] **#4444 remains OPEN** — flip-ON in prd gated separately

## Observability

```yaml
liveness_signal:
  what: "/api/flags?role=prd returns JSON with both flag keys"
  cadence: "hourly (scheduled-membership-health.yml)"
  alert_target: "gh issue create (P0 label)"
  configured_in: ".github/workflows/scheduled-membership-health.yml"

error_reporting:
  destination: "Sentry via reportSilentFallback"
  fail_loud: "env-fallback + Sentry breadcrumb on Flagsmith SDK errors"

failure_modes:
  - mode: "Flagsmith SDK timeout (>200ms)"
    detection: "reportSilentFallback → Sentry"
    alert_route: "Sentry rule (existing feature-flags op)"
  - mode: "LRU cache exhaustion (>1000 entries)"
    detection: "eviction is silent (by design); Sentry breadcrumb if all-eviction scenario detected"
    alert_route: "none (graceful degradation — re-fetch on next request)"
  - mode: "audit_flag_flip RPC failure"
    detection: "skill exit code 4"
    alert_route: "operator terminal (immediate — skill fails loudly)"
  - mode: "WORM trigger bypass attempt"
    detection: "Postgres RAISE EXCEPTION (P0001 ERRCODE)"
    alert_route: "application error propagation to caller"

logs:
  where: "Sentry breadcrumbs (boot + fallback paths)"
  retention: "90 days (Sentry plan)"

discoverability_test:
  command: "curl -sf https://soleur.ai/api/flags?role=prd | jq '.[\"team-workspace-invite\"], .[\"byok-delegations\"]'"
  expected_output: "false\nfalse"
```

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering (CTO)

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** Dual-control architecture + async boundary placement + CI HTTP probe strategy adopted per CTO binding constraints. AsyncLocalStorage adoption is inline (precedent exists at byok-lease.ts:45). LRU-bounded cache addresses unbounded-growth DDoS risk.

### Legal (CLO)

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** PR-1 disclosure precondition met (merged 67c06373). `transient: true` on all identity calls closes server-side persistence concern. LIA doc filed for Art. 6(1)(f) basis. WORM ledger satisfies SOC2 CC8.1 + Art. 32(1)(d).

### Product/UX Gate

**Tier:** NONE
**Decision:** N/A — no user-facing UI changes. Backend capability + flag migration only. Consumer sites already render the feature gates; this PR changes the mechanism, not the UX.

## Test Strategy

- **Unit tests:** vitest (`npx vitest run`)
- **Integration tests:** WORM trigger tests via Supabase test-helpers (real Postgres)
- **E2E:** dual-control truth table in `e2e/team-membership.e2e.ts`
- **Hot-path regression:** mock-based latency assertion (≤1 Flagsmith call per request batch)
- **No bunfig.toml block:** vitest is the configured runner; `bunfig.toml` `pathIgnorePatterns` is `["**"]` but vitest bypasses bun test discovery

## Risks & Mitigations

| Risk | Mitigation | Precedent |
|---|---|---|
| WORM trigger bypass via UPDATE | Separate `_no_update` function — no TG_OP check needed, unconditionally raises | Kieran P0-1; diverges from mig 043 shared-function pattern (simpler for flag_flip_audit which has no Art. 17 bypass) |
| Owner-insert RLS becomes RPC bypass | ZERO RLS policies; service-role-only via SECURITY DEFINER writer | learning `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md` |
| BEFORE-DELETE blocks pg_cron retention | Row-state bypass (`retention_until < now()`) — no GUC required | learning `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` |
| WORM blocks Art. 17 erasure | No FK from flag_flip_audit to users; `actor` is operator email, not user PII | learning `2026-05-25-art17-cascade-deadlock-and-worm-trigger-carveout.md` |
| Async hot-path kills latency | Per-request memo (React `cache()` for RSC; AsyncLocalStorage for Inngest); regression test ≤1 call | learning `2026-04-27-widen-async-contract-instead-of-deferred-construction-proxy.md` |
| `_roleCache` unbounded growth | LRU-bounded N=1000 (env-tunable FLAGSMITH_CACHE_MAX_ENTRIES); eviction re-fetches | Code Simplicity consensus |
| Env-var sweep miss | Pre-merge AC grep gates | learning `2026-03-20-verify-env-var-consumption-at-code-level.md` |
| Doppler env baked at docker run | Flagsmith SDK resolves at request time; E2E verifies | learning `2026-05-19-doppler-env-hot-reload-limitation.md` |
| Customer DPA signing during PR lag | Pre-merge tenant-dpa-register grep guard | GDPR-gate LC-04 |
| Cross-tenant billing breach | Dual-control + E2E truth table | brainstorm User-Brand Impact |

## Precedent-Diff (Phase 4.4)

### SECURITY DEFINER Writer RPC

**Precedent:** migrations 033, 037, 042, 050, 051, 053 all use `SECURITY DEFINER` + `SET search_path = public, pg_temp`.

**Plan alignment:** `audit_flag_flip()` follows this pattern exactly. No divergence.

### WORM Trigger Pattern

**Precedent (mig 043):** Single function `tenant_deploy_audit_no_mutate()` → TWO triggers (BEFORE UPDATE, BEFORE DELETE). Function handles both operations with internal `IF TG_OP =` branching. Includes Art. 17 GUC bypass (`app.tenant_deploy_anonymise_in_progress`).

**Plan divergence (intentional):** PR-2 uses TWO separate functions (`flag_flip_audit_no_update()`, `flag_flip_audit_no_delete()`) → TWO triggers. Rationale: `flag_flip_audit` has NO FK to `users` (actor is operator email, not user UUID), so no Art. 17 anonymisation bypass is needed. Simpler functions = less surface area. The UPDATE function unconditionally raises; the DELETE function has only the row-state bypass.

**Risk acceptance:** Divergence from mig 043's shared-function pattern is explicitly justified by the absence of the Art. 17 use case. If a future requirement adds an FK (unlikely per design), a new migration adds the GUC bypass at that time.

### REVOKE/GRANT Matrix

**Precedent (mig 043:175,227-228,278-279):** `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role` + selective `GRANT EXECUTE ... TO service_role`.

**Plan alignment:** Exact match. Additionally REVOKEs from `service_role` on trigger functions (triggers execute in the caller's context; no role should be able to call them directly).

### Scheduled-Work Pattern

**Precedent:** 5+ Inngest cron functions (`cron-agent-native-audit.ts`, `cron-bug-fixer.ts`, etc.) vs 30 GH Actions scheduled workflows.

**Plan note:** The pg_cron retention heartbeat (umbrella plan task 2.E.5) is explicitly deferred per scope control. When it ships, the ALERT mechanism should be an Inngest cron function (canonical per ADR-033), NOT a GH Actions workflow. The pg_cron sweep itself stays in Postgres (it's a SQL-native DELETE, not application logic).

## SDK Type Verification (deepen-plan Phase 4.45)

### getIdentityFlags Signature

Verified at `node_modules/flagsmith-nodejs/build/cjs/sdk/index.d.ts:89-91`:

```typescript
getIdentityFlags(identifier: string, traits?: {
    [key: string]: FlagsmithTraitValue | TraitConfig;
}, transient?: boolean): Promise<Flags>;
```

**Key findings:**
- Third arg `transient?: boolean` — when `true`, the entire identity evaluation is not persisted server-side (strongest data-minimization form)
- `TraitConfig` (at `types.d.ts:122-125`) allows per-trait transient: `{ value: FlagsmithTraitValue, transient?: boolean }`
- Plan uses third-arg blanket `true` (correct: we never want any trait persisted)

### Trait Format

Current code at `server.ts:99`:
```typescript
const flags = await c.getIdentityFlags(`role:${role}`, { role });
```

Traits dict accepts simple values (`{ role: "prd" }`) — they are auto-wrapped as `FlagsmithTraitValue`. Plan extends to:
```typescript
const flags = await c.getIdentityFlags(
  orgId ? `org:${orgId}:${role}` : `role:${role}`,
  { role, ...(orgId ? { orgId } : {}) },
  true // transient: never persist identity server-side
);
```

### resolveKeyOwnerThenLease Async Status

Verified at `byok-resolver.ts:117`:
```typescript
export async function resolveKeyOwnerThenLease<T>(
```

Function is already async. Callers at `agent-runner.ts:902,2468` and `cc-dispatcher.ts:908` already use `await`/`return` (which propagates the Promise). The change is purely INSIDE the function body: adding the `isByokDelegationsEnabled` flag check at entry.

## Sharp Edges

- `transient: true` MANDATORY on every `getIdentityFlags(...)` call — opts out of Flagsmith server-side identity persistence (data minimization lever).
- Two WORM trigger FUNCTIONS (not one shared), NOT a single combined trigger. Simpler than mig 043 precedent because flag_flip_audit has no Art. 17 anonymisation bypass.
- Row-state bypass on DELETE (NOT `session_replication_role` GUC). pg_cron runs as `postgres` role, not `service_role`.
- Writer RPC + triggers pin `SET search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`.
- `actor` CHECK constraint `'^[a-z0-9._+-]+@[a-z0-9.-]+\.[a-z]{2,}$'` — writer RPC normalizes via `lower(p_actor)`.
- LRU cache bounded N=1000, env-tunable via `FLAGSMITH_CACHE_MAX_ENTRIES`, 30s TTL preserved.
- Skill exit code 4 on audit-row append failure (no silent skip) — per AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`.
- CI workflow: HTTP probe to `/api/flags?role=prd`, NOT `vars.FLAG_*` — single source of truth.
- `verify-required-secrets.sh` must ADD (not just preserve) the env-fallback mirror invariant for both flags.
- `resolveKeyOwnerThenLease()` is ALREADY async (returns Promise) — consumers at agent-runner.ts:902,2468 and cc-dispatcher.ts:908 ALREADY await it. The change is INSIDE the function (adding the flag check), not at the call sites.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above.
- PR body uses `Ref #4456` (NOT `Closes`) — umbrella stays open for PR-3.
- Label: `semver:minor` (new capability: per-org targeting).
