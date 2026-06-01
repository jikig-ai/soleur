/**
 * Invite acceptance — live behavior (fix-invite-accept-attestation-overwrite).
 *
 * Regression guard for migration 090: before the fix, accept_workspace_invitation
 * ALWAYS failed with P0001 "workspace_invitations attestation_id is immutable
 * once set" because create_workspace_invitation sets attestation_id at creation
 * and the no_mutate trigger forbids changing it, yet accept tried to overwrite
 * it. This exercises the real RPC end-to-end so the schema/trigger/RPC
 * contradiction (which the unit mocks cannot see) stays fixed.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1 against DEV Supabase only
 * (hr-dev-prd-distinct-supabase-projects). Synthesized fixtures per
 * cq-test-fixtures-synthesized-only.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/workspace-invitations-accept.integration.test.ts
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

function freshTokenHash(): string {
  return createHash("sha256").update(randomBytes(32)).digest("hex");
}

describe.skipIf(!INTEGRATION_ENABLED)("accept_workspace_invitation — live", () => {
  let service: SupabaseClient;
  let ownerFx: SharedWorkspaceFixture;
  let inviteeFx: SharedWorkspaceFixture;
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
      console.warn("[accept] SKIP: PostgREST schema cache stale (PGRST205).");
      return;
    }
    // ownerFx provides the workspace + owner; inviteeFx provides a real
    // public.users row that is NOT yet a member of ownerFx's workspace.
    ownerFx = await createSharedWorkspaceMembers(service, 1);
    inviteeFx = await createSharedWorkspaceMembers(service, 1);
  }, 90_000);

  afterAll(async () => {
    if (inviteeFx) await tearDownSharedWorkspace(service, inviteeFx);
    if (ownerFx) await tearDownSharedWorkspace(service, ownerFx);
  }, 90_000);

  test("owner invites → invitee accepts → membership created, accepted_at set, attestation immutable", async () => {
    if (!ready) return;
    const owner = ownerFx.members[0];
    const invitee = inviteeFx.members[0];

    // 1. Create the invitation (sets attestation_id at creation time).
    const { data: createData, error: createErr } = await service.rpc(
      "create_workspace_invitation",
      {
        p_workspace_id: ownerFx.workspaceId,
        p_invitee_email: invitee.email,
        p_role: "member",
        p_token_hash: freshTokenHash(),
        p_attestation_text: "integration-test invite",
        p_caller_user_id: owner.userId,
      },
    );
    expect(createErr).toBeNull();
    expect((createData as { ok: boolean }).ok).toBe(true);
    const invitationId = (createData as { invitation_id: string }).invitation_id;

    const { data: invBefore } = await service
      .from("workspace_invitations")
      .select("attestation_id, accepted_at")
      .eq("id", invitationId)
      .single();
    const creationAttestationId = (invBefore as { attestation_id: string }).attestation_id;
    expect(creationAttestationId).toBeTruthy();

    // 2. Accept as the invitee — the path that regressed (P0001 before 090).
    const { data: acceptData, error: acceptErr } = await service.rpc(
      "accept_workspace_invitation",
      { p_invitation_id: invitationId, p_accepter_user_id: invitee.userId },
    );
    expect(acceptErr).toBeNull();
    expect(acceptData).toMatchObject({ ok: true, workspace_id: ownerFx.workspaceId });

    // 3. Membership row created, linked to the NEW acceptance attestation.
    const { data: memberRow } = await service
      .from("workspace_members")
      .select("role, attestation_id")
      .eq("workspace_id", ownerFx.workspaceId)
      .eq("user_id", invitee.userId)
      .single();
    expect(memberRow).toMatchObject({ role: "member" });
    expect((memberRow as { attestation_id: string }).attestation_id).toBe(
      (acceptData as { attestation_id: string }).attestation_id,
    );

    // 4. Invitation: accepted_at set; attestation_id UNCHANGED (creation one).
    const { data: invAfter } = await service
      .from("workspace_invitations")
      .select("accepted_at, attestation_id")
      .eq("id", invitationId)
      .single();
    expect((invAfter as { accepted_at: string | null }).accepted_at).not.toBeNull();
    expect((invAfter as { attestation_id: string }).attestation_id).toBe(creationAttestationId);

    // 5. Double-accept is idempotent-safe → already_accepted.
    const { data: secondAccept } = await service.rpc("accept_workspace_invitation", {
      p_invitation_id: invitationId,
      p_accepter_user_id: invitee.userId,
    });
    expect(secondAccept).toMatchObject({ ok: false, reason: "already_accepted" });
  });

  test("RPC-level identity binding: a non-intended user cannot accept (not_intended_invitee)", async () => {
    if (!ready) return;
    const owner = ownerFx.members[0];
    // Address the invite to a fresh synthetic email that resolves to no user
    // (invitee_user_id IS NULL → the email-mismatch branch — the raw-token-holder
    // defense). Self-contained: does not depend on the membership state mutated
    // by the prior test.
    const strangerEmail = syntheticWorkspaceFixtureEmail();
    const { data: createData } = await service.rpc("create_workspace_invitation", {
      p_workspace_id: ownerFx.workspaceId,
      p_invitee_email: strangerEmail,
      p_role: "member",
      p_token_hash: freshTokenHash(),
      p_attestation_text: "integration-test invite (identity)",
      p_caller_user_id: owner.userId,
    });
    const invitationId = (createData as { invitation_id: string }).invitation_id;

    // Accepting as `owner` (whose email != strangerEmail) must be rejected by the
    // RPC itself — this is the 076 defense-in-depth restored in migration 090,
    // independent of the route's 403 gate.
    const { data: wrongAccept } = await service.rpc("accept_workspace_invitation", {
      p_invitation_id: invitationId,
      p_accepter_user_id: owner.userId,
    });
    expect(wrongAccept).toMatchObject({ ok: false, reason: "not_intended_invitee" });
  });
});
