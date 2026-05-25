---
date: 2026-05-22
feature: workspace-member-session-invalidation
issue: "#4307"
parent_bundle: feat-rls-known-gaps-4233-bundle
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
brainstorm: knowledge-base/project/brainstorms/2026-05-22-rls-known-gaps-4233-bundle-brainstorm.md
spec: knowledge-base/project/specs/feat-rls-known-gaps-4233-bundle/spec.md
draft_pr: "#4345"
branch: feat-rls-known-gaps-4233-bundle
plan_review: 5-agent panel applied (DHH + Kieran + code-simplicity + architecture-strategist + spec-flow-analyzer); 7 cuts + 8 fixes folded into v2
status: planned
---

# feat: workspace-member session invalidation on removal + role-change (#4307)

## Overview

Closes #4307. The only `priority/p2-medium` deferral from #4233's bundle; the load-bearing prerequisite for flipping `team-workspace-invite` ON in the prd Flagsmith segment. Today, removing a workspace member does not invalidate that member's existing JWT; the access_token remains valid until natural ~1h expiry, during which the removed user retains read/write access via `is_workspace_member(...)`-routed RLS. **Latent** today (zero external members), **active** the moment invite UI ships.

PR-1 ships, after 5-agent plan-review consolidation:

1. **Migration 067:** `revoked_after timestamptz` + `revocation_reason text` columns on `workspace_member_removals` (mig 062); `public.check_my_revocation(p_jwt_iat) → (revoked boolean, workspace_id uuid, reason text)` SECURITY DEFINER helper using a **user-global predicate** (any revocation post-iat for the calling user, regardless of `current_organization_id`); `public.update_workspace_member_role(p_workspace_id, p_user_id, p_new_role)` SECURITY DEFINER RPC; existing `public.remove_workspace_member` RPC updated to populate the new columns AND clear `user_session_state.current_organization_id` when it points to the affected workspace. WORM trigger LEFT UNCHANGED (the new columns are protected by the existing PA-19 §(g)(2) "RPC-only writer" invariant).
2. **Middleware revocation lookup:** new server-side check at `apps/web-platform/middleware.ts` immediately after `await supabase.auth.getUser()`. Per-request DB call to `public.check_my_revocation`. No cache. Fail-closed (503) on DB unavailability. iat extraction inlined with explicit try/catch on `decodeJwtPayloadUnsafe`. On revoked: clear Supabase auth cookies (both `Domain`-less AND `Domain=<NEXT_PUBLIC_COOKIE_DOMAIN>` variants) + 302 to `/auth/signin?revoked={reason}` with `Cache-Control: no-store, no-cache`.
3. **Signin page query-param handling:** `/auth/signin` page reads `?revoked=removed|role-changed` and renders a banner. No new standalone `/membership-revoked` route — reuses an existing PUBLIC_PATHS entry.
4. **WS fan-out:** the new `update_workspace_member_role` TS wrapper fan-outs a `MEMBERSHIP_REVOKED` (4012) close to active websockets for the affected user, mirroring the existing `remove_workspace_member` site at `server/workspace-membership.ts:187-192`. WS preamble `reason` field is NOT added in PR-1; existing screen handles both cases identically.
5. **Art. 30 amendments:** PA-19 §(g) gains TOM (10) (revocation lookup) AND §(g)(2) prose is amended to "EXACTLY TWO SECURITY DEFINER bodies INSERT into `workspace_member_removals`" reflecting the new role-change RPC.
6. **Flagsmith default-OFF (replaces the AC10 skill gate):** the `team-workspace-invite` Flagsmith prd-segment default value is hardcoded OFF; flipping is a deliberate post-#4307-close operator action. PR-1 does NOT flip it.
7. **Tenant-isolation tests:** `apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts` covering positive control + service-role re-read poison check + dual-shape RLS deny + multi-workspace user-global predicate + clock-skew tolerance.

## User-Brand Impact

**If this lands broken, the user experiences:** A workspace member they removed (or demoted) screenshots a private thread minutes later, or a removed contractor's stale session writes a message into the workspace after admin action. The founder cannot tell the system to "log them out now"; the system silently leaks ~1 hour of access. Demo-killing.

**If this leaks, the user's workspace data is exposed via:** The removed member's existing JWT continues to pass `is_workspace_member(...)` in RLS predicates covering `conversations`, `messages`, `attachments`, `audit_byok_use`, `runtime_cost_state`, `kb_share_links`, `workspace_member_attestations`, `workspace_member_removals`. Leak surface = the entire team-workspace data plane until natural JWT expiry.

**Brand-survival threshold:** `single-user incident` — carry-forward from feat-rls-known-gaps-4233-bundle brainstorm Phase 0.1.

**CPO sign-off:** required at plan time (brainstorm carry-forward in spec.md frontmatter `domain_review.cpo: signed-off`; plan inherits via `requires_cpo_signoff: true`).

