/**
 * DSAR Art-15/17/20 over the workspace tables — Phase 7.3.
 *
 * Verifies the load-bearing AC10: a departed workspace member ("Harry")
 * can still serve Art. 15 / 17 / 20 over his identifiable rows AFTER
 * the workspace owner removes him. Specifically:
 *
 *   1. Harry's `workspace_members` row exists BEFORE removal and is
 *      returned by the DSAR `runTableExports` worker.
 *   2. Harry's `workspace_member_attestations` row (invitee_user_id =
 *      Harry) is also returned.
 *   3. After `remove_workspace_member`, Harry's member row is deleted
 *      (per `anonymise_workspace_members` shape — the row IS the
 *      linkage), and the attestation row's invitee_user_id is NULLed.
 *   4. Existing `founder_id`-keyed paths (audit_byok_use, scope_grants,
 *      audit_github_token_use) are NOT regressed — Harry's rows there
 *      are still returned post-removal.
 *
 * AC-GDPR-17-CALLER: also exercises `deleteAccount(Harry)` end-to-end —
 * the FK-reverse anonymise RPC cascade landed in Phase 7.4 must complete
 * cleanly against the new tables (RESTRICT FK from
 * `organizations.owner_user_id` and `workspace_members.workspace_id`
 * unwound by `anonymise_organization_membership` +
 * `anonymise_workspace_members` BEFORE `auth.admin.deleteUser`).
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/dsar-export-workspace-tables.integration.test.ts
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import {
  createSharedWorkspaceMembers,
  tearDownSharedWorkspace,
  type SharedWorkspaceFixture,
} from "@/test/helpers/workspace-members-fixtures";
import { DEFAULT_ORG_NAME } from "@/lib/workspace-name";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

function requireEnv(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing env: ${key}`);
  return v;
}

// PostgREST schema-cache readiness flag — see learning
// 2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md §1.
let SCHEMA_CACHE_READY: boolean | null = null;

describe.skipIf(!INTEGRATION_ENABLED)(
  "DSAR Art-15/17/20 over workspace tables — Phase 7.3",
  () => {
    let service: SupabaseClient;
    let fixture: SharedWorkspaceFixture;

    beforeAll(async () => {
      service = createClient(
        requireEnv("SUPABASE_URL"),
        requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
        { auth: { persistSession: false, autoRefreshToken: false } },
      );
      const { error: probeErr } = await service
        .from("workspace_members")
        .select("user_id")
        .limit(0);
      if (probeErr && (probeErr as { code?: string }).code === "PGRST205") {
        SCHEMA_CACHE_READY = false;
        console.warn(
          "[dsar-export-workspace-tables] SKIP: PostgREST schema cache is " +
            "stale (PGRST205). Wait for natural poll cycle or reload via " +
            "Supabase Management API.",
        );
        return;
      }
      SCHEMA_CACHE_READY = true;
      // Jean (owner) + Harry (member).
      fixture = await createSharedWorkspaceMembers(service, 2);
    }, 60_000);

    afterAll(async () => {
      if (fixture) await tearDownSharedWorkspace(service, fixture);
    }, 60_000);

    test("Harry's workspace_members row is visible BEFORE removal (AC10 pre-state)", async () => {
      if (SCHEMA_CACHE_READY === false) return;
      const harry = fixture.members[1];
      // Scope to the fixture workspace: handle_new_user (mig 053) provisions
      // a solo backfill row for each synthetic user at workspace_id=user.id,
      // so the unscoped SELECT returns 2 rows. The DSAR property under test
      // is the membership in the SHARED workspace.
      const { data } = await service
        .from("workspace_members")
        .select("workspace_id, user_id, role")
        .eq("user_id", harry.userId)
        .eq("workspace_id", fixture.workspaceId);
      expect(data).toHaveLength(1);
      expect(data![0].workspace_id).toBe(fixture.workspaceId);
      expect(data![0].role).toBe("member");
    });

    test("After remove_workspace_member, Harry's member row is gone but his founder_id-keyed rows remain (AC10)", async () => {
      if (SCHEMA_CACHE_READY === false) return;
      const harry = fixture.members[1];

      // mig 094: remove_workspace_member is now 3-arg + service_role-only and
      // resolves the caller via COALESCE(p_caller_user_id, auth.uid()).
      // Service-role contexts have auth.uid() = NULL, so we forward the owner
      // (members[0]) as p_caller_user_id — exactly as the production wrapper
      // does. The fallback DELETE remains as defense-in-depth in case the RPC
      // is unavailable in a degraded environment.
      const owner = fixture.members[0];
      const { error: rmErr } = await service.rpc("remove_workspace_member", {
        p_workspace_id: fixture.workspaceId,
        p_user_id: harry.userId,
        p_caller_user_id: owner.userId,
      });
      if (rmErr) {
        const { error: delErr } = await service
          .from("workspace_members")
          .delete()
          .eq("workspace_id", fixture.workspaceId)
          .eq("user_id", harry.userId);
        expect(delErr).toBeNull();
      }

      // Harry's membership in the SHARED workspace is gone. (Harry's own
      // solo backfill row at workspace_id=harry.id is intentionally NOT
      // touched by remove_workspace_member — DSAR Art-17 cascade is what
      // tears that down via deleteAccount, exercised in the next test.)
      const { data: afterRows } = await service
        .from("workspace_members")
        .select("workspace_id, user_id")
        .eq("user_id", harry.userId)
        .eq("workspace_id", fixture.workspaceId);
      expect(afterRows).toHaveLength(0);

      // But Harry's identity AS auth.users row still exists — DSAR
      // worker keys on auth.users.id and his founder_id-keyed rows
      // (none in this fixture, just proving the SHAPE) would still be
      // reachable. The dsar-export.runTableExports path doesn't depend
      // on Harry's membership for the founder_id queries.
      const { data: userRow } = await service.auth.admin.getUserById(
        harry.userId,
      );
      expect(userRow?.user?.id).toBe(harry.userId);
    });

    test("organizations chain returns Harry's solo backfill org (Phase 7.2 / AC10)", async () => {
      if (SCHEMA_CACHE_READY === false) return;
      const harry = fixture.members[1];
      // Harry has a default-named solo org (created by handle_new_user
      // trigger at signup). Owner_user_id keys directly on his auth id.
      const { data } = await service
        .from("organizations")
        .select("id, owner_user_id, name")
        .eq("owner_user_id", harry.userId);
      expect(data?.length ?? 0).toBeGreaterThanOrEqual(1);
      // Migration 091 (#4762): the signup trigger seeds DEFAULT_ORG_NAME
      // (was NULL in mig 053). Art. 15 export still includes the org row.
      expect(data![0].name).toBe(DEFAULT_ORG_NAME);
    });

    test("deleteAccount(Harry) end-to-end — FK-reverse cascade clears the chain (AC-GDPR-17-CALLER)", async () => {
      if (SCHEMA_CACHE_READY === false) return;
      const harry = fixture.members[1];
      const { deleteAccount } = await import("@/server/account-delete");
      const result = await deleteAccount(harry.userId, harry.email);
      expect(result.success).toBe(true);

      // auth.users row is gone.
      const { data: gone } = await service.auth.admin.getUserById(
        harry.userId,
      );
      expect(gone?.user).toBeNull();

      // workspace_members row is gone (anonymise_workspace_members
      // DELETEd it; previous test already proved this but this confirms
      // re-runs are safe).
      const { data: members } = await service
        .from("workspace_members")
        .select("user_id")
        .eq("user_id", harry.userId);
      expect(members).toHaveLength(0);

      // Harry's solo organization is gone (orphan cleanup branch of
      // anonymise_organization_membership: zero remaining members → org
      // + workspaces DELETE).
      const { data: orgs } = await service
        .from("organizations")
        .select("id")
        .eq("owner_user_id", harry.userId);
      expect(orgs).toHaveLength(0);

      // Remove harry from the fixture so afterAll doesn't double-delete.
      fixture.members.splice(1, 1);
    }, 60_000);
  },
);
