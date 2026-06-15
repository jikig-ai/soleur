/**
 * Conversation visibility RLS integration tests — PR-A (#4521).
 *
 * Exercises the dual-predicate policy `conversations_owner_or_shared`
 * (mig 075) and the `set_conversation_visibility` SECURITY DEFINER RPC.
 *
 * Setup: 3 synthetic users across 2 workspaces:
 *   - User A (owner of workspace 1)
 *   - User B (member of workspace 1)
 *   - User C (owner of workspace 2 — cross-workspace control)
 *
 * Opt-in via SUPABASE_DEV_INTEGRATION=1. Run from apps/web-platform:
 *   doppler run -p soleur -c dev -- \
 *     env SUPABASE_DEV_INTEGRATION=1 \
 *     ./node_modules/.bin/vitest run test/server/conversation-visibility.tenant-isolation.test.ts
 */

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomUUID } from "node:crypto";
import {
  createSharedWorkspaceMembers,
  tearDownSharedWorkspace,
  type SharedWorkspaceFixture,
} from "../helpers/workspace-members-fixtures";
import { withGoTrueRetry } from "../helpers/gotrue-retry";

const INTEGRATION_ENABLED =
  process.env.SUPABASE_DEV_INTEGRATION === "1";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value)
    throw new Error(`[conversation-visibility.integration] ${name} required`);
  return value;
}

const REPO_URL = "https://github.com/acme/visibility-test";