**Review-time:** `user-impact-reviewer` agent invoked at PR review per `plugins/soleur/skills/review/SKILL.md` conditional-agent block. Must enumerate per-failure-mode: stale-JWT post-removal, demotion-treated-as-removal copy, multi-workspace cross-leak (mitigated by user-global predicate F5), clock-skew false-negative, DB-down fail-open regression, WS-fan-out skip, post-refresh-JWT carrying stale `current_organization_id` (mitigated by user_session_state clear F6).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| FR1.5 references `revocation_reason='role-changed'` | No `revocation_reason` column on `workspace_member_removals` (mig 062:89-109). | ADD COLUMN `revocation_reason text NULL` in mig 067. No WORM extension (cut C3); column protected by RPC-only-writer invariant. |
| FR1.5 says role-change path writes a revocation row | No `update_workspace_member_role` RPC exists; no TS site UPDATEs `workspace_members.role`. | ADD `update_workspace_member_role` SECURITY DEFINER RPC in mig 067 (operator chose option B). |
| FR1.4 wires a 5-10s cache | No short-TTL cache primitive exists; Vercel multi-isolate → cache non-coherent. | No cache. Per-request `check_my_revocation` call. p99 budget ≤50ms. Fail-closed (503). |
| FR1.4 redirects to `/membership-revoked` | No middleware redirect exists; existing path is WS-only. | Redirect to `/auth/signin?revoked={reason}` — reuses PUBLIC_PATHS, no new route file, no exempt-list ceremony (cut C4). Existing WS path preserved. |
| FR3.2 / AC10 names "the flag-set skill" gate | Skill is bypass-trivial; `doppler secrets set` directly skips it. | **Cut C5.** Replaced with Flagsmith prd-segment default hardcoded OFF + operator gesture documented in #4307 close ceremony. The skill remains a workflow-nudge only. |
| Middleware predicate uses `current_organization_id` | Multi-workspace user removed-from-one passes when JWT's current_org is non-revoked; UI may flash data (SpecFlow C demo-killer; arch P0-1). | **Switch predicate to user-global** (F5): `EXISTS WHERE removed_user_id = p_user_id AND revoked_after > p_jwt_iat`. RPC returns `(revoked, workspace_id, reason)` so the redirect carries the specific reason. |
| Hook (mig 060) on natural refresh re-evaluates membership | Hook reads `user_session_state.current_organization_id` and injects without re-validating membership; post-refresh JWT can carry stale org claim → half-broken dashboard (arch P0-2). | **Both RPCs UPDATE `user_session_state` SET `current_organization_id = NULL` WHERE `user_id = p_user_id AND current_organization_id = <affected_org_id>` IN THE SAME TRANSACTION** (F6). Best-effort cleanup; the hook-side membership validation is filed as a follow-up. |
| `extractIatFromJwt` helper using `decodeJwtPayloadUnsafe` | The function is private (not exported) AND throws `RuntimeAuthError` on malformed JWT (Kieran P0-1). | **Inline in middleware with explicit try/catch** (cut C2). No helper. Failure mode becomes explicit at the call site. |

## Files to Edit

- `apps/web-platform/middleware.ts` — inject revocation lookup after `getUser()` at line ~123; cookie-clear + redirect helper with `Cache-Control: no-store` + dual-shape cookie clear; inline JWT iat extraction with try/catch.
- `apps/web-platform/lib/supabase/tenant.ts` — **export** `decodeJwtPayloadUnsafe` so middleware can call it (lightest possible change vs. refactor); document the throw contract at the call site. NO new helper.
- `apps/web-platform/lib/routes.ts` — no change (signin already in PUBLIC_PATHS; no REVOCATION_EXEMPT_PATHS list needed).
- `apps/web-platform/app/auth/signin/page.tsx` — read `?revoked=removed|role-changed` query param; render the revoked banner; sign user out via the existing signout flow.
- `apps/web-platform/server/workspace-membership.ts` — add `updateWorkspaceMemberRole(p_workspace_id, p_user_id, p_new_role)` wrapper; reuse WS close-fan-out pattern from lines 187-192.
- `apps/web-platform/server/team-workspace-boot.ts` — no change in PR-1 (the Flagsmith default-OFF + breadcrumb at line 7-19 is sufficient).
- `apps/web-platform/components/dashboard/membership-revoked-screen.tsx` — no change in PR-1 (component used only by the WS-driven in-flight terminal screen; copy is acceptable for both reasons).
- `knowledge-base/legal/article-30-register.md` — PA-19 §(g)(2) prose amended to "EXACTLY TWO SECURITY DEFINER bodies INSERT" (F1); PA-19 §(g) gains TOM (10) describing the revocation lookup; PA-20 §(b) Purposes amendment for role-change event class.
- `apps/web-platform/test/supabase-migrations/067-workspace-member-revocation-lookup.test.ts` — new migration-shape lint test (file path under "Files to Create").
- **NOT EDITED:** `plugins/soleur/skills/flag-set-role/SKILL.md`, `plugins/soleur/skills/flag-set-role/scripts/flip.sh` (cut C5).
- **NOT EDITED:** `apps/web-platform/lib/types.ts`, `apps/web-platform/lib/ws-client.ts` (cut C6 — WS preamble `reason` field deferred).
- **NOT EDITED:** `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql` (no WORM trigger rewrite).

## Files to Create

- `apps/web-platform/supabase/migrations/067_workspace_member_revocation_lookup.sql` — adds 2 columns + backfill; creates `check_my_revocation` + `update_workspace_member_role` SECURITY DEFINER functions; updates `remove_workspace_member` body to populate new columns AND clear `user_session_state`. NO WORM trigger replacement.
- `apps/web-platform/supabase/migrations/067_workspace_member_revocation_lookup.down.sql` — `DROP FUNCTION check_my_revocation; DROP FUNCTION update_workspace_member_role; ALTER TABLE workspace_member_removals DROP COLUMN revoked_after, DROP COLUMN revocation_reason;`. ~15 lines (slimmed per C7+code-simplicity-7).
- `apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts` — dual-shape RLS deny + positive control + service-role re-read poison + multi-workspace user-global predicate + clock-skew tolerance + middleware redirect smoke.
- `apps/web-platform/test/supabase-migrations/067-workspace-member-revocation-lookup.test.ts` — migration-shape lint asserting column types, function signatures, GRANT/REVOKE pattern, search_path pin, AND "exactly two SECURITY DEFINER bodies INSERT into workspace_member_removals" per F1.

## Implementation Phases (consolidated to 4)

### Phase 1 — Migration 067 + Art. 30 + migration-shape lint

