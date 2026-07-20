/**
 * Integration test — workspace-binding restart survival + memoization (task 2.7).
 *
 * Regression guard for the #5240 resume "blank/fresh tree" class. After a
 * backend process restart wipes the process-local `userWorkspaces` Map,
 * `resolveUserWorkspaceBinding` MUST rehydrate the user's active workspace from
 * the durable `user_session_state.current_workspace_id` (ADR-044
 * source-of-truth, #5338) instead of aborting with "No workspace binding for
 * user" — AND MUST memoize the rehydrated value so a second resolve on the same
 * connection skips the DB. The two properties are distinct (restart-survival vs
 * memoization), so the test asserts both with a single spy that must fire
 * EXACTLY ONCE across two resolves (spec-flow P2-A).
 *
 * This is the live-DB counterpart deferred from Phase 1 (operator decision
 * 2026-06-30). The unit branches are already covered with bare spies +
 * structural-mock supabase in `test/durable-workspace-binding-resolver.test.ts`.
 * What a unit spy CANNOT prove, and this test does: that the REAL
 * `readWorkspaceIdFromDb` round-trips the actual `user_session_state` row
 * through real SQL (table + column the resolver depends on genuinely exist and
 * read), and that a FAITHFUL restart — every registry Map empty, not just
 * `userWorkspaces` (spec-flow P2-B) — survives.
 *
 * Opt-in via WORKSPACE_BINDING_INTEGRATION_TEST=1. Runs against the real
 * Supabase dev project; requires `doppler run -p soleur -c dev` for env vars
 * (hr-dev-prd — DEV only, never prod).
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env WORKSPACE_BINDING_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run test/workspace-binding-restart-survival.integration.test.ts
 *
 * Plan: 2026-06-30-feat-phase2-git-data-lease-fencing-plan.md task 2.7 / AC7.
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "crypto";

import {
  resolveUserWorkspaceBinding,
  getUserWorkspace,
  __test_only__,
} from "@/server/agent-session-registry";
import { readWorkspaceIdFromDb } from "@/server/workspace-resolver";

const INTEGRATION_ENABLED =
  process.env.WORKSPACE_BINDING_INTEGRATION_TEST === "1";

// Only synthetic emails matching this pattern may be created or deleted by this
// test. Enforces hr-destructive-prod-tests-allowlist.
const SYNTHETIC_EMAIL_PATTERN = /^wsbinding-[a-f0-9]{16}@soleur\.test$/;

function syntheticEmail(): string {
  return `wsbinding-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates wsbinding-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`[workspace-binding.integration] ${name} is required`);
  }
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "workspace-binding restart survival + memoization (integration)",
  () => {
    let service: SupabaseClient;

    const user = {
      id: "",
      email: syntheticEmail(),
      password: randomBytes(16).toString("hex"),
    };
    // A distinct workspace (id != user.id) seeded as the user's
    // current_workspace_id. Using a NON-solo id is the decisive choice: it
    // proves the resolved binding is the value READ FROM THE DB, not a solo
    // (= user.id) default the resolver might otherwise have produced.
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
      // membership, and a workspace_member_actions audit row. Read the solo
      // workspace's organization to attach a second workspace under it.
      const { data: soloWs, error: soloErr } = await service
        .from("workspaces")
        .select("organization_id")
        .eq("id", user.id)
        .single();
      expect(soloErr, `solo workspace lookup failed: ${soloErr?.message}`).toBeNull();
      const orgId = (soloWs as { organization_id: string }).organization_id;

      // A distinct workspace under the same org (cq-test-fixtures-synthesized-only).
      teamWorkspaceId = randomUUID();
      const { error: teamWsErr } = await service.from("workspaces").insert({
        id: teamWorkspaceId,
        organization_id: orgId,
        name: "team-workspace",
      });
      expect(teamWsErr, `insert team workspace failed: ${teamWsErr?.message}`).toBeNull();

      // Seed the durable source-of-truth the resolver rehydrates from. service
      // role bypasses RLS (the table routes authenticated writes via the
      // set_current_workspace_id RPC; service writes directly). Upsert handles
      // whether the signup trigger already created the row.
      const { error: seedErr } = await service
        .from("user_session_state")
        .upsert(
          { user_id: user.id, current_workspace_id: teamWorkspaceId },
          { onConflict: "user_id" },
        );
      expect(seedErr, `seed user_session_state failed: ${seedErr?.message}`).toBeNull();
    }, 30_000);

    afterAll(async () => {
      // Scrub the process-local registry so a sibling suite in the same worker
      // never inherits this user's binding.
      __test_only__.clear();

      if (!service || !user.id) return;
      assertSynthetic(user.email);
      // Teardown in FK-dependency order, mirroring the established synthetic-user
      // sequence (concurrency-acquire-slot-workspace-id.integration.test.ts).
      // current_workspace_id is ON DELETE SET NULL so the team-workspace delete
      // is not blocked, but clear the session_state row explicitly for
      // determinism. The trigger-created solo membership + its WORM audit row
      // must be cleared via the anonymise_* RPCs (a DIRECT workspace_members
      // delete re-fires the audit trigger and re-blocks deleteUser).
      await service.from("user_session_state").delete().eq("user_id", user.id);
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
        // re-block this. The account is synthetic + dev-only; warn rather than
        // fail the suite on a teardown-only cascade gap.
        console.warn(
          `afterAll: deleteUser(${user.email}) failed: ${error.message}`,
        );
      }
    }, 30_000);

    test("rehydrates from the live DB once after a restart, then serves from the Map", async () => {
      // Faithful restart: clear EVERY registry Map, not just userWorkspaces. The
      // registry is a module-level singleton with no factory to reconstruct, so
      // __test_only__.clear() (which resets activeSessions, userWorkspaces, and
      // activeTurnConversations — the complete in-memory surface) is the truthful
      // proxy for the state a real process restart loses (spec-flow P2-B).
      __test_only__.clear();
      expect(getUserWorkspace(user.id)).toBeUndefined();
      expect(__test_only__.workspaceSize()).toBe(0);

      // Spy wrapper around the REAL durable reader so we can count DB reads
      // while exercising the genuine readWorkspaceIdFromDb → user_session_state
      // round-trip (vi.importActual-style wrap; a stubbed return would not prove
      // the live column reads).
      let dbReads = 0;
      const reader = (uid: string): Promise<string | null> => {
        dbReads += 1;
        return readWorkspaceIdFromDb(uid, service);
      };

      // Call 1 (cold, Map empty — the restart): the DB read fires, returns the
      // seeded id, and the resolver writes it back into the Map.
      const first = await resolveUserWorkspaceBinding(user.id, reader);
      expect(first).toBe(teamWorkspaceId);
      // Proves the value came from the DB, not a solo (= user.id) default.
      expect(first).not.toBe(user.id);
      expect(dbReads).toBe(1);
      expect(getUserWorkspace(user.id)).toBe(teamWorkspaceId); // writeback
      expect(__test_only__.workspaceSize()).toBe(1);

      // Call 2 (warm, Map populated): the Map hit serves the value and the DB
      // read does NOT fire again. The spy must read EXACTLY ONCE across both
      // calls — a vacuous (un-memoized) implementation would read twice.
      const second = await resolveUserWorkspaceBinding(user.id, reader);
      expect(second).toBe(teamWorkspaceId);
      expect(dbReads).toBe(1);
    }, 30_000);
  },
);
