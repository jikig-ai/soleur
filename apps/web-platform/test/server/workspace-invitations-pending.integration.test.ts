/**
 * getPendingInvitesForUser — live behavior (#4715 recovery-banner deadlock).
 *
 * The unit test (workspace-invitations-pending-select.test.ts) asserts the
 * select STRING; this exercises the real query against DEV Supabase so a
 * column that does not exist on the resolved table (the 42703 class that
 * shipped in #4713 via `raw_user_meta_data` on public.users) fails loudly
 * here instead of returning a silent empty array in production.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1 against DEV Supabase only
 * (hr-dev-prd-distinct-supabase-projects). Synthesized fixtures per
 * cq-test-fixtures-synthesized-only.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/workspace-invitations-pending.integration.test.ts
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
import { getPendingInvitesForUser } from "@/server/workspace-invitations";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

function requireEnv(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing env: ${key}`);
  return v;
}

describe.skipIf(!INTEGRATION_ENABLED)("getPendingInvitesForUser — live", () => {
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
      console.warn("[pending] SKIP: PostgREST schema cache stale (PGRST205).");
      return;
    }
    fixture = await createSharedWorkspaceMembers(service, 1);
  }, 60_000);

  afterAll(async () => {
    if (fixture) await tearDownSharedWorkspace(service, fixture);
  }, 60_000);

  test("a pending invite is returned by email (no 42703 silent-empty)", async () => {
    if (!ready) return;
    const owner = fixture.members[0];
    const inviteeEmail = syntheticWorkspaceFixtureEmail();
    const tokenHash = createHash("sha256")
      .update(randomBytes(32).toString("base64url"))
      .digest("hex");

    const { data: createData, error: createErr } = await service.rpc(
      "create_workspace_invitation",
      {
        p_workspace_id: fixture.workspaceId,
        p_invitee_email: inviteeEmail,
        p_role: "member",
        p_token_hash: tokenHash,
        p_attestation_text: "integration-test invite",
        p_caller_user_id: owner.userId,
      },
    );
    expect(createErr).toBeNull();
    expect((createData as { ok: boolean }).ok).toBe(true);

    try {
      // The invitee has no account yet — match purely by email, exactly as the
      // recovery banner does for a keyless invitee. A random userId proves the
      // byEmail branch alone surfaces the invite.
      const invites = await getPendingInvitesForUser(
        randomBytes(16).toString("hex"),
        inviteeEmail,
      );

      const found = invites.find((i) => i.workspace_id === fixture.workspaceId);
      // The core regression: this would be undefined if the query errored
      // (42703) and returned [].
      expect(found).toBeDefined();
      expect(found?.role).toBe("member");
      // inviter_name derives from the inviter's public.users.email (the column
      // that actually exists), populated by the handle_new_user trigger.
      expect(found?.inviter_name).toBe(owner.email);
      expect(typeof found?.workspace_name).toBe("string");
    } finally {
      await service
        .from("workspace_invitations")
        .delete()
        .eq("invitee_email", inviteeEmail.toLowerCase());
    }
  }, 60_000);
});