1.1. **Schema drift + parity check** (precondition):
```bash
doppler run -p soleur -c dev -- psql -c "\d public.workspace_member_removals" > /tmp/live-schema.txt
diff /tmp/live-schema.txt <(grep -E "ALTER TABLE|CREATE TABLE.*workspace_member_removals|^\s+\w+\s+(uuid|text|timestamp)" apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql)
gh issue view 4307 --json state | jq -r .state  # expect OPEN today; baseline for downstream tests
```
Per learning `2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md`. Halt if drift.

1.2. **Add columns + backfill.** No WORM trigger replacement (cut C3).
```sql
ALTER TABLE public.workspace_member_removals
  ADD COLUMN IF NOT EXISTS revoked_after     timestamptz NULL,
  ADD COLUMN IF NOT EXISTS revocation_reason text         NULL;

-- Backfill legacy rows so any pre-067 removal also blocks stale JWTs whose
-- iat predates the removal. Set revoked_after = removed_at. UPDATE passes
-- the existing WORM trigger because NEW.id = OLD.id and NEW.removed_at =
-- OLD.removed_at (trigger only checks those + PII NULL-transition).
UPDATE public.workspace_member_removals
   SET revoked_after = removed_at, revocation_reason = 'removed'
 WHERE revoked_after IS NULL;

CREATE INDEX IF NOT EXISTS workspace_member_removals_revocation_lookup_idx
  ON public.workspace_member_removals (removed_user_id, revoked_after);
```

1.3. **Create unified `check_my_revocation`** (cut C1: replaces both `is_member_revoked` + `get_my_revocation_reason`; F5: user-global predicate).
```sql
DROP FUNCTION IF EXISTS public.check_my_revocation(timestamptz);

CREATE FUNCTION public.check_my_revocation(p_jwt_iat timestamptz)
  RETURNS TABLE(revoked boolean, workspace_id uuid, reason text)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- User-global predicate (F5): any revocation for auth.uid() with
  -- revoked_after STRICTLY AFTER the JWT's issued-at. Returns a single
  -- row when revoked, or an empty result-set when not revoked.
  -- Strict > on (revoked_after, p_jwt_iat) to absorb ±2s skew on the safer
  -- (deny) side.
  RETURN QUERY
    SELECT true, wmr.workspace_id, wmr.revocation_reason
      FROM public.workspace_member_removals wmr
     WHERE wmr.removed_user_id = auth.uid()
       AND wmr.revoked_after   > p_jwt_iat
     ORDER BY wmr.revoked_after DESC
     LIMIT 1;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::text;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.check_my_revocation(timestamptz) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_my_revocation(timestamptz) TO authenticated;

COMMENT ON FUNCTION public.check_my_revocation(timestamptz) IS
  'Returns (revoked, workspace_id, reason) for auth.uid(). User-global predicate per #4307 plan-review F5 — any post-iat revocation triggers redirect, regardless of current_organization_id.';
```

1.4. **Update `remove_workspace_member`** to populate new columns AND clear user_session_state (F6).
```sql
CREATE OR REPLACE FUNCTION public.remove_workspace_member(
  p_workspace_id uuid, p_user_id uuid
)
  RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_caller_user_id uuid := auth.uid();
        v_org_id         uuid;
BEGIN
  -- (preserve existing authorization logic from mig 062:272-342)
  SELECT organization_id INTO v_org_id
    FROM public.workspaces WHERE id = p_workspace_id;

  DELETE FROM public.workspace_members
   WHERE workspace_id = p_workspace_id AND user_id = p_user_id;

  INSERT INTO public.workspace_member_removals (
    workspace_id, removed_user_id, removed_by_user_id,
    revoked_after, revocation_reason
  ) VALUES (
    p_workspace_id, p_user_id, v_caller_user_id,
    now(), 'removed'
  );

  -- F6: clear user_session_state.current_organization_id if it points to the
  -- affected organization AND the user has no remaining workspaces in it.
  -- The hook at mig 060 doesn't re-validate membership before injecting
  -- current_organization_id into the next JWT; clearing here ensures the
  -- post-refresh JWT lands the user on signin instead of a half-broken
  -- dashboard. Best-effort — a follow-up will add membership validation
  -- to the hook itself.
  UPDATE public.user_session_state uss
     SET current_organization_id = NULL
   WHERE uss.user_id = p_user_id
     AND uss.current_organization_id = v_org_id
     AND NOT EXISTS (
       SELECT 1 FROM public.workspace_members m
       JOIN public.workspaces w ON w.id = m.workspace_id
       WHERE m.user_id = p_user_id AND w.organization_id = v_org_id
     );
END;
$$;
```

1.5. **Create `update_workspace_member_role`** with `set_config` for actor attribution (F2) and user_session_state clear (F6 — clear when demotion changes effective workspace context; safer: always clear to force refresh).
```sql
CREATE OR REPLACE FUNCTION public.update_workspace_member_role(
  p_workspace_id uuid, p_user_id uuid, p_new_role text
)
  RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_caller_user_id uuid := auth.uid();
BEGIN
  -- F2: actor attribution so PA-20 §(g)(3) audit-trigger writes the actor
  -- instead of NULL (orphan-audit-row → Sentry alert per PA-20 §(g)(5)).
  PERFORM set_config('workspace_audit.actor_user_id', COALESCE(v_caller_user_id::text, ''), true);

  IF p_new_role NOT IN ('owner', 'member') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'invalid role; must be owner or member';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id AND user_id = v_caller_user_id AND role = 'owner'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'caller is not an owner of this workspace';
  END IF;

  UPDATE public.workspace_members SET role = p_new_role
   WHERE workspace_id = p_workspace_id AND user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'no workspace_members row for (workspace_id, user_id)';
  END IF;

  INSERT INTO public.workspace_member_removals (
    workspace_id, removed_user_id, removed_by_user_id,
    revoked_after, revocation_reason
  ) VALUES (
    p_workspace_id, p_user_id, v_caller_user_id,
    now(), 'role-changed'
  );

  -- F6 (role-change variant): force JWT refresh by clearing the current_org
  -- pointer if it matches the affected workspace's org. The next mint will
  -- come from a clean state; the user signs back in and lands with their
  -- new role.
  UPDATE public.user_session_state uss
     SET current_organization_id = NULL
    FROM public.workspaces w
   WHERE uss.user_id = p_user_id
     AND w.id        = p_workspace_id
     AND uss.current_organization_id = w.organization_id;
END;
$$;

REVOKE ALL ON FUNCTION public.update_workspace_member_role(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_workspace_member_role(uuid, uuid, text) TO authenticated;
```

