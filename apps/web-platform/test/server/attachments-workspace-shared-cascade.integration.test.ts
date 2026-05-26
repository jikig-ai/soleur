/**
 * Cascade pseudonymisation integration tests — mig 068 (#4318).
 *
 * Covers AC5(a)-(e) (full account-delete cascade) and AC6 (workspace-
 * member removal cascade). Both paths converge on the private RPC
 * `public._anonymise_authored_messages_internal(p_user_id, p_workspace_id)`
 * which sets `messages.user_id = NULL` for authored-with-attachments
 * rows in shared convs (i.e., convs the departing user does NOT own).
 *
 * E-1 (Phase 0 worklog): messages.user_id is uuid REFERENCES
 * auth.users(id) ON DELETE CASCADE — synthetic-pseudonym mints are
 * FK-invalid; the cascade nulls user_id to match codebase convention
 * (mig 051/048/044/053 anonymise_* RPCs).
 *
 * Fixture topology:
 *   - 1 shared workspace (W), 1 organization
 *   - 2 users: Alice (owner of W), Bob (member of W)
 *   - 1 conversation (shared_conv) in W, owned by Alice (c.user_id = Alice)
 *   - 1 conversation (solo_conv_bob) in Bob's solo workspace (c.user_id = Bob)
 *   - 1 message (shared_msg_bob) authored by Bob in shared_conv with
 *     1 message_attachment row (storage_path-only; no actual Storage upload
 *     required for the cascade assertion, which is DB-only)
 *   - 1 message (owner_msg_alice) authored by Alice in shared_conv with
 *     no attachment (control — should never be touched)
 *   - 1 message (solo_msg_bob) authored by Bob in solo_conv_bob with
 *     1 attachment (control — cascade-deletes with Bob's account)
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/attachments-workspace-shared-cascade.integration.test.ts
 *
 * **GREEN only after mig 068 applies to dev.** The pooler-via-operator
 * apply path is blocked (storage.objects is owned by
 * supabase_storage_admin; the `postgres` pooler role cannot
 * DROP POLICY on it). Dev auto-applies via
 * `.github/workflows/web-platform-release.yml#migrate` on push to main.
 * Pre-merge, these tests assert the cascade CONTRACT; they go GREEN
 * automatically on the first CI run after the PR lands.
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { randomUUID } from "node:crypto";

import {
  createSharedWorkspaceMembers,
  tearDownSharedWorkspace,
  type SharedWorkspaceFixture,
} from "@/test/helpers/workspace-members-fixtures";
import { tearDownTenantUser } from "@/test/helpers/tenant-isolation-teardown";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value)
    throw new Error(`[attachments-cascade] ${name} is required`);
  return value;
}

interface CascadeFixture {
  workspace: SharedWorkspaceFixture;
  sharedConvId: string;
  soloConvBobId: string;
  sharedMsgBobId: string;
  ownerMsgAliceId: string;
  soloMsgBobId: string;
  sharedAttachmentId: string;
  soloAttachmentId: string;
}

async function buildFixture(
  service: SupabaseClient,
): Promise<CascadeFixture> {
  const workspace = await createSharedWorkspaceMembers(service, 2);
  const [alice, bob] = workspace.members;

  // Conversation owned by Alice in shared workspace.
  const { data: sharedConvRow, error: sharedConvErr } = await service
    .from("conversations")
    .insert({
      user_id: alice.userId,
      workspace_id: workspace.workspaceId,
      domain_leader: "cto",
      status: "active",
    })
    .select("id")
    .single();
  if (sharedConvErr || !sharedConvRow)
    throw new Error(`shared conv insert: ${sharedConvErr?.message}`);
  const sharedConvId = sharedConvRow.id as string;

  // Bob's solo conversation (handle_new_user trigger provisioned his
  // solo workspace at workspaces.id = bob.userId per mig 053 N2).
  const { data: soloConvRow, error: soloConvErr } = await service
    .from("conversations")
    .insert({
      user_id: bob.userId,
      workspace_id: bob.userId,
      domain_leader: "cto",
      status: "active",
    })
    .select("id")
    .single();
  if (soloConvErr || !soloConvRow)
    throw new Error(`solo conv insert: ${soloConvErr?.message}`);
  const soloConvBobId = soloConvRow.id as string;

  // Bob's authored message in shared_conv (will be pseudonymised).
  const sharedMsgBobId = randomUUID();
  const { error: sharedMsgErr } = await service.from("messages").insert({
    id: sharedMsgBobId,
    conversation_id: sharedConvId,
    user_id: bob.userId,
    workspace_id: workspace.workspaceId,
    role: "user",
    content: "bob's message in shared conv with attachment",
    template_id: "default_legacy",
  });
  if (sharedMsgErr)
    throw new Error(`shared msg insert: ${sharedMsgErr.message}`);

  // Alice's authored message in shared_conv WITHOUT attachment (control).
  const ownerMsgAliceId = randomUUID();
  const { error: ownerMsgErr } = await service.from("messages").insert({
    id: ownerMsgAliceId,
    conversation_id: sharedConvId,
    user_id: alice.userId,
    workspace_id: workspace.workspaceId,
    role: "assistant",
    content: "alice's owner message — control, must remain untouched",
    template_id: "default_legacy",
  });
  if (ownerMsgErr)
    throw new Error(`owner msg insert: ${ownerMsgErr.message}`);

  // Bob's message in his solo conv (will cascade-delete with his account).
  const soloMsgBobId = randomUUID();
  const { error: soloMsgErr } = await service.from("messages").insert({
    id: soloMsgBobId,
    conversation_id: soloConvBobId,
    user_id: bob.userId,
    workspace_id: bob.userId,
    role: "user",
    content: "bob's solo message",
    template_id: "default_legacy",
  });
  if (soloMsgErr)
    throw new Error(`solo msg insert: ${soloMsgErr.message}`);

  // Attachments — one on bob's shared msg, one on his solo msg.
  // No actual Storage upload; the cascade RPC predicate only checks
  // EXISTS on message_attachments, not on Storage bytes.
  const sharedAttachmentId = randomUUID();
  const { error: sharedAttErr } = await service
    .from("message_attachments")
    .insert({
      id: sharedAttachmentId,
      message_id: sharedMsgBobId,
      storage_path: `${bob.userId}/${sharedConvId}/${randomUUID()}.png`,
      filename: "bob-shared.png",
      content_type: "image/png",
      size_bytes: 100,
    });
  if (sharedAttErr)
    throw new Error(`shared att insert: ${sharedAttErr.message}`);

  const soloAttachmentId = randomUUID();
  const { error: soloAttErr } = await service
    .from("message_attachments")
    .insert({
      id: soloAttachmentId,
      message_id: soloMsgBobId,
      storage_path: `${bob.userId}/${soloConvBobId}/${randomUUID()}.png`,
      filename: "bob-solo.png",
      content_type: "image/png",
      size_bytes: 100,
    });
  if (soloAttErr) throw new Error(`solo att insert: ${soloAttErr.message}`);

  return {
    workspace,
    sharedConvId,
    soloConvBobId,
    sharedMsgBobId,
    ownerMsgAliceId,
    soloMsgBobId,
    sharedAttachmentId,
    soloAttachmentId,
  };
}

async function tearDownFixture(
  service: SupabaseClient,
  fixture: CascadeFixture | null,
): Promise<void> {
  if (!fixture) return;
  // message_attachments + messages + conversations cascade-delete with
  // their parents; the workspace helper unwinds membership/org/users.
  try {
    await tearDownSharedWorkspace(service, fixture.workspace);
  } catch {
    // best-effort
  }
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "attachments workspace-shared cascade (mig 068 #4318)",
  () => {
    let service: SupabaseClient;

    beforeAll(async () => {
      const url = requireEnv("SUPABASE_URL");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      service = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
    });

    describe("AC5: full account-delete cascade (step 3.901)", () => {
      let fixture: CascadeFixture | null = null;

      beforeAll(async () => {
        fixture = await buildFixture(service);
      }, 30_000);

      afterAll(async () => {
        if (!service || !fixture) return;
        await tearDownFixture(service, fixture);
      }, 30_000);

      test("deleteAccount(bob) succeeds + cascade nulls his shared-conv attachment-message user_id, leaves Alice's owner message untouched", async () => {
        if (!fixture) throw new Error("fixture build failed");
        const bob = fixture.workspace.members[1];
        const { deleteAccount } = await import("@/server/account-delete");
        const result = await deleteAccount(bob.userId, bob.email);
        expect(
          result.success,
          `deleteAccount failed: ${result.error}`,
        ).toBe(true);

        // AC5(a): bob's shared-conv attachment-message persists, user_id = NULL.
        const { data: sharedMsgRow, error: sharedSelErr } = await service
          .from("messages")
          .select("id, user_id, content")
          .eq("id", fixture.sharedMsgBobId)
          .maybeSingle();
        expect(sharedSelErr).toBeNull();
        expect(sharedMsgRow).not.toBeNull();
        expect(sharedMsgRow!.user_id).toBeNull();
        // Content survives (controller-retained shared asset).
        expect(sharedMsgRow!.content).toContain("bob's message in shared conv");

        // AC5(b): Alice's owner message in same conv untouched.
        const { data: ownerMsgRow } = await service
          .from("messages")
          .select("id, user_id")
          .eq("id", fixture.ownerMsgAliceId)
          .maybeSingle();
        expect(ownerMsgRow).not.toBeNull();
        expect(ownerMsgRow!.user_id).toBe(fixture.workspace.members[0].userId);

        // AC5(c): Bob's solo-conv message cascade-DELETEd via auth.users
        // ON DELETE CASCADE → public.users → conversations → messages.
        const { data: soloMsgRow } = await service
          .from("messages")
          .select("id")
          .eq("id", fixture.soloMsgBobId)
          .maybeSingle();
        expect(soloMsgRow).toBeNull();

        // message_attachments cascade-delete with the parent message.
        const { data: soloAttRow } = await service
          .from("message_attachments")
          .select("id")
          .eq("id", fixture.soloAttachmentId)
          .maybeSingle();
        expect(soloAttRow).toBeNull();

        // The shared message_attachment row survives (parent message
        // survived with user_id=NULL).
        const { data: sharedAttRow } = await service
          .from("message_attachments")
          .select("id, storage_path, filename")
          .eq("id", fixture.sharedAttachmentId)
          .maybeSingle();
        expect(sharedAttRow).not.toBeNull();
        expect(sharedAttRow!.filename).toBe("bob-shared.png");
      }, 60_000);
    });

    describe("AC6: workspace-member-removal cascade (folded inside remove_workspace_member RPC)", () => {
      let fixture: CascadeFixture | null = null;

      beforeAll(async () => {
        fixture = await buildFixture(service);
      }, 30_000);

      afterAll(async () => {
        if (!service || !fixture) return;
        // Bob still has an auth row in this branch (removeWorkspaceMember
        // does NOT delete auth.users). Tear it down explicitly.
        try {
          const bob = fixture.workspace.members[1];
          await tearDownTenantUser(service, { id: bob.userId, email: bob.email });
        } catch {}
        await tearDownFixture(service, fixture);
      }, 30_000);

      test("remove_workspace_member(W, bob) atomically nulls bob's shared-conv attachment-message user_id BEFORE the membership DELETE", async () => {
        if (!fixture) throw new Error("fixture build failed");
        const [alice, bob] = fixture.workspace.members;

        // Caller must be an owner; mig 067 enforces this via auth.uid().
        // Service-role call: we set request.jwt.claims to Alice's sub so
        // auth.uid() inside the SECURITY DEFINER RPC resolves correctly.
        // (Service-role bypasses RLS for the SELECT/DELETE but the RPC
        // body's `IF v_caller_user_id IS NULL THEN RAISE` check fires
        // on auth.uid() = NULL, so the claim header is load-bearing.)
        const url = requireEnv("SUPABASE_URL");
        const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
        const { mintFounderJwt } = await import("@/lib/supabase/tenant");
        const aliceMint = await mintFounderJwt(alice.userId);
        const aliceClient = createClient(url, anonKey, {
          global: { headers: { Authorization: `Bearer ${aliceMint.jwt}` } },
          auth: { persistSession: false, autoRefreshToken: false },
        });

        const { error: rpcErr } = await aliceClient.rpc("remove_workspace_member", {
          p_workspace_id: fixture.workspace.workspaceId,
          p_user_id: bob.userId,
        });
        expect(rpcErr, `remove_workspace_member failed: ${rpcErr?.message}`).toBeNull();

        // AC6: bob's shared-conv attachment-message has user_id = NULL.
        const { data: sharedMsgRow } = await service
          .from("messages")
          .select("id, user_id")
          .eq("id", fixture.sharedMsgBobId)
          .maybeSingle();
        expect(sharedMsgRow).not.toBeNull();
        expect(sharedMsgRow!.user_id).toBeNull();

        // Bob's solo-conv message survives intact (NOT in W; the
        // cascade RPC's predicate filters to m.workspace_id = W).
        const { data: soloMsgRow } = await service
          .from("messages")
          .select("id, user_id")
          .eq("id", fixture.soloMsgBobId)
          .maybeSingle();
        expect(soloMsgRow).not.toBeNull();
        expect(soloMsgRow!.user_id).toBe(bob.userId);

        // Alice's owner message untouched.
        const { data: ownerMsgRow } = await service
          .from("messages")
          .select("id, user_id")
          .eq("id", fixture.ownerMsgAliceId)
          .maybeSingle();
        expect(ownerMsgRow).not.toBeNull();
        expect(ownerMsgRow!.user_id).toBe(alice.userId);

        // Bob's workspace_members row was DELETEd by the RPC's
        // post-cascade DELETE (the F2 ordering invariant).
        const { data: memberRow } = await service
          .from("workspace_members")
          .select("user_id")
          .eq("workspace_id", fixture.workspace.workspaceId)
          .eq("user_id", bob.userId)
          .maybeSingle();
        expect(memberRow).toBeNull();

        // workspace_member_removals WORM row written.
        const { data: removalRow } = await service
          .from("workspace_member_removals")
          .select("workspace_id, removed_user_id, removed_by_user_id, revocation_reason")
          .eq("workspace_id", fixture.workspace.workspaceId)
          .eq("removed_user_id", bob.userId)
          .maybeSingle();
        expect(removalRow).not.toBeNull();
        expect(removalRow!.removed_by_user_id).toBe(alice.userId);
        expect(removalRow!.revocation_reason).toBe("removed");
      }, 60_000);
    });
  },
);
