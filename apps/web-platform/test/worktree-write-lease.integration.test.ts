/**
 * Integration test — worktree_write_lease (migration 115) acquire/touch/release
 * semantics, RLS shape, and Art.17 cascade. Epic #5274 Phase 2, PR A.
 *
 * Covers plan ACs:
 *   AC2(a) two distinct hosts → exactly one holder; loser gets zero rows.
 *   AC2(b) same-host re-acquire of its own fresh lease → returns its row, SAME gen
 *          (the self-lockout regression guard).
 *   AC2(c) cross-host re-acquire after the 120s heartbeat expiry → gen+1.
 *   AC2(d) release frees the lease so a fresh acquire succeeds immediately.
 *   AC2(e) touch against a reclaimed/gen-bumped lease returns 0 (fail-loud signal);
 *          touch of a held lease returns 1.
 *   AC2(f) release with a stale lease_generation is a no-op (no stomp of a reclaimer).
 *   AC4   RLS: exactly one SELECT policy, zero write policies, on the table.
 *   AC5   deleting a workspace cascade-deletes its lease rows.
 *
 * Expiry is simulated by ageing heartbeat_at via the service client (service_role
 * bypasses RLS) rather than sleeping 120s.
 *
 * Opt-in via WORKTREE_LEASE_INTEGRATION_TEST=1. Runs against the real Supabase
 * DEV project (never prod — hr-dev-prd); requires `doppler run -p soleur -c dev`:
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env WORKTREE_LEASE_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run test/worktree-write-lease.integration.test.ts
 */