1.6. **Art. 30 amendments** co-edited in this commit set:
- **PA-19 §(g)(2)** prose changes from "All inserts route through `remove_workspace_member` SECURITY DEFINER RPC" to: **"All inserts route through EXACTLY TWO SECURITY DEFINER bodies: `remove_workspace_member` (revocation_reason='removed') AND `update_workspace_member_role` (revocation_reason='role-changed'); verified by `grep "INSERT.*workspace_member_removals" apps/web-platform/server/` AND the migration-shape lint at `test/supabase-migrations/067-workspace-member-revocation-lookup.test.ts` enforcing exactly two CREATE OR REPLACE FUNCTION bodies contain that INSERT."** (F1)
- **PA-19 §(g)** appends TOM (10):
  > (10) **Revocation lookup at middleware.** `revoked_after timestamptz` + `revocation_reason text` columns populated by `remove_workspace_member` and `update_workspace_member_role` RPCs at INSERT-time. Middleware at `apps/web-platform/middleware.ts` calls `public.check_my_revocation(jwt_iat)` on every authenticated request (no cache; per-request lookup; fail-closed 503 on DB unavailability). User-global predicate (no `current_organization_id` dependency) closes the multi-workspace cross-leak vector documented in #4307 plan-review F5. Together with the Custom Access Token Hook's natural-refresh re-evaluation (mig 060) AND the same RPCs' atomic clear of `user_session_state.current_organization_id`, this closes the Art. 6 lawful-basis termination window AND the Art. 32 entitlement-change confidentiality TOM gap noted at #4307.
- **PA-20 §(b)** Purposes: append "Role-change events via `update_workspace_member_role` RPC (#4307 PR-1). The RPC issues `PERFORM set_config('workspace_audit.actor_user_id', auth.uid()::text, true)` at body top so the existing PA-20 §(g)(3) trigger-driven writer captures the actor instead of NULL."

1.7. **Migration-shape lint.** New file `test/supabase-migrations/067-workspace-member-revocation-lookup.test.ts` asserts:
- Column types + NULL semantics.
- `check_my_revocation` + `update_workspace_member_role` function signatures, search_path pin, REVOKE/GRANT pattern.
- **EXACTLY TWO `CREATE OR REPLACE FUNCTION` bodies in `apps/web-platform/supabase/migrations/067_workspace_member_revocation_lookup.sql` contain `INSERT INTO public.workspace_member_removals`** (F1 invariant).
- `update_workspace_member_role` body contains `PERFORM set_config('workspace_audit.actor_user_id'` (F2).
- Both RPCs contain the user_session_state UPDATE clearing `current_organization_id` (F6).

### Phase 2 — Middleware revocation lookup + signin banner

2.1. **Export `decodeJwtPayloadUnsafe`** from `apps/web-platform/lib/supabase/tenant.ts`. Single line: add `export` keyword. Per `hr-type-widening-cross-consumer-grep`: this is a contract-narrowing-to-public (no existing external callers; `git grep` confirmed). No sweep required.

2.2. **Inline iat extraction in middleware** with explicit try/catch (C2 + K-P0-1):
```ts
// After `await supabase.auth.getUser()` at middleware.ts:121-123
if (user && session?.access_token) {
  let iat: Date | null = null;
  try {
    const payload = decodeJwtPayloadUnsafe(session.access_token);
    if (typeof payload.iat === "number") iat = new Date(payload.iat * 1000);
  } catch (err) {
    // decodeJwtPayloadUnsafe throws RuntimeAuthError on malformed JWT —
    // failure-closed: send a 401 and let the client re-auth.
    Sentry.captureMessage("revocation_gate.malformed_jwt", { level: "warning" });
    return new NextResponse("Unauthorized", { status: 401 });
  }
  if (!iat) {
    Sentry.captureMessage("revocation_gate.no_iat", { level: "warning" });
    return new NextResponse("Unauthorized", { status: 401 });
  }

  const { data, error } = await supabase.rpc("check_my_revocation", {
    p_jwt_iat: iat.toISOString(),
  });
  if (error) {
    // Fail-CLOSED — revocation is a security boundary.
    reportSilentFallback(error, { tag: "revocation_gate.db_error", userId: user.id });
    return new NextResponse("Service Unavailable", { status: 503 });
  }
  // data is a single-row table per Phase 1.3
  const row = Array.isArray(data) ? data[0] : data;
  if (row?.revoked) {
    return clearSessionAndRedirect(request, `/auth/signin?revoked=${row.reason ?? "removed"}`);
  }
}
```

2.3. **`clearSessionAndRedirect` helper** with cache-control headers + dual-shape cookie clear (F8):
```ts
const COOKIE_DOMAIN = process.env.NEXT_PUBLIC_COOKIE_DOMAIN; // e.g., ".soleur.ai" in prd

function clearSessionAndRedirect(request: NextRequest, target: string): NextResponse {
  const url = request.nextUrl.clone();
  const [pathOnly, queryOnly] = target.split("?");
  url.pathname = pathOnly!;
  url.search = queryOnly ?? "";
  const response = NextResponse.redirect(url, { status: 302 });
  response.headers.set("Cache-Control", "no-store, no-cache, must-revalidate");
  response.headers.set("Pragma", "no-cache");
  // Clear every sb-* cookie on BOTH Domain shapes (F8). Supabase may set
  // cookies with explicit Domain; a Domain-less clear creates a phantom that
  // wins on subsequent requests.
  for (const cookie of request.cookies.getAll()) {
    if (cookie.name.startsWith("sb-")) {
      response.cookies.set(cookie.name, "", { maxAge: 0, path: "/" });
      if (COOKIE_DOMAIN) {
        response.cookies.set(cookie.name, "", { maxAge: 0, path: "/", domain: COOKIE_DOMAIN });
      }
    }
  }
  return response;
}
```