describe.skipIf(!INTEGRATION_ENABLED)(
  "Conversation visibility RLS + RPC (#4521 PR-A)",
  () => {
    let service: SupabaseClient;
    let supabaseUrl: string;
    let anonKey: string;

    // Workspace 1: userA (owner) + userB (member)
    let ws1: SharedWorkspaceFixture;
    // Workspace 2: userC (owner) — cross-workspace control
    let ws2: SharedWorkspaceFixture;

    let userAClient: SupabaseClient;
    let userBClient: SupabaseClient;
    let userCClient: SupabaseClient;

    // Conversation IDs created during setup
    let privateConvId: string;
    let sharedConvId: string;

    beforeAll(async () => {
      supabaseUrl = requireEnv("NEXT_PUBLIC_SUPABASE_URL");
      anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

      service = createClient(supabaseUrl, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      // Create workspaces: ws1 with 2 members, ws2 with 1 member
      ws1 = await createSharedWorkspaceMembers(service, 2);
      ws2 = await createSharedWorkspaceMembers(service, 1);

      const userA = ws1.members[0];
      const userB = ws1.members[1];
      const userC = ws2.members[0];

      // Set repo_url for all users
      for (const user of [userA, userB, userC]) {
        const { error } = await service
          .from("users")
          .update({ repo_url: REPO_URL })
          .eq("id", user.userId);
        expect(error, `set repo_url for ${user.email}`).toBeNull();
      }

      // Create User A's private conversation (via service role)
      privateConvId = randomUUID();
      const { error: privErr } = await service.from("conversations").insert({
        id: privateConvId,
        user_id: userA.userId,
        workspace_id: ws1.workspaceId,
        repo_url: REPO_URL,
        status: "active",
        last_active: new Date().toISOString(),
        visibility: "private",
      });
      expect(privErr, "insert private conversation").toBeNull();

      // Create User A's shared conversation (via service role)
      sharedConvId = randomUUID();
      const { error: sharedErr } = await service.from("conversations").insert({
        id: sharedConvId,
        user_id: userA.userId,
        workspace_id: ws1.workspaceId,
        repo_url: REPO_URL,
        status: "active",
        last_active: new Date().toISOString(),
        visibility: "workspace",
      });
      expect(sharedErr, "insert shared conversation").toBeNull();

      // Sign in as each user to get tenant JWTs
      userAClient = createClient(supabaseUrl, anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      // User A doesn't have a password in the fixture helper — use admin
      // to generate a session. The fixture helper uses createUser with a
      // random password we don't have access to. Use admin.generateLink
      // or just create fresh clients with service-role impersonation.
      // Actually — we need real tenant JWTs. Let me use the admin API
      // to update the user's password to a known value.
      const knownPassword = randomUUID();
      for (const user of [userA, userB, userC]) {
        const { error } = await service.auth.admin.updateUserById(user.userId, {
          password: knownPassword,
        });
        expect(error, `set password for ${user.email}`).toBeNull();
      }

      const { error: signInA } = await withGoTrueRetry("signIn:userA", () =>
        userAClient.auth.signInWithPassword({
          email: userA.email,
          password: knownPassword,
        }),
      );
      expect(signInA, "userA sign-in").toBeNull();

      userBClient = createClient(supabaseUrl, anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { error: signInB } = await withGoTrueRetry("signIn:userB", () =>
        userBClient.auth.signInWithPassword({
          email: userB.email,
          password: knownPassword,
        }),
      );
      expect(signInB, "userB sign-in").toBeNull();

      userCClient = createClient(supabaseUrl, anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { error: signInC } = await withGoTrueRetry("signIn:userC", () =>
        userCClient.auth.signInWithPassword({
          email: userC.email,
          password: knownPassword,
        }),
      );
      expect(signInC, "userC sign-in").toBeNull();
    }, 60_000);

    afterAll(async () => {
      if (!service) return;

      // Clean up conversations before workspace teardown (FK order)
      for (const id of [privateConvId, sharedConvId]) {
        if (id) await service.from("conversations").delete().eq("id", id);
      }

      if (ws1) await tearDownSharedWorkspace(service, ws1);
      if (ws2) await tearDownSharedWorkspace(service, ws2);
    }, 30_000);

    // ------------------------------------------------------------------
    // AC3: RLS deny — workspace member cannot see private conversations
    // ------------------------------------------------------------------
    it("User B cannot SELECT User A's private conversation", async () => {
      const { data, error } = await userBClient
        .from("conversations")
        .select("id")
        .eq("id", privateConvId);

      // dual-shape deny (TR5): PostgREST either returns 42501 error
      // or filters to empty array — both are correct RLS deny shapes.
      if (error) {
        expect(error.code).toBe("42501");
      } else {
        expect(data).toEqual([]);
      }

      // Poison-check: service-role confirms the row exists
      const { data: svcData } = await service
        .from("conversations")
        .select("id")
        .eq("id", privateConvId);
      expect(svcData).toHaveLength(1);
    });

    // ------------------------------------------------------------------
    // AC4: RLS allow — workspace member CAN see shared conversation
    // ------------------------------------------------------------------
    it("User B CAN SELECT User A's shared conversation", async () => {
      const { data, error } = await userBClient
        .from("conversations")
        .select("id, visibility")
        .eq("id", sharedConvId);

      expect(error).toBeNull();
      expect(data).toHaveLength(1);
      expect(data![0].id).toBe(sharedConvId);
      expect(data![0].visibility).toBe("workspace");
    });

    // ------------------------------------------------------------------
    // Positive control: owner always sees own conversations
    // ------------------------------------------------------------------
    it("User A can SELECT both private and shared own conversations", async () => {
      const { data, error } = await userAClient
        .from("conversations")
        .select("id")
        .in("id", [privateConvId, sharedConvId]);

      expect(error).toBeNull();
      expect(data).toHaveLength(2);
      const ids = data!.map((r) => r.id).sort();
      expect(ids).toEqual([privateConvId, sharedConvId].sort());
    });

    // ------------------------------------------------------------------
    // AC5: Cross-workspace deny
    // ------------------------------------------------------------------
    it("User C (different workspace) cannot SELECT any conversation", async () => {
      const { data, error } = await userCClient
        .from("conversations")
        .select("id")
        .in("id", [privateConvId, sharedConvId]);

      if (error) {
        expect(error.code).toBe("42501");
      } else {
        expect(data).toEqual([]);
      }
    });

    // ------------------------------------------------------------------
    // AC8: effective write-isolation contract for the visibility column.
    //
    // Mig 075's `REVOKE UPDATE(visibility) ON conversations FROM
    // authenticated` is a NO-OP on a real Supabase project: the table-level
    // `GRANT ... ON public.conversations TO authenticated` subsumes the
    // narrower column REVOKE, so `authenticated` retains column UPDATE.
    // (Confirmed live on dev AND prd; see the SOLEUR-DEBT marker in
    // mig 075_conversation_visibility.sql.) The ENFORCED contract is the
    // RLS policy `conversations_owner_update` — owner-only writes. These
    // tests assert that effective contract, not the defense-in-depth column
    // grant a clean-migration replica would have. A test that asserts the
    // column REVOKE cannot pass against any real Supabase project.
    //
    // SOLEUR-DEBT: mig 075 column REVOKE on conversations.visibility is a no-op (Supabase's table-level GRANT to authenticated subsumes it); RLS conversations_owner_update is the enforced guard so impact is nil; restore real column protection only if a non-owner write path to visibility that RLS does not cover is ever introduced, by GRANTing conversations at column granularity instead of ALL. (Marker lives here, not in mig 075 — editing an applied migration trips the content_sha drift probe.)
    // ------------------------------------------------------------------
    it("Owner CAN UPDATE own conversation visibility directly (RLS allows)", async () => {
      // Use a DEDICATED row, not the shared privateConvId — this is the only
      // destructive test in the suite, and coupling it to a shared row that
      // downstream tests assert on means a mid-test failure would cascade into
      // misleading downstream failures. Self-contained insert + finally-delete.
      const ownConvId = randomUUID();
      const userA = ws1.members[0];
      const { error: insErr } = await service.from("conversations").insert({
        id: ownConvId,
        user_id: userA.userId,
        workspace_id: ws1.workspaceId,
        repo_url: REPO_URL,
        status: "active",
        last_active: new Date().toISOString(),
        visibility: "private",
      });
      expect(insErr, "insert owner-update fixture row").toBeNull();

      try {
        const { error } = await userAClient
          .from("conversations")
          .update({ visibility: "workspace" } as Record<string, unknown>)
          .eq("id", ownConvId);
        expect(error).toBeNull();

        const { data: after } = await service
          .from("conversations")
          .select("visibility")
          .eq("id", ownConvId)
          .single();
        expect(after?.visibility).toBe("workspace");
      } finally {
        await service.from("conversations").delete().eq("id", ownConvId);
      }
    });

    it("Non-owner CANNOT UPDATE another owner's conversation visibility (RLS blocks)", async () => {
      const { data, error } = await userBClient
        .from("conversations")
        .update({ visibility: "private" } as Record<string, unknown>)
        .eq("id", sharedConvId)
        .select("id");

      // RLS owner-only UPDATE deny is dual-shape: a 42501 error, OR a 0-row
      // match (PostgREST returns no error when the USING clause filters all
      // candidate rows). Either is a correct deny.
      if (error) {
        expect(error.code).toBe("42501");
      } else {
        expect(data).toEqual([]);
      }

      // Load-bearing proof: service-role read-back confirms unchanged.
      const { data: unchanged } = await service
        .from("conversations")
        .select("visibility")
        .eq("id", sharedConvId)
        .single();
      expect(unchanged?.visibility).toBe("workspace");
    });

    it("anon CANNOT UPDATE visibility (RLS blocks)", async () => {
      const anonClient = createClient(supabaseUrl, anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await anonClient
        .from("conversations")
        .update({ visibility: "workspace" } as Record<string, unknown>)
        .eq("id", privateConvId)
        .select("id");

      // anon has no auth.uid(); the owner-update USING clause matches 0 rows.
      // Accept either an error or an empty result — both deny the write.
      if (!error) {
        expect(data).toEqual([]);
      }

      // Load-bearing proof: read-back confirms unchanged.
      const { data: unchanged } = await service
        .from("conversations")
        .select("visibility")
        .eq("id", privateConvId)
        .single();
      expect(unchanged?.visibility).toBe("private");
    });

    // ------------------------------------------------------------------
    // AC7: set_conversation_visibility RPC — owner can toggle
    // ------------------------------------------------------------------
    it("Owner can toggle visibility via RPC", async () => {
      // Toggle private → workspace
      const { error: toShared } = await userAClient.rpc(
        "set_conversation_visibility",
        {
          p_conversation_id: privateConvId,
          p_visibility: "workspace",
        },
      );
      expect(toShared).toBeNull();

      // Verify change
      const { data: after } = await service
        .from("conversations")
        .select("visibility")
        .eq("id", privateConvId)
        .single();
      expect(after?.visibility).toBe("workspace");

      // Toggle back to private
      const { error: toPrivate } = await userAClient.rpc(
        "set_conversation_visibility",
        {
          p_conversation_id: privateConvId,
          p_visibility: "private",
        },
      );
      expect(toPrivate).toBeNull();

      const { data: restored } = await service
        .from("conversations")
        .select("visibility")
        .eq("id", privateConvId)
        .single();
      expect(restored?.visibility).toBe("private");
    });

    // ------------------------------------------------------------------
    // AC7: set_conversation_visibility RPC — non-owner gets exception
    // ------------------------------------------------------------------
    it("Non-owner cannot toggle visibility via RPC", async () => {
      const { error } = await userBClient.rpc(
        "set_conversation_visibility",
        {
          p_conversation_id: sharedConvId,
          p_visibility: "private",
        },
      );

      expect(error).not.toBeNull();
      // RPC raises USING ERRCODE = 'insufficient_privilege' → SQLSTATE 42501
      // (mig 075's NOT-FOUND branch). The prior P0001 assertion was wrong
      // since #4521 — the RPC has never raised the default raise_exception
      // code; it was hidden because this opt-in suite never runs in CI.
      expect(error!.code).toBe("42501");

      // Verify unchanged
      const { data } = await service
        .from("conversations")
        .select("visibility")
        .eq("id", sharedConvId)
        .single();
      expect(data?.visibility).toBe("workspace");
    });

    // ------------------------------------------------------------------
    // AC6: workspace_id INSERT regression — conversation must include
    // workspace_id when created.
    // ------------------------------------------------------------------
    it("Conversation INSERT without workspace_id fails NOT NULL", async () => {
      const noWsConvId = randomUUID();
      const { error } = await service.from("conversations").insert({
        id: noWsConvId,
        user_id: ws1.members[0].userId,
        // workspace_id intentionally omitted
        repo_url: REPO_URL,
        status: "active",
        last_active: new Date().toISOString(),
      });

      // workspace_id is NOT NULL — should fail with 23502 (not_null_violation)
      expect(error).not.toBeNull();
      expect(error!.code).toBe("23502");
    });

    // ------------------------------------------------------------------
    // RPC validation: invalid visibility value rejected
    // ------------------------------------------------------------------
    it("RPC rejects invalid visibility value", async () => {
      const { error } = await userAClient.rpc(
        "set_conversation_visibility",
        {
          p_conversation_id: privateConvId,
          p_visibility: "public",
        },
      );

      expect(error).not.toBeNull();
    });
  },
);
