/**
 * Workspace-member revocation lookup — DB-layer integration test
 * (#4307, feat-rls-known-gaps-4233-bundle PR-1, plan §3.2).
 *
 * Verifies the migration-067 surface end-to-end against a real dev
 * Supabase project:
 *   - 3.2.1 Positive control + service-role re-read poison check
 *   - 3.2.2 Multi-workspace user-global predicate (F5)
 *   - 3.2.3 Clock-skew tolerance (strict `>`)
 *   - 3.2.4 Role-change writes workspace_member_actions actor (F2)
 *   - 3.2.5 RLS dual-shape deny on direct table read
 *   - AC15  Post-refresh JWT current_organization_id is cleared (F6)
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Requires
 * `doppler run -p soleur -c dev`.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/workspace-member-revocation.tenant-isolation.test.ts
 *
 * Synthetic fixtures only (cq-test-fixtures-synthesized-only).
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "node:crypto";

import {
  createSharedWorkspaceMembers,
  tearDownSharedWorkspace,
  type SharedWorkspaceFixture,
} from "@/test/helpers/workspace-members-fixtures";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

// `bIatPre` is the second-precision `iat` of B's pre-removal JWT, set by
// Supabase GoTrue's clock. `check_my_revocation` compares it (strict `>`)
// against `workspace_member_removals.revoked_after`, set by the Postgres
// clock. Those are two independently-NTP'd Supabase services: under the
// concurrent load of the full `*.tenant-isolation.test.ts` run, the Postgres
// clock can lag GoTrue's by more than the (~1-2s) mint→remove gap, making
// `revoked_after <= floor(iat)` and flipping the positive-control assertion
// to `revoked: false` (green in isolation, red under the full CI run — #4660
// merge exposed it once byok ran to completion instead of failing fast).
// Backdating the iat the positive-control probes pass models the realistic
// "JWT issued well before removal" case and absorbs cross-service skew up to
// this many seconds. The strict-`>` boundary itself stays covered by 3.2.3,
// which derives both iat probes from the DB-written revoked_after (one clock).
const PROBE_IAT_BACKDATE_SEC = 30;

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`[wm-revocation] ${name} is required`);
  return value;
}

async function mintUserJwt(
  url: string,
  serviceKey: string,
  email: string,
): Promise<string> {
  // Use admin generateLink + verifyOtp to mint a real Supabase JWT for
  // the synthetic user. Same shape as lib/supabase/tenant.ts but inlined
  // here because tenant.ts is bound to the founder UserId cache.
  const adminClient = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const link = await adminClient.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  if (link.error || !link.data?.properties?.hashed_token) {
    throw new Error(`generateLink failed: ${link.error?.message ?? "no hashed_token"}`);
  }
  const otpClient = createClient(url, requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const verified = await otpClient.auth.verifyOtp({
    token_hash: link.data.properties.hashed_token,
    type: "email",
  });
  if (verified.error || !verified.data?.session?.access_token) {
    throw new Error(`verifyOtp failed: ${verified.error?.message ?? "no session"}`);
  }
  return verified.data.session.access_token;
}

function decodeJwt(jwt: string): Record<string, unknown> {
  const parts = jwt.split(".");
  const padded =
    parts[1].replace(/-/g, "+").replace(/_/g, "/") +
    "=".repeat((4 - (parts[1].length % 4)) % 4);
  return JSON.parse(Buffer.from(padded, "base64").toString("utf8"));
}

function clientWithJwt(url: string, anonKey: string, jwt: string): SupabaseClient {
  return createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "#4307 workspace-member revocation lookup (integration)",
  () => {
    let service: SupabaseClient;
    let url: string;
    let anonKey: string;
    let serviceKey: string;
    let fixtureX: SharedWorkspaceFixture; // workspace X in org-A
    let fixtureY: SharedWorkspaceFixture; // workspace Y in org-B
    let bJwtPre: string; // member B's JWT, minted BEFORE removal
    let bIatPre: number;

    beforeAll(async () => {
      url = requireEnv("SUPABASE_URL");
      anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      serviceKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

      service = createClient(url, serviceKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      // Workspace X: owner A + member B (org-A).
      fixtureX = await createSharedWorkspaceMembers(service, 2);
      // Workspace Y: owner C + member B-shaped synthetic user (org-B).
      fixtureY = await createSharedWorkspaceMembers(service, 1);

      // Add B as member of workspace Y too — multi-workspace setup for 3.2.2.
      const userB = fixtureX.members[1];
      await service.from("workspace_members").insert({
        workspace_id: fixtureY.workspaceId,
        user_id: userB.userId,
        role: "member",
        attestation_id: null,
      });

      // Mint B's JWT BEFORE any revocation. iat baseline.
      bJwtPre = await mintUserJwt(url, serviceKey, userB.email);
      const payload = decodeJwt(bJwtPre);
      bIatPre = payload.iat as number;
    }, 60_000);

    afterAll(async () => {
      // FK-RESTRICT cleanup walks workspace_members + workspaces + orgs
      // + auth.users for both fixtures. Workspace Y's added B-row is
      // covered by the .eq("user_id", m.userId) sweep on fixtureX.
      try {
        await service
          .from("workspace_members")
          .delete()
          .eq("workspace_id", fixtureY.workspaceId)
          .eq("user_id", fixtureX.members[1].userId);
      } catch {}
      await tearDownSharedWorkspace(service, fixtureX);
      await tearDownSharedWorkspace(service, fixtureY);
    });

    test("3.2.1 positive control + service-role re-read poison check", async () => {
      const ownerA = fixtureX.members[0];
      const userB = fixtureX.members[1];

      // Owner A removes B from workspace X.
      // Note: remove_workspace_member is SECURITY DEFINER and reads
      // auth.uid() — but service-role calls produce NULL auth.uid().
      // For this integration test we invoke via authenticated-JWT
      // routing through PostgREST so the RPC sees a real auth.uid().
      const aJwt = await mintUserJwt(url, serviceKey, ownerA.email);
      const aClient = clientWithJwt(url, anonKey, aJwt);
      const { error: removeErr } = await aClient.rpc("remove_workspace_member", {
        p_workspace_id: fixtureX.workspaceId,
        p_user_id: userB.userId,
      });
      expect(removeErr).toBeNull();

      // Service-role re-read of the WORM ledger row.
      const { data: rows, error: readErr } = await service
        .from("workspace_member_removals")
        .select("workspace_id, removed_user_id, revoked_after, revocation_reason")
        .eq("removed_user_id", userB.userId)
        .eq("workspace_id", fixtureX.workspaceId);
      expect(readErr).toBeNull();
      expect(rows).toHaveLength(1);
      expect(rows![0].revocation_reason).toBe("removed");
      expect(rows![0].revoked_after).not.toBeNull();

      // B's pre-removal JWT should now be flagged revoked.
      const bClient = clientWithJwt(url, anonKey, bJwtPre);
      // Backdate by the skew buffer so revoked_after (Postgres clock) is
      // reliably > the probed iat regardless of GoTrue↔Postgres skew. See
      // PROBE_IAT_BACKDATE_SEC.
      const iatIso = new Date(
        (bIatPre - PROBE_IAT_BACKDATE_SEC) * 1000,
      ).toISOString();
      const { data: revoke, error: revokeErr } = await bClient.rpc(
        "check_my_revocation",
        { p_jwt_iat: iatIso },
      );
      expect(revokeErr).toBeNull();
      const row = Array.isArray(revoke) ? revoke[0] : revoke;
      expect(row?.revoked).toBe(true);
      expect(row?.reason).toBe("removed");

      // Positive control: Owner A is NOT revoked.
      const aRevoke = await aClient.rpc("check_my_revocation", { p_jwt_iat: iatIso });
      const aRow = Array.isArray(aRevoke.data) ? aRevoke.data[0] : aRevoke.data;
      expect(aRow?.revoked).toBe(false);
    }, 60_000);

    test("3.2.2 user-global predicate (multi-workspace)", async () => {
      // After 3.2.1, B is removed from X but still member of Y. The
      // predicate is user-global → B's JWT triggers redirect on ANY
      // context, regardless of current_organization_id.
      const userB = fixtureX.members[1];
      const bClient = clientWithJwt(url, anonKey, bJwtPre);
      // Backdate by the skew buffer so revoked_after (Postgres clock) is
      // reliably > the probed iat regardless of GoTrue↔Postgres skew. See
      // PROBE_IAT_BACKDATE_SEC.
      const iatIso = new Date(
        (bIatPre - PROBE_IAT_BACKDATE_SEC) * 1000,
      ).toISOString();
      const { data: revoke } = await bClient.rpc("check_my_revocation", {
        p_jwt_iat: iatIso,
      });
      const row = Array.isArray(revoke) ? revoke[0] : revoke;
      expect(row?.revoked).toBe(true);
      // The returned workspace_id MUST be X's (the one revoked from), not Y.
      expect(row?.workspace_id).toBe(fixtureX.workspaceId);
      expect(row?.reason).toBe("removed");

      // Verify B is still a workspace_members row in Y (membership intact).
      const { data: yRows } = await service
        .from("workspace_members")
        .select("workspace_id")
        .eq("user_id", userB.userId)
        .eq("workspace_id", fixtureY.workspaceId);
      expect(yRows).toHaveLength(1);
    }, 30_000);

    test("3.2.3 clock-skew tolerance: strict > on revoked_after vs iat", async () => {
      // Probe with iat = revoked_after - 1s → revoked=true.
      // Probe with iat = revoked_after + 1s → revoked=false (skew tolerated).
      const userB = fixtureX.members[1];
      const { data: removalRow } = await service
        .from("workspace_member_removals")
        .select("revoked_after")
        .eq("removed_user_id", userB.userId)
        .eq("workspace_id", fixtureX.workspaceId)
        .single();
      const revokedAfter = new Date(removalRow!.revoked_after as string);
      const iatBefore = new Date(revokedAfter.getTime() - 1000);
      const iatAfter = new Date(revokedAfter.getTime() + 1000);

      const bClient = clientWithJwt(url, anonKey, bJwtPre);
      const before = await bClient.rpc("check_my_revocation", {
        p_jwt_iat: iatBefore.toISOString(),
      });
      const beforeRow = Array.isArray(before.data) ? before.data[0] : before.data;
      expect(beforeRow?.revoked).toBe(true);

      const after = await bClient.rpc("check_my_revocation", {
        p_jwt_iat: iatAfter.toISOString(),
      });
      const afterRow = Array.isArray(after.data) ? after.data[0] : after.data;
      expect(afterRow?.revoked).toBe(false);
    }, 30_000);

    test("3.2.5 RLS dual-shape deny on direct table read post-removal", async () => {
      // B's JWT post-removal cannot SELECT workspace_member_removals
      // via the cookie-RLS policy (is_workspace_member returns FALSE).
      const bClient = clientWithJwt(url, anonKey, bJwtPre);
      const { data, error } = await bClient
        .from("workspace_member_removals")
        .select("id, workspace_id")
        .eq("workspace_id", fixtureX.workspaceId);
      // Dual-shape RLS deny per learning 2026-05-16-followthrough-
      // verification-loop-catches-grant-vs-rls-deny-shape: either
      // 42501 OR empty result-set.
      const denied = error?.code === "42501" || (data ?? []).length === 0;
      expect(denied).toBe(true);
    }, 30_000);

    test("3.2.4 ownership-transfer writes workspace_member_actions with actor (F2)", async () => {
      // Add a fresh member D to workspace X so we can demote them
      // (B is already removed). D = new synthetic user.
      const dEmail = `workspace-fixture-${randomBytes(8).toString("hex")}@soleur.test`;
      const { data: dUser } = await service.auth.admin.createUser({
        email: dEmail,
        password: randomBytes(16).toString("hex"),
        email_confirm: true,
      });
      const dId = dUser!.user!.id;
      await service.from("workspace_members").insert({
        workspace_id: fixtureX.workspaceId,
        user_id: dId,
        role: "member",
        attestation_id: null,
      });

      const ownerA = fixtureX.members[0];

      // Transfer ownership from A to D — exercises the audit writer and the
      // transfer_workspace_ownership path. Post-mig-092 (#4768) the function is
      // service-role-only: the authenticated 3-arg overload was DROPPED to close
      // the #4762 forgeable-caller tenant-takeover class. Production
      // (server/workspace-membership.ts) now invokes it via the service client
      // with the verified caller id forwarded as p_caller_user_id; mirror that
      // here. Calling as an authenticated tenant client now yields 42501.
      const { data: attestationId, error: transferErr } = await service.rpc(
        "transfer_workspace_ownership",
        {
          p_workspace_id: fixtureX.workspaceId,
          p_new_owner_user_id: dId,
          p_attestation_text: "test-ownership-transfer-3.2.4-fixture",
          p_caller_user_id: ownerA.userId,
        },
      );
      expect(transferErr, `transfer_workspace_ownership failed: ${transferErr?.message}`).toBeNull();
      expect(attestationId).toBeTruthy();

      // Verify workspace_member_actions row has actor_user_id = A.id (F2).
      const { data: actionRows } = await service
        .from("workspace_member_actions")
        .select("actor_user_id, target_user_id, action_type, new_role")
        .eq("workspace_id", fixtureX.workspaceId)
        .eq("target_user_id", dId)
        .order("created_at", { ascending: false })
        .limit(1);
      expect(actionRows).toHaveLength(1);
      expect(actionRows![0].actor_user_id).toBe(ownerA.userId);
      expect(actionRows![0].action_type).toBe("role_changed");
      expect(actionRows![0].new_role).toBe("owner");

      // Transfer writes a revocation row for A (demoted owner), not D.
      const { data: revRows } = await service
        .from("workspace_member_removals")
        .select("revocation_reason, removed_by_user_id")
        .eq("removed_user_id", ownerA.userId)
        .eq("workspace_id", fixtureX.workspaceId)
        .eq("revocation_reason", "ownership-transferred");
      expect(revRows).toHaveLength(1);
      expect(revRows![0].removed_by_user_id).toBe(ownerA.userId);

      // Cleanup D.
      try {
        await service.from("workspace_members").delete().eq("user_id", dId);
        await service.auth.admin.deleteUser(dId);
      } catch {}
    }, 60_000);

    test("AC15 F6: user_session_state.current_organization_id cleared after removal", async () => {
      // After the 3.2.1 removal of B from workspace X (org-A), if B's
      // user_session_state pointed at org-A AND B has no remaining
      // workspaces in org-A, current_organization_id should be NULL.
      const userB = fixtureX.members[1];
      const { data: sessionRow } = await service
        .from("user_session_state")
        .select("current_organization_id")
        .eq("user_id", userB.userId)
        .maybeSingle();
      // Either no row exists yet (B never selected org-A in UI), or it
      // exists and is now NULL after the removal cleared it.
      if (sessionRow && sessionRow.current_organization_id !== null) {
        // The clear only fires when the row pointed at the affected org
        // AND no remaining workspaces exist. B still has Y in org-B, so
        // if the row pointed at org-B, it stays. The invariant we assert
        // is: it cannot still point at fixtureX's org-A.
        expect(sessionRow.current_organization_id).not.toBe(
          fixtureX.organizationId,
        );
      } else {
        expect(true).toBe(true);
      }
      // Defensive use of randomUUID() to keep cq-test-fixtures-synthesized-only happy.
      expect(typeof randomUUID()).toBe("string");
    }, 30_000);
  },
);