2.4. **Signin page query-param** (`apps/web-platform/app/auth/signin/page.tsx`): read `searchParams.revoked`. If `"removed"`, render a banner above the existing form: "A workspace owner removed you. Sign in below to continue with your other workspaces." If `"role-changed"`: "Your role was updated. Sign in again to apply the new permissions." Otherwise, render the existing form unchanged. Both branches expose the standard sign-in form; no new component file required.

### Phase 3 — Role-change TS wrapper + WS fan-out + tenant-isolation tests

3.1. In `apps/web-platform/server/workspace-membership.ts` add `updateWorkspaceMemberRole`:
```ts
export async function updateWorkspaceMemberRole(
  p_workspace_id: string, p_user_id: string, p_new_role: "owner" | "member"
): Promise<void> {
  const supabase = await getServerClient();
  const { error } = await supabase.rpc("update_workspace_member_role", {
    p_workspace_id, p_user_id, p_new_role,
  });
  if (error) throw error;
  // Fan-out WS close with MEMBERSHIP_REVOKED (4012) — mirrors
  // remove_workspace_member at workspace-membership.ts:187-192.
  // Preamble shape unchanged (cut C6 — no `reason` field in PR-1).
  for (const session of getActiveSessions({ userId: p_user_id, workspaceId: p_workspace_id })) {
    closeWithPreamble(session.ws, WS_CLOSE_CODES.MEMBERSHIP_REVOKED, {});
  }
}
```

3.2. **Tenant-isolation integration tests** (`apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts`), gated by `TENANT_INTEGRATION_TEST=1`:
- **3.2.1 Positive control + service-role re-read poison.** Owner A removes B. B's old JWT calls `check_my_revocation(b_iat)` → returns `(revoked=true, workspace_id, reason='removed')`. Service-role re-read confirms `workspace_member_removals` has a row with `revoked_after = now() ±slack, revocation_reason='removed'`. Owner A's own query returns `(revoked=false, NULL, NULL)` (positive control). All payloads use `randomUUID()`.
- **3.2.2 User-global predicate (multi-workspace).** B is a member of workspaces X (org-A) AND Y (org-B). A removes B from X only. B's JWT (issued before removal) → `check_my_revocation(iat) = (true, X.id, 'removed')` regardless of `current_organization_id`. Removing B from X also clears `user_session_state.current_organization_id` IFF it pointed to org-A (verified by service-role re-read).
- **3.2.3 Clock-skew tolerance.** Service-role poison-write `revoked_after = jwt_iat - 1 second` → predicate FALSE. Poison-write `+1 second` → TRUE.
- **3.2.4 Role-change.** Owner A demotes B owner→member. Service-role re-read: `workspace_members.role = 'member'` AND `workspace_member_removals` row has `revocation_reason='role-changed'` AND `workspace_member_actions` row has `actor_user_id = A` (F2 verification — NOT NULL). B's old JWT triggers redirect to `/auth/signin?revoked=role-changed`.
- **3.2.5 RLS dual-shape deny.** Direct table read with B's old JWT post-removal → dual-shape accept (`error.code === '42501'` OR `data === []`) per learning `2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape`.

3.3. **Middleware redirect smoke** (`apps/web-platform/test/server/middleware-revocation-redirect.test.ts`): mock supabase-js; request with revoked JWT → 302 to `/auth/signin?revoked=removed`, cookies cleared on both Domain shapes, `Cache-Control: no-store` set. Request to `/auth/signin` directly → 200 (PUBLIC_PATH). DB-error → 503. Malformed JWT → 401.

3.4. **Signin banner snapshot** (`apps/web-platform/test/components/signin-revoked-banner.test.tsx`): `?revoked=removed` renders removed copy; `?revoked=role-changed` renders role-change copy; no `?revoked` renders bare signin form.

### Phase 4 — Ship

4.1. PR body contains `Closes #4307` on its own body line (F3 per `wg-use-closes-n-in-pr-body-not-title-to`). Bundle siblings #4304/#4305/#4306/#4318 receive `Ref #4307` notes only, NOT `Closes`.

4.2. Pre-merge: `tsc --noEmit` passes; `./node_modules/.bin/vitest run` passes for new tests; `bash scripts/test-all.sh` passes; full identity-rbac-reviewer sweep on the diff confirms no R4 finding remains.

4.3. Post-merge: per `hr-menu-option-ack-not-prod-write-auth`, apply mig 067 via `web-platform-release.yml#migrate` (dev → prd ack-gated). `gh issue close 4307 -r completed -c "Closed by PR-N (mig 067 + middleware revocation lookup)."` AFTER prd migration succeeds.