import { afterAll, afterEach, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "crypto";

const INTEGRATION_ENABLED =
  process.env.WORKTREE_LEASE_INTEGRATION_TEST === "1";

// Only synthetic emails matching this pattern may be created or deleted by this
// test (hr-destructive-prod-tests-allowlist, cq-test-fixtures-synthesized-only).
const SYNTHETIC_EMAIL_PATTERN = /^worktree-lease-[a-f0-9]{16}@soleur\.test$/;

function syntheticEmail(): string {
  return `worktree-lease-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates worktree-lease-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`[worktree-lease.integration] ${name} is required`);
  }
  return value;
}

const HOST_A = `host-a-${randomBytes(6).toString("hex")}`;
const HOST_B = `host-b-${randomBytes(6).toString("hex")}`;

describe.skipIf(!INTEGRATION_ENABLED)(
  "worktree_write_lease acquire/touch/release + RLS + cascade (integration)",
  () => {
    let service: SupabaseClient;

    const user = {
      id: "",
      email: syntheticEmail(),
      password: randomBytes(16).toString("hex"),
    };
    // A distinct workspace under the same org used for the cascade test (AC5):
    // deleting it must not require unwinding the trigger-created solo lineage.
    let teamWorkspaceId = "";
    const WORKTREE = "wt-main";

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
      user.id = data.user?.id ?? "";
      expect(error, `createUser(${user.email}) failed`).toBeNull();
      expect(user.id).toBeTruthy();

      // The new-user trigger (mig-053) auto-creates the solo org + workspace
      // (workspaces.id = user.id, ADR-038 N2) + owner membership + WORM audit.
      const { data: soloWs, error: soloErr } = await service
        .from("workspaces")
        .select("organization_id")
        .eq("id", user.id)
        .single();
      expect(soloErr, `solo workspace lookup failed: ${soloErr?.message}`).toBeNull();
      const orgId = (soloWs as { organization_id: string }).organization_id;

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
      // Per-test cleanup so lease rows from one test don't skew the next.
      await service
        .from("worktree_write_lease")
        .delete()
        .eq("workspace_id", user.id);
      if (teamWorkspaceId) {
        await service
          .from("worktree_write_lease")
          .delete()
          .eq("workspace_id", teamWorkspaceId);
      }
    });

    afterAll(async () => {
      if (!service || !user.id) return;
      assertSynthetic(user.email);
      // Teardown in FK-dependency order — the canonical synthetic-user sequence
      // (concurrency-acquire-slot-workspace-id.integration.test.ts:131-164):
      // anonymise the WORM membership audit BEFORE deleteUser, else the trigger
      // re-creates a workspace_member_actions row referencing the user.
      await service.from("worktree_write_lease").delete().eq("workspace_id", user.id);
      if (teamWorkspaceId) {
        await service.from("worktree_write_lease").delete().eq("workspace_id", teamWorkspaceId);
      }
      await service.rpc("anonymise_workspace_members", { p_user_id: user.id });
      await service.rpc("anonymise_workspace_member_actions", { p_user_id: user.id });
      if (teamWorkspaceId) {
        await service.from("workspaces").delete().eq("id", teamWorkspaceId);
      }
      await service.from("workspaces").delete().eq("id", user.id);
      await service.from("organizations").delete().eq("owner_user_id", user.id);
      const { error } = await service.auth.admin.deleteUser(user.id);
      if (error && !/not found/i.test(error.message)) {
        console.warn(`afterAll: deleteUser(${user.email}) failed: ${error.message}`);
      }
    }, 30_000);

    async function acquire(
      hostId: string,
      workspaceId = user.id,
      worktreeId = WORKTREE,
    ): Promise<{ host_id: string; lease_generation: number } | null> {
      const { data, error } = await service.rpc("acquire_worktree_lease", {
        p_workspace_id: workspaceId,
        p_worktree_id: worktreeId,
        p_host_id: hostId,
      });
      expect(error, `acquire failed: ${error?.message} (${error?.code})`).toBeNull();
      const rows = (data ?? []) as { host_id: string; lease_generation: number }[];
      return rows.length === 0 ? null : rows[0]!;
    }

    async function touch(hostId: string, gen: number): Promise<number> {
      const { data, error } = await service.rpc("touch_worktree_lease", {
        p_workspace_id: user.id,
        p_worktree_id: WORKTREE,
        p_host_id: hostId,
        p_lease_generation: gen,
      });
      expect(error, `touch failed: ${error?.message}`).toBeNull();
      return data as number;
    }

    async function release(hostId: string, gen: number): Promise<number> {
      const { data, error } = await service.rpc("release_worktree_lease", {
        p_workspace_id: user.id,
        p_worktree_id: WORKTREE,
        p_host_id: hostId,
        p_lease_generation: gen,
      });
      expect(error, `release failed: ${error?.message}`).toBeNull();
      return data as number;
    }

    async function ageHeartbeat(seconds: number): Promise<void> {
      // service_role bypasses RLS — age the heartbeat to simulate expiry.
      const { error } = await service
        .from("worktree_write_lease")
        .update({ heartbeat_at: new Date(Date.now() - seconds * 1000).toISOString() })
        .eq("workspace_id", user.id)
        .eq("worktree_id", WORKTREE);
      expect(error, `ageHeartbeat failed: ${error?.message}`).toBeNull();
    }

    test("AC2(a): two distinct hosts → one holder; loser gets zero rows", async () => {
      const a = await acquire(HOST_A);
      expect(a?.host_id).toBe(HOST_A);
      expect(a?.lease_generation).toBe(1);
      // HOST_B tries to take the still-fresh lease → loses (zero rows).
      const b = await acquire(HOST_B);
      expect(b).toBeNull();
    }, 30_000);

    test("AC2(b): same-host re-acquire of its own fresh lease keeps gen (self-lockout fix)", async () => {
      const first = await acquire(HOST_A);
      expect(first?.lease_generation).toBe(1);
      const second = await acquire(HOST_A);
      expect(second, "same-host re-acquire must return its row, not zero").not.toBeNull();
      expect(second?.host_id).toBe(HOST_A);
      expect(second?.lease_generation, "gen must stay stable on same-host refresh").toBe(1);
    }, 30_000);

    test("AC2(c): cross-host re-acquire after expiry bumps gen", async () => {
      const a = await acquire(HOST_A);
      expect(a?.lease_generation).toBe(1);
      await ageHeartbeat(121);
      const b = await acquire(HOST_B);
      expect(b?.host_id).toBe(HOST_B);
      expect(b?.lease_generation).toBe(2);
    }, 30_000);

    test("AC2(d): release frees the lease for an immediate fresh acquire", async () => {
      const a = await acquire(HOST_A);
      expect(await release(HOST_A, a!.lease_generation)).toBe(1);
      const reacquired = await acquire(HOST_B);
      expect(reacquired?.host_id).toBe(HOST_B);
      // First-ever insert after deletion → gen resets to the column default 1.
      expect(reacquired?.lease_generation).toBe(1);
    }, 30_000);

    test("AC2(e): touch returns 1 while held, 0 after reclaim", async () => {
      const a = await acquire(HOST_A);
      expect(await touch(HOST_A, a!.lease_generation)).toBe(1);
      await ageHeartbeat(121);
      const b = await acquire(HOST_B);
      expect(b?.lease_generation).toBe(2);
      // HOST_A's stale touch (gen=1) finds no matching row → 0 (fail-loud signal).
      expect(await touch(HOST_A, a!.lease_generation)).toBe(0);
    }, 30_000);

    test("AC2(f): release with a stale gen is a no-op (no stomp)", async () => {
      const a = await acquire(HOST_A);
      await ageHeartbeat(121);
      const b = await acquire(HOST_B);
      expect(b?.lease_generation).toBe(2);
      // HOST_A tries to release the lease it no longer holds (stale gen=1) → 0.
      expect(await release(HOST_A, a!.lease_generation)).toBe(0);
      // The lease is still HOST_B's gen=2 — unstomped.
      const { data } = await service
        .from("worktree_write_lease")
        .select("host_id, lease_generation")
        .eq("workspace_id", user.id)
        .eq("worktree_id", WORKTREE)
        .single();
      expect((data as { host_id: string }).host_id).toBe(HOST_B);
      expect((data as { lease_generation: number }).lease_generation).toBe(2);
    }, 30_000);

    test("AC4: table exists + service_role can read (RLS shape asserted in verify/115)", async () => {
      // pg_policy is not exposed via PostgREST, so the authoritative RLS-shape
      // assertion (exactly one SELECT policy, zero write policies, REVOKEd from
      // anon/authenticated, search_path-pinned RPCs) lives in the SQL sentinel
      // apps/web-platform/supabase/verify/115_worktree_write_lease.sql, run by
      // CI's verify-migrations job. Here, a service_role smoke check only:
      // service_role bypasses RLS, so a clean read proves the table + grants
      // exist without contradicting the RLS posture.
      const { error: existsErr } = await service
        .from("worktree_write_lease")
        .select("workspace_id")
        .limit(1);
      expect(existsErr, "table must exist and be queryable by service_role").toBeNull();
    }, 30_000);

    test("AC5: deleting a workspace cascade-deletes its lease rows (Art.17)", async () => {
      const a = await acquire(HOST_A, teamWorkspaceId);
      expect(a?.host_id).toBe(HOST_A);
      const { error: delErr } = await service
        .from("workspaces")
        .delete()
        .eq("id", teamWorkspaceId);
      expect(delErr, `workspace delete failed: ${delErr?.message}`).toBeNull();
      const { data } = await service
        .from("worktree_write_lease")
        .select("workspace_id")
        .eq("workspace_id", teamWorkspaceId);
      expect((data ?? []).length, "lease rows must cascade-delete with the workspace").toBe(0);
      teamWorkspaceId = ""; // already deleted — skip teardown double-delete
    }, 30_000);
  },
);
