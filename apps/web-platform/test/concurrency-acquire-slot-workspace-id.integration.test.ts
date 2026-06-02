/**
 * Integration test — acquire_conversation_slot MUST populate workspace_id.
 *
 * Regression guard for the production Sentry `concurrency silent fallback`
 * (issue 52442f7a9b77462b9927b1f055204cce): `feature=concurrency`,
 * `op=acquireSlot`, `pg_code=23502`. Migration 059 added
 * `user_concurrency_slots.workspace_id NOT NULL` but the slot writer RPC
 * (`acquire_conversation_slot`, defined in 029) was never re-issued, so its
 * INSERT omitted `workspace_id` and every NEW-conversation acquire failed the
 * NOT NULL constraint (23502). Migration 093 re-issues the RPC with a 4th
 * `p_workspace_id` arg.
 *
 * RED→GREEN: before migration 093 the 4-arg overload does not exist
 * (PostgREST PGRST202 / "function not found"); after 093 it returns ok and
 * persists the supplied workspace_id. The pre-fix 3-arg 23502 was confirmed
 * live against dev (plan Phase 0.5).
 *
 * Opt-in via ACQUIRE_SLOT_WS_INTEGRATION_TEST=1. Runs against the real
 * Supabase dev project; requires `doppler run -p soleur -c dev` for env vars.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env ACQUIRE_SLOT_WS_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run test/concurrency-acquire-slot-workspace-id.integration.test.ts
 *
 * Plan: 2026-06-02-fix-acquire-slot-workspace-id-not-null-violation-plan.md AC6/AC7.
 */