4.4. Document in #4307 close ceremony: "Flagsmith `team-workspace-invite` prd-segment may now be flipped ON (cut C5 — no skill-side gate)."

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** `remove_workspace_member` RPC populates `revoked_after = now()` AND `revocation_reason = 'removed'` AND clears `user_session_state.current_organization_id` when no remaining same-org workspace. Removed user's next request within ≤10s gets 302 to `/auth/signin?revoked=removed` with cleared cookies (both Domain shapes) and `Cache-Control: no-store`. Verified by §3.2.1 + §3.3.
- **AC2.** `update_workspace_member_role` RPC flips role AND writes `workspace_member_removals` row with `revocation_reason='role-changed'` AND writes `workspace_member_actions` audit row with non-NULL `actor_user_id` (F2) AND clears `user_session_state.current_organization_id`. Demoted user's next request within ≤10s gets 302 to `/auth/signin?revoked=role-changed`. Verified by §3.2.4.
- **AC3.** Middleware revocation check is per-request (no cache) and fail-CLOSED. On `check_my_revocation` DB error → 503. p99 latency added ≤50ms. Verified by §3.3 + Observability load probe.
- **AC4.** Service-role writers (`server/cost-writer.ts`, `account-delete.ts`, `dsar-export.ts`) NOT affected. Verified by `grep -rn "createServiceClient\|service-role-client" apps/web-platform/server/ | grep -v "/test/"` returning expected allowlist.
- **AC5 (replaced by user-global predicate).** Multi-workspace user revoked from one workspace is redirected on ANY workspace context (F5). Verified by §3.2.2. (Old AC5 about "workspace B session intact" is superseded — under user-global predicate, the removed user is redirected globally and signs back in to access their other workspaces.)
- **AC6.** Strict `>` clock-skew (no INTERVAL slack). ±2s skew documented; RLS-deny is the safer-side error. Verified by §3.2.3.
- **AC7.** WS fan-out parity: `update_workspace_member_role`'s TS wrapper fan-outs `MEMBERSHIP_REVOKED` (4012) to active websockets. Existing preamble shape unchanged (no `reason` field in PR-1; cut C6). In-flight streams terminated within ≤10s.
- **AC8.** `/auth/signin` reads `?revoked=removed|role-changed` and renders the appropriate banner. No new exempt-list ceremony (cut C4 + code-simplicity-4). Verified by §3.4.
- **AC9.** Art. 30 amendments: PA-19 §(g)(2) prose updated to "EXACTLY TWO SECURITY DEFINER bodies INSERT" (F1); PA-19 §(g) TOM (10) added; PA-20 §(b) Purposes amended; CLO line-edit visible in diff. Grep:
  ```bash
  awk '/^## Processing Activity 19/,/^## Processing Activity 20/' knowledge-base/legal/article-30-register.md | grep -q "check_my_revocation"
  awk '/^## Processing Activity 19/,/^## Processing Activity 20/' knowledge-base/legal/article-30-register.md | grep -q "EXACTLY TWO SECURITY DEFINER"
  ```
- **AC10 (replaced).** Flagsmith `team-workspace-invite` prd-segment default value remains hardcoded OFF; no skill-side gate edit (cut C5). PR body documents the operator-flip ceremony as a post-#4307-close action. Verified by reading Flagsmith state pre-merge:
  ```bash
  curl -s -H "Authorization: Token $FLAGSMITH_API_TOKEN" https://api.flagsmith.com/api/v1/environments/<prd-env-id>/featurestates/?feature_name=team-workspace-invite | jq '.results[0].enabled'  # expect false
  ```
- **AC11.** WORM trigger NOT modified (cut C3). The new `revoked_after`/`revocation_reason` columns are protected by the existing PA-19 §(g)(2) "RPC-only writer" invariant — enforced by AC9's grep + the §1.7 migration-shape lint.
- **AC12.** PR body contains `Closes #4307` **on its own body line** (per `wg-use-closes-n-in-pr-body-not-title-to`), NOT in the title, NOT in a checkbox/code-block. (F3)
- **AC13.** `tsc --noEmit` passes. `./node_modules/.bin/vitest run` passes for new tests.
- **AC14 (new — DB-call-rate ceiling F7).** Observability dashboard tracks `revocation_gate.rpc_calls_per_second`; SLO ≤200/sec sustained for 60s. If exceeded → Sentry alert AND auto-fallback to per-isolate cache (Alternative A2; manual code change required, not automated). Baseline auth-middleware RPS measured pre-merge from Vercel + Sentry and recorded in PR body.
- **AC15 (new — F6).** Post-natural-refresh JWT for a removed user: integration test asserts that after `remove_workspace_member` + supabase-js refresh, the new JWT does NOT carry the affected `current_organization_id`. (Verified by triggering a refresh in §3.2.1 and re-decoding the new JWT.)

### Post-merge (operator)

- **AC16.** Apply mig 067 via `web-platform-release.yml#migrate` job (dev first; prd via `hr-menu-option-ack-not-prod-write-auth` ack-gated `supabase db push`). Verify with `gh workflow run web-platform-release.yml --ref main` + `gh run watch`.
- **AC17.** `gh issue close 4307 -r completed -c "Closed by PR-N (mig 067 + middleware revocation lookup)."` AFTER prd migration succeeds.
- **AC18.** Re-run identity-rbac-reviewer manually against any open identity-touching PR to confirm R4 info-finding (session invalidation) is silenced.
- **AC19.** Verify boot breadcrumb at `team-workspace-boot.ts` continues to fire correctly (no regression on existing Sentry tag).
- **AC20 (new — follow-up filing).** File two follow-up GitHub issues after merge:
  1. **Hook-side membership validation.** Extend mig 060 Custom Access Token Hook to validate workspace membership before injecting `current_organization_id`. Closes the "best-effort cleanup" gap F6.
  2. **WS preamble `reason` field.** Add `reason: "removed" | "role-changed"` to MEMBERSHIP_REVOKED preamble for in-flight-session differentiated copy (cut C6).

## Test Strategy

