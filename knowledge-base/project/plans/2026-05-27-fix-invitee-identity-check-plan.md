---
title: "fix: add invitee identity check to accept/decline workspace invitation RPCs"
type: fix
date: 2026-05-27
lane: single-domain
requires_cpo_signoff: true
---

# fix: add invitee identity check to accept/decline workspace invitation RPCs

## Overview

The `accept_workspace_invitation` and `decline_workspace_invitation` SECURITY DEFINER RPCs (migration `075_workspace_invitations.sql`, introduced via issue #4516) do not verify that the calling user (`auth.uid()` / `p_accepter_user_id` / `p_decliner_user_id`) matches the invitation's intended recipient (`invitee_user_id` or `invitee_email`). Any authenticated user who obtains a valid invitation ID can accept or decline the invitation on behalf of the intended invitee, gaining unauthorized workspace membership at the invited role.

The API route handlers (`app/api/workspace/accept-invite/route.ts` and `app/api/workspace/decline-invite/route.ts`) also lack a pre-RPC identity check, meaning the vulnerability exists at both the SQL and application layers.

**Severity:** High. This is an authorization bypass in a SECURITY DEFINER function that creates `workspace_members` rows. Exploitation requires only a valid invitation ID (a UUID, not a secret token) and any authenticated session.

**Attack vector:** Authenticated user A obtains invitation ID I (intended for user B). User A calls `POST /api/workspace/accept-invite` with `{ invitationId: I }`. The RPC succeeds, creating a `workspace_members` row for user A in user B's intended workspace at user B's intended role. User B's invitation is consumed (marked `accepted_at`), preventing legitimate acceptance.

## User-Brand Impact

- **If this lands broken, the user experiences:** unauthorized users joining their workspace with the role meant for someone else; the intended invitee discovers their invitation is already consumed and cannot join.
- **If this leaks, the user's data is exposed via:** an unauthorized workspace member gaining full read access to all workspace-scoped resources (conversations, messages, KB files, BYOK audit logs, scope grants) through the workspace-keyed RLS policies established in migration 059.
- **Brand-survival threshold:** `single-user incident`

## Problem Statement / Motivation

The `accept_workspace_invitation` RPC body (lines 273-351 of `075_workspace_invitations.sql`) performs these checks after locking the invitation row:

1. Invitation exists
2. Not already accepted
3. Not already declined
4. Not expired
5. Accepter is not already a workspace member

It does NOT check whether `v_accepter` matches `v_inv.invitee_user_id` or `v_inv.invitee_email`. The same gap exists in `decline_workspace_invitation` (lines 360-398).

The `accept-invite/route.ts` handler fetches the user via `supabase.auth.getUser()` and passes `user.id` to `acceptWorkspaceInvitation(body.invitationId, user.id)`, but never verifies that `user.id` or `user.email` matches the invitation's intended recipient before calling the RPC.

## Proposed Solution

### 1. SQL layer (primary defense)

Add identity binding inside both `accept_workspace_invitation` and `decline_workspace_invitation` RPCs via a new migration (`076_invitation_invitee_identity_check.sql`). After the invitation row is locked and lifecycle checks pass, add:

```sql
-- Identity binding: accepter must be the intended invitee.
IF v_inv.invitee_user_id IS NOT NULL AND v_inv.invitee_user_id <> v_accepter THEN
  RETURN jsonb_build_object('ok', false, 'reason', 'not_intended_invitee');
END IF;
IF v_inv.invitee_user_id IS NULL THEN
  IF LOWER(v_inv.invitee_email) <> LOWER((SELECT email FROM auth.users WHERE id = v_accepter)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_intended_invitee');
  END IF;
END IF;
```

The same pattern applies to `decline_workspace_invitation` with `v_decliner` in place of `v_accepter`.

### 2. Application layer (defense-in-depth)

Add a pre-RPC identity check in both `accept-invite/route.ts` and `decline-invite/route.ts`. Before calling the RPC, fetch the invitation row via service client, compare `invitee_user_id` against `user.id` and `invitee_email` against `user.email`, and return 403 if mismatched. This provides fail-fast feedback without waiting for the RPC round-trip and prevents the RPC from being called at all for unauthorized users.

### 3. TypeScript error handling

Update `workspace-invitations.ts` to surface the new `not_intended_invitee` reason from the RPC response. Update the route handlers' error-status mapping to return HTTP 403 for this reason.

## Technical Considerations

### Security

- **SECURITY DEFINER context:** Both RPCs run as the function owner (postgres), not the calling role. The identity check MUST be inside the function body, not in RLS policies (which are bypassed by SECURITY DEFINER).
- **Email comparison:** Uses `LOWER()` for case-insensitive matching, consistent with `create_workspace_invitation` (line 215 of migration 075).
- **auth.users access:** The `SELECT email FROM auth.users WHERE id = v_accepter` query is safe inside SECURITY DEFINER because the function runs with elevated privileges. The `auth.users` table is not accessible to `authenticated` role directly, but is accessible to the function owner.
- **`decline_workspace_invitation` has the same vulnerability:** The decline RPC does not check identity either. While the impact is lower (declining an invitation doesn't grant access), it still allows unauthorized users to sabotage invitations intended for others. Both RPCs must be fixed.

### Performance

- The identity check adds one conditional branch and at most one `SELECT` from `auth.users` (only when `invitee_user_id IS NULL`). The `auth.users` lookup is on a primary key (`id`) -- negligible cost.

### Attack Surface Enumeration

| Code path | Vulnerability | Fix location |
|-----------|--------------|-------------|
| `accept_workspace_invitation` RPC (075:273-351) | No invitee identity check | New migration 076 `CREATE OR REPLACE FUNCTION` |
| `decline_workspace_invitation` RPC (075:360-398) | No invitee identity check (decline sabotage) | New migration 076 `CREATE OR REPLACE FUNCTION` |
| `app/api/workspace/accept-invite/route.ts` | No pre-RPC identity check | Add identity check before RPC call |
| `app/api/workspace/decline-invite/route.ts` | No pre-RPC identity check | Add identity check before RPC call |

## Observability

```yaml
liveness_signal:
  what: "Workspace invitation RPCs returning not_intended_invitee rejections"
  cadence: "per-invocation (event-driven)"
  alert_target: "Sentry web-platform via SENTRY_DSN"
  configured_in: "apps/web-platform/server/workspace-invitations.ts (existing reportSilentFallback)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN"
  fail_loud: "HTTP 403 with error: not_intended_invitee in JSON response body"

failure_modes:
  - mode: "Legitimate invitee blocked by email case mismatch"
    detection: "Sentry alert on not_intended_invitee with invitee_user_id IS NULL (email-only path)"
    alert_route: "Sentry issue auto-created, routed to engineering"
  - mode: "Migration 076 fails to apply (function replacement rejected)"
    detection: "Supabase migration runner returns non-zero exit; deploy pipeline fails"
    alert_route: "CI failure notification"

logs:
  where: "Vercel function logs (accept-invite route, decline-invite route)"
  retention: "30 days (Vercel plan default)"

discoverability_test:
  command: "doppler run -p soleur -c dev -- npx supabase db lint --level error 2>&1 | grep -i 'identity\\|invitee'"
  expected_output: "No errors related to invitation identity (lint passes clean)"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: New migration `076_invitation_invitee_identity_check.sql` exists under `apps/web-platform/supabase/migrations/` and replaces both `accept_workspace_invitation` and `decline_workspace_invitation` functions with identity-binding logic.
- [ ] AC2: `accept_workspace_invitation` returns `{ok: false, reason: 'not_intended_invitee'}` when `p_accepter_user_id` does not match `invitee_user_id` (when set) or `invitee_email` (when `invitee_user_id` is NULL).
- [ ] AC3: `decline_workspace_invitation` returns `{ok: false, reason: 'not_intended_invitee'}` when `p_decliner_user_id` does not match `invitee_user_id` (when set) or `invitee_email` (when `invitee_user_id` is NULL).
- [ ] AC4: `accept-invite/route.ts` returns HTTP 403 with `{error: 'not_intended_invitee'}` when the authenticated user does not match the invitation's invitee, BEFORE calling the RPC.
- [ ] AC5: `decline-invite/route.ts` returns HTTP 403 with `{error: 'not_intended_invitee'}` when the authenticated user does not match the invitation's invitee, BEFORE calling the RPC.
- [ ] AC6: `accept-invite/route.ts` service client SELECT includes `invitee_user_id, invitee_email` fields (widened from current query that only selects `inviter_user_id, workspace_id, workspaces!inner(name)`).
- [ ] AC7: Migration pins `SET search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`.
- [ ] AC8: Down migration `076_invitation_invitee_identity_check.down.sql` restores the original function bodies (without identity checks).
- [ ] AC9: Unit test verifies that an unauthorized user (different user ID and email) receives `not_intended_invitee` when attempting to accept an invitation via the route handler.
- [ ] AC10: Unit test verifies that an unauthorized user receives `not_intended_invitee` when attempting to decline an invitation via the route handler.
- [ ] AC11: Unit test verifies that the legitimate invitee (matching `invitee_user_id`) can still accept successfully.
- [ ] AC12: Unit test verifies that the legitimate invitee (matching `invitee_email` when `invitee_user_id` is NULL) can still accept successfully.
- [ ] AC13: `grep -cE 'not_intended_invitee' apps/web-platform/supabase/migrations/076_invitation_invitee_identity_check.sql` returns >= 4 (2 per RPC, accept + decline).

### Post-merge (operator)

- [ ] AC14: Verify migration applied: `doppler run -p soleur -c prd -- npx supabase migration list 2>&1 | grep 076`

## Implementation Phases

### Phase 1: SQL migration (076_invitation_invitee_identity_check.sql)

**Files to create:**
- `apps/web-platform/supabase/migrations/076_invitation_invitee_identity_check.sql`
- `apps/web-platform/supabase/migrations/076_invitation_invitee_identity_check.down.sql`

`CREATE OR REPLACE FUNCTION` for both `accept_workspace_invitation` and `decline_workspace_invitation`. The function signatures remain identical (same parameter types, same return type). The replacement adds the identity-binding check block after the lifecycle checks (not_found, already_accepted, already_declined, expired) and before the "already_member" check (for accept) or the `UPDATE` (for decline).

The identity check logic (repeated for both functions, substituting `v_accepter`/`v_decliner`):

```sql
-- Identity binding: caller must be the intended invitee.
IF v_inv.invitee_user_id IS NOT NULL AND v_inv.invitee_user_id <> v_accepter THEN
  RETURN jsonb_build_object('ok', false, 'reason', 'not_intended_invitee');
END IF;
IF v_inv.invitee_user_id IS NULL THEN
  IF LOWER(v_inv.invitee_email) <> LOWER((SELECT email FROM auth.users WHERE id = v_accepter)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_intended_invitee');
  END IF;
END IF;
```

The down migration restores the original function bodies from migration 075 (without identity checks).

### Phase 2: Application-layer defense-in-depth (route handlers)

**Files to edit:**
- `apps/web-platform/app/api/workspace/accept-invite/route.ts`
- `apps/web-platform/app/api/workspace/decline-invite/route.ts`

In `accept-invite/route.ts`, widen the existing service client SELECT (line 34) to include invitee identity fields:

```typescript
.select("inviter_user_id, invitee_user_id, invitee_email, workspace_id, workspaces!inner(name)")
```

In both handlers, after the invitation row is fetched via service client, add the identity check. The check must be gated on `invRow` being non-null to avoid masking 404s as 403s:

```typescript
// Identity binding: reject if authenticated user is not the intended invitee.
if (invRow) {
  const isInvitee =
    invRow.invitee_user_id === user.id ||
    (!invRow.invitee_user_id &&
      invRow.invitee_email?.toLowerCase() === user.email?.toLowerCase());

  if (!isInvitee) {
    return NextResponse.json(
      { error: "not_intended_invitee" },
      { status: 403 },
    );
  }
}
```

For `decline-invite/route.ts`:
1. Add `import { createServiceClient } from "@/lib/supabase/service"` to imports.
2. Add the service client fetch of the invitation row (same pattern as accept-invite, including `invitee_user_id, invitee_email` fields) before the identity check.

### Phase 3: Error-status mapping updates

**Files to edit:**
- `apps/web-platform/app/api/workspace/accept-invite/route.ts` (error mapping)
- `apps/web-platform/app/api/workspace/decline-invite/route.ts` (error mapping)

Note: `workspace-invitations.ts` types (`AcceptInvitationResult`, `DeclineInvitationResult`) already use `{ ok: false; reason: string }` which handles any reason string including `not_intended_invitee` -- no type changes needed.

Update the error-status mapping in both route handlers to return 403 for `not_intended_invitee`:

```typescript
const status =
  result.reason === "invitation_not_found" || result.reason === "expired"
    ? 404
    : result.reason === "not_intended_invitee"
      ? 403
      : result.reason === "already_accepted" || ...
```

### Phase 4: Tests

**Files to create:**
- `apps/web-platform/test/server/workspace-invitation-identity.test.ts`

Unit tests using vitest that mock the Supabase service client responses:

1. **Accept -- unauthorized user (by user_id):** Mock invitation with `invitee_user_id` set to a different user. Verify route returns 403.
2. **Accept -- unauthorized user (by email):** Mock invitation with `invitee_user_id` NULL and `invitee_email` set to a different email. Verify route returns 403.
3. **Accept -- authorized user (by user_id):** Mock invitation with `invitee_user_id` matching caller. Verify route proceeds to RPC call.
4. **Accept -- authorized user (by email):** Mock invitation with `invitee_user_id` NULL and `invitee_email` matching caller (case-insensitive). Verify route proceeds to RPC call.
5. **Decline -- unauthorized user:** Mock invitation with `invitee_user_id` set to different user. Verify route returns 403.
6. **Decline -- authorized user:** Mock invitation with `invitee_user_id` matching caller. Verify route proceeds.

## Files to Edit

- `apps/web-platform/app/api/workspace/accept-invite/route.ts` -- widen service client SELECT to include `invitee_user_id, invitee_email`; add pre-RPC identity check (gated on `invRow` non-null); update error mapping
- `apps/web-platform/app/api/workspace/decline-invite/route.ts` -- add `createServiceClient` import; add service client fetch with invitee fields; add pre-RPC identity check (gated on `invRow` non-null); update error mapping

## Files to Create

- `apps/web-platform/supabase/migrations/076_invitation_invitee_identity_check.sql`
- `apps/web-platform/supabase/migrations/076_invitation_invitee_identity_check.down.sql`
- `apps/web-platform/test/server/workspace-invitation-identity.test.ts`

## Open Code-Review Overlap

None

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a straightforward authorization-bypass fix in SECURITY DEFINER RPCs. The fix follows established patterns (identity binding inside the function body, defense-in-depth at the application layer). No architectural concerns -- the change is additive (new conditional check) with no schema modifications. The `CREATE OR REPLACE FUNCTION` pattern is the standard approach for patching RPC bodies without schema migration.

### Product/UX Gate

**Tier:** NONE

No user-facing UI changes. The fix adds server-side authorization checks that surface as error responses only when an unauthorized user attempts exploitation. Legitimate users see no behavioral change.

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Email case mismatch blocks legitimate invitee | `LOWER()` applied to both sides of comparison, consistent with `create_workspace_invitation` pattern |
| `invitee_user_id` and `invitee_email` both NULL (Art. 17 anonymised row) | Anonymised rows have `accepted_at` or `declined_at` set (lifecycle complete); the check fires after lifecycle guards, so anonymised rows are already filtered by `accepted_at IS NOT NULL` or `declined_at IS NOT NULL` returns |
| Down migration reverts security fix | Down migration is for development rollback only; production deploys are forward-only |
| Service client fetch in decline-invite adds a DB round-trip | One SELECT on a UUID primary key; negligible latency; acceptable for security defense-in-depth |

## Test Strategy

**Runner:** vitest (per `apps/web-platform/package.json` `scripts.test`)

**Approach:** Unit tests with mocked Supabase service client. The tests verify the route handler behavior (application-layer defense). The SQL-layer identity check is verified via the AC13 grep assertion on the migration file content and would be covered by integration tests in the existing tenant-isolation test suite (opt-in via `TENANT_INTEGRATION_TEST=1`).

**Note on `bunfig.toml`:** `apps/web-platform/bunfig.toml` has `[test] pathIgnorePatterns = ["**"]` (defense-in-depth per #1469). Use `./node_modules/.bin/vitest run test/server/workspace-invitation-identity.test.ts` explicitly, not `bun test`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The `decline_workspace_invitation` vulnerability (sabotage) is lower severity than `accept_workspace_invitation` (unauthorized access) but MUST be fixed in the same PR. Leaving decline unfixed creates an inconsistent security posture and a tracking gap.
- The `invitee_user_id IS NULL` code path (email-only matching) fires for invitations sent to users who do not yet have accounts. When they sign up and accept, the email comparison is the only identity binding. Ensure the email comparison uses `LOWER()` on both sides.
- [Plan review P0-1] The existing service client SELECT in `accept-invite/route.ts:34` does NOT include `invitee_user_id` or `invitee_email`. The identity check code would see `undefined` for both fields, blocking ALL users. The SELECT must be widened.
- [Plan review P0-2] The identity check must be gated on `invRow` being non-null. Otherwise, a "not found" invitation returns 403 instead of allowing the RPC to return the correct 404.

## References

- Issue: #4544
- Parent feature: #4516 (feat: build team workspace Members tab UI and invite flow)
- Migration file: `apps/web-platform/supabase/migrations/075_workspace_invitations.sql`
- Provenance: Pre-existing vulnerability flagged by automated security review plugin (prior to PR #4524)