import { afterAll, afterEach, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "crypto";

const INTEGRATION_ENABLED =
  process.env.ACQUIRE_SLOT_WS_INTEGRATION_TEST === "1";

// Only synthetic emails matching this pattern may be created or deleted by
// this test. Enforces hr-destructive-prod-tests-allowlist.
const SYNTHETIC_EMAIL_PATTERN = /^acquire-slot-ws-[a-f0-9]{16}@soleur\.test$/;

function syntheticEmail(): string {
  return `acquire-slot-ws-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates acquire-slot-ws-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`[acquire-slot-ws.integration] ${name} is required`);
  }
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "acquire_conversation_slot populates workspace_id (integration)",
  () => {
    let service: SupabaseClient;

    const user = {
      id: "",
      email: syntheticEmail(),
      password: randomBytes(16).toString("hex"),
    };
    // A distinct workspace (id != user.id) the test attaches under the same
    // organization — used to prove the slot tracks the supplied workspace_id,
    // not a hardcoded solo value.
    let teamWorkspaceId = "";

    beforeAll(async () => {
      const supabaseUrl = requireEnv("NEXT_PUBLIC_SUPABASE_URL");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

      service = createClient(supabaseUrl, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      assertSynthetic(user.email);
      const { data, error } = await service.auth.admin.createUser({
        email: user.email,
        password: user.password,
        email_confirm: true,
      });
      // Assign id BEFORE asserting so afterAll cleanup runs even if a flaky
      // post-create assertion below trips.
      user.id = data.user?.id ?? "";
      expect(error, `createUser(${user.email}) failed`).toBeNull();
      expect(user.id).toBeTruthy();

      // The new-user trigger auto-creates the solo organization, the solo
      // workspace (workspaces.id = user.id per ADR-038 N2), the owner
      // membership, and a workspace_member_actions audit row. Do NOT recreate
      // them. Read the solo workspace's organization to attach a second
      // workspace under it.
      const { data: soloWs, error: soloErr } = await service
        .from("workspaces")
        .select("organization_id")
        .eq("id", user.id)
        .single();
      expect(soloErr, `solo workspace lookup failed: ${soloErr?.message}`).toBeNull();
      const orgId = (soloWs as { organization_id: string }).organization_id;

      // A distinct workspace under the same org. acquire_conversation_slot is
      // SECURITY DEFINER and only requires the workspace row to EXIST (FK) — no
      // membership row is needed to prove the slot tracks the supplied
      // workspace_id (cq-test-fixtures-synthesized-only).
      teamWorkspaceId = randomUUID();
      const { error: teamWsErr } = await service.from("workspaces").insert({
        id: teamWorkspaceId,
        organization_id: orgId,
        name: "team-workspace",
      });
      expect(teamWsErr, `insert team workspace failed: ${teamWsErr?.message}`).toBeNull();
    }, 30_000);

    afterEach(async () => {
      if (!service || !user.id) return;
      // Per-test cleanup so slot rows from one test don't skew the next.
      await service
        .from("user_concurrency_slots")
        .delete()
        .eq("user_id", user.id);
    });

    afterAll(async () => {
      if (!service || !user.id) return;
      assertSynthetic(user.email);
      // Teardown in FK-dependency order. The trigger-created solo
      // membership + its WORM audit row must be cleared for deleteUser to
      // succeed (workspace_member_actions.{target,actor}_user_id are RESTRICT
      // FKs to public.users). Use the anonymise_* RPCs — a DIRECT delete of
      // workspace_members fires the audit trigger and RE-creates a
      // workspace_member_actions row referencing the user, re-blocking the
      // delete. anonymise_workspace_members sets app.worm_bypass to suppress
      // that audit; anonymise_workspace_member_actions NULLs the existing
      // membership-creation audit row's user refs.
      await service.from("user_concurrency_slots").delete().eq("user_id", user.id);
      await service.from("conversations").delete().eq("user_id", user.id);
      await service.rpc("anonymise_workspace_members", { p_user_id: user.id });
      await service.rpc("anonymise_workspace_member_actions", {
        p_user_id: user.id,
      });
      if (teamWorkspaceId) {
        await service.from("workspaces").delete().eq("id", teamWorkspaceId);
      }
      await service.from("workspaces").delete().eq("id", user.id);
      await service.from("organizations").delete().eq("owner_user_id", user.id);

      const { error } = await service.auth.admin.deleteUser(user.id);
      if (error && !/not found/i.test(error.message)) {
        // Best-effort: a future trigger-added RESTRICT FK to users could
        // re-block this. The account is synthetic + dev-only; warn rather
        // than fail the suite on a teardown-only cascade gap.
        console.warn(
          `afterAll: deleteUser(${user.email}) failed: ${error.message}`,
        );
      }
    }, 30_000);

    async function acquireSlot(
      conversationId: string,
      workspaceId: string,
      cap = 5,
    ): Promise<{ status: string; active_count: number }> {
      const { data, error } = await service.rpc("acquire_conversation_slot", {
        p_user_id: user.id,
        p_conversation_id: conversationId,
        p_effective_cap: cap,
        p_workspace_id: workspaceId,
      });
      expect(
        error,
        `acquire_conversation_slot failed: ${error?.message} (code ${error?.code})`,
      ).toBeNull();
      const row = Array.isArray(data) ? data[0] : data;
      return { status: row.status, active_count: row.active_count };
    }

    async function slotWorkspaceId(
      conversationId: string,
    ): Promise<string | null> {
      const { data, error } = await service
        .from("user_concurrency_slots")
        .select("workspace_id")
        .eq("user_id", user.id)
        .eq("conversation_id", conversationId)
        .maybeSingle();
      expect(error, `slot lookup failed: ${error?.message}`).toBeNull();
      return (data as { workspace_id?: string } | null)?.workspace_id ?? null;
    }

    test("solo acquire: status ok and slot.workspace_id = userId (solo N2)", async () => {
      const convId = randomUUID();
      const result = await acquireSlot(convId, user.id);
      expect(result.status).toBe("ok");
      // The slot row carries the supplied (solo) workspace_id — proving the
      // 23502 NOT NULL violation is closed.
      expect(await slotWorkspaceId(convId)).toBe(user.id);
    }, 30_000);

    test("team acquire: slot tracks the ACTIVE workspace, not a hardcoded solo value", async () => {
      const convId = randomUUID();
      const result = await acquireSlot(convId, teamWorkspaceId);
      expect(result.status).toBe("ok");
      // The decisive assertion: passing a distinct owned workspace persists
      // THAT workspace_id, not user.id — so the slot keys to the conversation's
      // active workspace (matches createConversation's workspace_id).
      expect(await slotWorkspaceId(convId)).toBe(teamWorkspaceId);
      expect(await slotWorkspaceId(convId)).not.toBe(user.id);
    }, 30_000);
  },
);