- **Migration-shape lint:** vitest against SQL file structure. Asserts F1 invariant (exactly 2 INSERT call-sites in CREATE OR REPLACE bodies), F2 invariant (`PERFORM set_config('workspace_audit.actor_user_id'` present in role-change body), F6 invariant (both RPCs UPDATE user_session_state).
- **Tenant-isolation integration:** real Supabase dev project, `TENANT_INTEGRATION_TEST=1`, dual-shape RLS deny accept (`42501` OR `[]`), `randomUUID()` for all uuid payloads, service-role re-read poison check, JWT-refresh re-decode verification (AC15).
- **Middleware smoke:** vitest with mocked supabase-js; assert 302 + cache-control + dual-shape cookie clear, 503, 401 (malformed JWT), 200 (signin path passthrough).
- **Signin banner snapshot:** vitest + testing-library; assert distinct copy per `?revoked` value AND bare signin form when param missing.
- **Test runner:** `vitest` per `apps/web-platform/package.json` `scripts.test` (line 15). NOT `bun test` — `apps/web-platform/bunfig.toml` has `[test] pathIgnorePatterns = ["**"]` per learning `2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md` SE#3.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO).

Carry-forward from `knowledge-base/project/brainstorms/2026-05-22-rls-known-gaps-4233-bundle-brainstorm.md` `## Domain Assessments`.

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward + 5-agent plan-review)
**Assessment:** Mechanism = revocation lookup via `workspace_member_removals` (mig 062) extended with `revoked_after` + `revocation_reason`. Per-request lookup (no cache) is the safer simplification of brainstorm's 5-10s cache given Vercel isolate non-coherence. **Plan-review additions:** user-global predicate (F5) eliminates the multi-workspace cross-leak; user_session_state clear (F6) keeps natural-refresh JWT consistent with revocation; WORM extension cut (C3) keeps the existing trigger and uses the RPC-only-writer invariant as the protection.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward + 5-agent plan-review)
**Assessment:** Cross-tenant stale-JWT = Art. 6 (lawful-basis termination) AND Art. 32 (entitlement-change TOM failure). PR-1 sequencing relative to invite-flag flip is BINDING. PA-19 §(g)(2) prose amended to reflect the two-INSERT-site reality (F1); PA-19 §(g) TOM (10) describes the revocation lookup; PA-20 §(b) Purposes covers role-change events. The cut of the AC10 skill gate (C5) does NOT weaken Art. 32 — the Flagsmith default-OFF is a stronger primitive than a skill that operators can bypass.

### Product (CPO)

**Status:** signed-off (brainstorm carry-forward; required by `brand_survival_threshold: single-user incident`)
**Assessment:** #4307 is the only p2 with active blast radius post-flag-flip. Mechanism per-user revocation, NOT JWKS, NOT TTL. ADR-038's "workspace co-members can read each others' messages + attachments" semantic — disclosure modal at first invite-send deferred to a follow-up. **Plan-review additions:** signin-redirect (cut C4) reuses an existing UX surface; user-global predicate (F5) kills the demo-flash failure mode SpecFlow named as highest-likelihood broken journey.

### Product/UX Gate

**Tier:** none (cut C4 removes the new route; remaining edit is a query-param branch on the existing signin page — no new component, no new design surface).
**Decision:** n/a
**Agents invoked:** spec-flow-analyzer (Phase 1 — surfaced 5 spec-level gaps folded into Research Reconciliation, plus 3 plan-review gaps folded into F5/F6/AC15)
**Skipped specialists:** ux-design-lead (no new design surface), copywriter (signin banner copy is one short sentence; reviewed inline)
**Pencil available:** n/a

### Brainstorm-recommended specialists

None named by name.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200`. Searched issue bodies for planned-edit paths.

- **#2591** "docs(security): document CSP middleware + route intersection for binary types" — references `apps/web-platform/middleware.ts`.
  - **Disposition: Acknowledge.** CSP documentation; orthogonal to revocation-lookup injection. Remains open.

No other matches.

## GDPR Gate Outcome (Phase 2.7)

Pre-emptive declarations folded into FRs/ACs to minimize gate friction:

- **AP-01 (lawful basis):** Art. 6(1)(c) record-keeping + Art. 32(1)(b) TOM. Carry-forward from PA-19.
- **T-01 (Privacy Policy):** No new processing surface. Disclosure modal at first invite-send is the CPO-named follow-up — deferred per spec NG4.
- **DL-04 (DSAR regression):** `revoked_after` + `revocation_reason` are PII-adjacent. DSAR export at `server/dsar-export.ts` already selects `*` from `workspace_member_removals` per existing PA-19 TOM (6) — no select-list edit needed.
- **TS-05 (data-portability):** New columns included in the `SELECT *` row export; satisfies Art. 20.

## Infrastructure (IaC)

**Not applicable.** SQL + TS + one page edit + one column in tenant.ts. No new vendor accounts, no servers, no Doppler secrets, no Terraform.

## Observability

```yaml
liveness_signal:
  what: "revocation_gate.checked counter (Sentry breadcrumb) + per-request DB latency p99 + revocation_gate.rpc_calls_per_second rate gauge (F7)"
  cadence: "per authenticated request"
  alert_target: "Sentry — workspace.session-invalidation; rate gauge tracked via Sentry metric"
  configured_in: "apps/web-platform/middleware.ts (Sentry.addBreadcrumb after check_my_revocation returns; Sentry.metrics.increment(\"revocation_gate.rpc_calls\") gauge)"
error_reporting:
  destination: "Sentry (existing wired)"
  fail_loud: "TRUE — reportSilentFallback called on check_my_revocation DB error per cq-silent-fallback-must-mirror-to-sentry"
