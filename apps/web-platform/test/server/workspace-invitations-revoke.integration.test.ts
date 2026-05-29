/**
 * Owner-side invite revoke — live behavior (feat-cancel-pending-invite, #4634).
 *
 * FR3: a revoked invite drops out of the pending lists.
 * FR4: a revoked invite's token can no longer be accepted.
 * FR5: the same email can be re-invited after a revoke (duplicate-pending
 *      guard ignores revoked rows).
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1 against DEV Supabase only
 * (hr-dev-prd-distinct-supabase-projects). Synthesized fixtures per
 * cq-test-fixtures-synthesized-only.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/workspace-invitations-revoke.integration.test.ts
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { createHash, randomBytes } from "node:crypto";

import {
  createSharedWorkspaceMembers,
  syntheticWorkspaceFixtureEmail,
  tearDownSharedWorkspace,
  type SharedWorkspaceFixture,
} from "@/test/helpers/workspace-members-fixtures";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

function requireEnv(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing env: ${key}`);
  return v;
}

function freshToken(): { token: string; hash: string } {
  const token = randomBytes(32).toString("base64url");
  return { token, hash: createHash("sha256").update(token).digest("hex") };
}

async function createInvite(
  service: SupabaseClient,
  workspaceId: string,
  callerUserId: string,
  email: string,
): Promise<{ invitationId: string; tokenHash: string }> {
  const { hash } = freshToken();
  const { data, error } = await service.rpc("create_workspace_invitation", {
    p_workspace_id: workspaceId,
    p_invitee_email: email,
    p_role: "member",
    p_token_hash: hash,
    p_attestation_text: "integration-test invite",
    p_caller_user_id: callerUserId,
  });
  expect(error).toBeNull();
  expect((data as { ok: boolean }).ok).toBe(true);
  return { invitationId: (data as { invitation_id: string }).invitation_id, tokenHash: hash };
}

describe.skipIf(!INTEGRATION_ENABLED)("revoke_workspace_invitation — live", () => {
  let service: SupabaseClient;
  let fixture: SharedWorkspaceFixture;
  let ready = true;

  beforeAll(async () => {
    service = createClient(
      requireEnv("SUPABASE_URL"),
      requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { error: probeErr } = await service
      .from("workspace_invitations")
      .select("id")
      .limit(0);
    if (probeErr && (probeErr as { code?: string }).code === "PGRST205") {
      ready = false;
      console.warn("[revoke] SKIP: PostgREST schema cache stale (PGRST205).");
      return;
    }
    fixture = await createSharedWorkspaceMembers(service, 1);
  }, 60_000);

  afterAll(async () => {
    if (fixture) await tearDownSharedWorkspace(service, fixture);
  }, 60_000);

  test("owner revokes → invite absent from pending lookup + re-invite allowed", async () => {
    if (!ready) return;
    const owner = fixture.members[0];
    const email = syntheticWorkspaceFixtureEmail();

    const { invitationId, tokenHash } = await createInvite(
      service,
      fixture.workspaceId,
      owner.userId,
      email,
    );

    // Revoke as owner.
    const { data: revokeData, error: revokeErr } = await service.rpc(
      "revoke_workspace_invitation",
      { p_invitation_id: invitationId, p_caller_user_id: owner.userId },
    );
    expect(revokeErr).toBeNull();
    expect((revokeData as { ok: boolean }).ok).toBe(true);

    // FR4 (presentation gate): lookup returns reason 'revoked'.
    const { data: lookupData } = await service.rpc("lookup_invitation_by_token", {
      p_token_hash: tokenHash,
    });
    expect(lookupData).toMatchObject({ ok: false, reason: "revoked" });

    // FR4 (mutation gate): the accept RPC must ALSO reject the revoked invite —
    // a raw-token holder POSTing accept-invite directly bypasses lookup.
    const { data: acceptData } = await service.rpc("accept_workspace_invitation", {
      p_invitation_id: invitationId,
      p_accepter_user_id: owner.userId,
    });
    expect(acceptData).toMatchObject({ ok: false, reason: "revoked" });

    // FR3: the owner pending query (revoked_at IS NULL) excludes it.
    const { data: pendingRows } = await service
      .from("workspace_invitations")
      .select("id")
      .eq("workspace_id", fixture.workspaceId)
      .is("revoked_at", null)
      .eq("id", invitationId);
    expect(pendingRows ?? []).toHaveLength(0);

    // FR5: same email can be re-invited (duplicate-pending guard ignores revoked).
    const reinvite = await createInvite(service, fixture.workspaceId, owner.userId, email);
    expect(reinvite.invitationId).not.toBe(invitationId);

    // Double-revoke is idempotent-safe → already_revoked.
    const { data: secondRevoke } = await service.rpc("revoke_workspace_invitation", {
      p_invitation_id: invitationId,
      p_caller_user_id: owner.userId,
    });
    expect(secondRevoke).toMatchObject({ ok: false, reason: "already_revoked" });
  });

  test("non-owner cannot revoke (caller_not_owner)", async () => {
    if (!ready) return;
    const owner = fixture.members[0];
    const email = syntheticWorkspaceFixtureEmail();
    const { invitationId } = await createInvite(service, fixture.workspaceId, owner.userId, email);

    const strangerId = "99999999-9999-9999-9999-999999999999";
    const { data } = await service.rpc("revoke_workspace_invitation", {
      p_invitation_id: invitationId,
      p_caller_user_id: strangerId,
    });
    expect(data).toMatchObject({ ok: false, reason: "caller_not_owner" });
  });
});