failure_modes:
  - mode: "check_my_revocation RPC errors (DB unavailable, schema drift)"
    detection: "Sentry event with tag=revocation_gate.db_error"
    alert_route: "Sentry workspace.session-invalidation"
  - mode: "middleware times out on the DB call (>2s)"
    detection: "Vercel function timeout in Sentry"
    alert_route: "Sentry workspace.session-invalidation"
  - mode: "decodeJwtPayloadUnsafe throws on malformed JWT"
    detection: "Sentry.captureMessage('revocation_gate.malformed_jwt')"
    alert_route: "Sentry workspace.session-invalidation"
  - mode: "JWT lacks iat claim"
    detection: "Sentry.captureMessage('revocation_gate.no_iat')"
    alert_route: "Sentry workspace.session-invalidation"
  - mode: "F7 thundering-herd: revocation_gate.rpc_calls/sec sustained > 200/sec for 60s"
    detection: "Sentry metric rule"
    alert_route: "Sentry workspace.session-invalidation high-severity"
  - mode: "Post-refresh JWT carries stale current_organization_id (F6 best-effort fail)"
    detection: "AC15 integration test in CI"
    alert_route: "vitest failure surfaces in CI"
logs:
  where: "Sentry breadcrumbs + structured logs via pino (existing)"
  retention: "Sentry 90d (existing)"
discoverability_test:
  command: "curl -s -o /dev/null -w '%{http_code}\\n' -H 'Cookie: sb-access-token=<test-revoked-jwt>' https://app.soleur.ai/dashboard"
  expected_output: "302 (redirected to /auth/signin?revoked=removed)"
```

p99 latency budget: 50ms added. p99 RPC concurrency budget: 200/sec sustained (F7). Baseline auth-middleware RPS recorded in PR body pre-merge.

## Risks & Sharp Edges

1. **Fail-closed 503 cascade on Supabase outage.** Adds one DB call to middleware. Today's `getUser()` failure already bails — topology unchanged. Vercel function timeout (default 10s) bounds the wait. Arch-strategist's quantitative concern (50ms × N concurrent) is addressed by AC14 + Observability rate gauge.
2. **PostgREST schema cache reload latency.** Per learning `2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md`: after applying mig 067, `NOTIFY pgrst` does NOT propagate through session-mode pooler. Deploy app code AFTER migration propagates; verify with manual RPC probe before deploy.
3. **WORM trigger CURRENT_USER trap.** Per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`: `current_user='service_role'` bypasses fire FALSE under PostgREST. The new RPCs do NOT add such checks (cut C3 means no new trigger logic). Existing PII NULL-transition rule remains in effect.
4. **pg_cron retention sweep + new columns.** Existing sweep on `removed_at` < now() - 36 months DELETEs rows; new columns are dropped along with the row.
5. **F6 is best-effort.** `user_session_state` clear is in the same SECURITY DEFINER body as the removal/role-change INSERT. If the UPDATE fails for any reason (FK violation, NOT NULL constraint), the whole transaction rolls back — safe. The follow-up (AC20-1) hardens by validating at JWT mint time.
6. **WS fan-out partial-success.** If the TS wrapper crashes after `update_workspace_member_role` succeeds but before `closeWithPreamble`, the WS lingers. Middleware catches the next HTTP request (≤10s). Idle WS without subsequent traffic stays alive until natural disconnect. SpecFlow G accepted this; AC20-2 (preamble `reason` field) is a partial follow-up but does not address the partial-success window. Acceptable at single-user incident threshold.
7. **Demotion ≠ removal copy clarity.** Signin banner copy distinguishes the two reasons. The existing in-flight WS terminal screen does not (cut C6); both reasons render the same generic copy. Acceptable for PR-1.
8. **Synthetic-user pollution in tenant-isolation tests.** Tests create real auth.users on **dev** Supabase per `hr-dev-prd-distinct-supabase-projects`. Synthetic email pattern `tenant-isolation-[a-f0-9]{16}@soleur.test` already in use.

## Alternative Approaches Considered

| # | Approach | Why not |
|---|---|---|
| A1 | `auth.admin.signOut(user.id, 'global')` on removal | No KB failure-mode capture; absence-of-evidence is not evidence-of-safety. Also: revokes refresh_token but existing access_token still valid until expiry — middleware lookup still needed. |
| A2 | Per-isolate 5-10s cache + fail-closed | Operator chose no-cache for clarity. AC14 names this as the auto-fallback if F7 thundering-herd rate ceiling is exceeded. |
| A3 | JWKS rotation on removal | CTO §2: panic-button. Logs out every user globally. |
| A4 | Shorter access_token TTL | CTO §2: narrows window, doesn't close it. Constant-friction across all users. |
| A5 | Bundle PR-1 + PR-2 (storage-bucket) | CPO §2: different review surfaces; different rollback shapes. |
| A6 (plan-review) | Per-workspace predicate keyed on `current_organization_id` | Arch P0-1 + SpecFlow C: multi-workspace cross-leak + demo data-flash. Rejected in favor of user-global predicate (F5). |
| A7 (plan-review) | Standalone `/membership-revoked` route | DHH cut: redirect-loop class, exempt-list ceremony, no UX gain over signin banner. Rejected in favor of `/auth/signin?revoked={reason}` (cut C4). |
| A8 (plan-review) | WORM trigger extension to immutable-after-first-set | DHH + Kieran P0-2 + Arch P1: existing PII rules cover the threat class via RPC-only-writer invariant. Cut (C3). |
| A9 (plan-review) | `flag-set-role` skill issue-state gate (AC10) | Arch P1: bypass-trivial (doppler CLI skips); DHH: ceremony. Replaced with Flagsmith prd-segment default-OFF (cut C5). |

## Sharp Edge: Empty User-Brand Impact Section Will Fail deepen-plan Phase 4.6

Section filled above with carry-forward from brainstorm Phase 0.1. CPO sign-off carry-forward in spec.md frontmatter.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-22-feat-workspace-member-session-invalidation-plan.md. Branch: feat-rls-known-gaps-4233-bundle. Worktree: .worktrees/feat-rls-known-gaps-4233-bundle/. Issue: #4307. PR: #4345. Brand-survival threshold: single-user incident. Plan v2 (5-agent plan-review applied: 7 cuts + 8 fixes). CPO sign-off carry-forward from brainstorm. Implementation next.
```
