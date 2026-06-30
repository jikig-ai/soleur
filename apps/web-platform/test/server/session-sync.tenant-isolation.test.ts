/**
 * Tenant isolation — session-sync.ts (PR-C §2.1, #3244).
 *
 * Asserts founder A's runtime JWT cannot read or mutate founder B's
 * repo/sync state. Two RLS surfaces are covered:
 *
 *   - `users` (`auth.uid() = id`): `kb_sync_history` SELECT/UPDATE and
 *     `repo_last_synced_at` UPDATE — these columns survive on `users`.
 *   - `workspaces.github_installation_id` via the membership-scoped
 *     `resolve_workspace_installation_id(p_workspace_id)` DEFINER RPC.
 *     ADR-044 PR-2b (mig 112) dropped `users.github_installation_id` and
 *     relocated the credential to `workspaces`, where it is REVOKE'd from
 *     `authenticated` (mig 079) — a tenant `select("github_installation_id")`
 *     yields `42501`, not an isolation deny, so the cross-tenant check goes
 *     through the RPC and asserts NULL (membership deny == not-connected).
 *
 * RLS-policy on `users` is `auth.uid() = id` — a cross-tenant probe
 * MUST return zero rows (SELECT) and affect zero rows (UPDATE) under
 * tenant JWT. Synthesized fixtures only per
 * `cq-test-fixtures-synthesized-only`; JWT fixtures are minted via the
 * SUT's own `mintFounderJwt` (decode-verifiable per
 * `2026-04-29-jwt-fixture-reminting-decode-verify`).
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Runs against the dev Supabase
 * project; requires `doppler run -p soleur -c dev` to provide
 * SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
 * and SUPABASE_JWT_SECRET.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/session-sync.tenant-isolation.test.ts
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { randomBytes } from "node:crypto";

import {
  mintFounderJwt,
  _resetTenantCache,
} from "@/lib/supabase/tenant";
import { registerSharedMintCache } from "@/test/helpers/mint-once";
import { tearDownTenantUser } from "@/test/helpers/tenant-isolation-teardown";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

const SYNTHETIC_EMAIL_PATTERN =
  /^tenant-isolation-[a-f0-9]{16}@soleur\.test$/;

function syntheticEmail(): string {
  return `tenant-isolation-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates tenant-isolation-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`[tenant-isolation] ${name} is required`);
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "tenant isolation — session-sync.ts (4 sites)",
  () => {
    let service: SupabaseClient;
    let aClient: SupabaseClient;
    let bClient: SupabaseClient;

    const userA = { id: "", email: syntheticEmail() };
    const userB = { id: "", email: syntheticEmail() };

    beforeAll(async () => {
      const url = requireEnv("SUPABASE_URL");
      const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      requireEnv("SUPABASE_JWT_SECRET");

      service = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      // Provision two synthetic founders via auth admin.
      for (const user of [userA, userB]) {
        assertSynthetic(user.email);
        const { data, error } = await service.auth.admin.createUser({
          email: user.email,
          password: randomBytes(16).toString("hex"),
          email_confirm: true,
        });
        if (data.user?.id) user.id = data.user.id;
        expect(error, `createUser(${user.email}) failed`).toBeNull();
        expect(user.id).toBeTruthy();
      }

      // Seed users.kb_sync_history for both. The `users` row itself is
      // created by the `on auth.users insert` trigger (migration 002); we
      // only set the fields the SUT reads. `github_installation_id` was
      // dropped from `users` by mig 112 (ADR-044) — it is seeded on the
      // `workspaces` row below instead.
      for (const user of [userA, userB]) {
        const { error } = await service
          .from("users")
          .update({
            kb_sync_history: [{ date: "2026-01-01", count: 1 }],
          })
          .eq("id", user.id);
        expect(error, `seed users for ${user.email}`).toBeNull();
      }

      // Seed workspaces.github_installation_id for both. The mig-053
      // `handle_new_user` trigger pre-creates `workspaces(id = users.id)`,
      // so this is an UPDATE (an INSERT would PK-collide).
      for (const user of [userA, userB]) {
        const { error } = await service
          .from("workspaces")
          .update({
            github_installation_id: parseInt(user.id.slice(0, 8), 16),
          })
          .eq("id", user.id);
        expect(error, `seed workspaces for ${user.email}`).toBeNull();
      }

      // Mint runtime JWTs via the SUT.
      _resetTenantCache();
      const aMint = await mintFounderJwt(userA.id);
      const bMint = await mintFounderJwt(userB.id);
      // Cap suite mint count to 2 — see test/helpers/mint-once.ts.
      registerSharedMintCache([
        [userA.id, aMint],
        [userB.id, bMint],
      ]);

      aClient = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${aMint.jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      bClient = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${bMint.jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
    }, 30_000);

    afterAll(async () => {
      if (!service) return;
      for (const user of [userA, userB]) {
        if (!user.id) continue;
        assertSynthetic(user.email);
        const { data: check } = await service.auth.admin.getUserById(user.id);
        if (check?.user?.email && check.user.email !== user.email) {
          throw new Error(
            `afterAll: auth.users.email for ${user.id} (${check.user.email}) ` +
              `does not match synthetic email ${user.email}`,
          );
        }
        await tearDownTenantUser(service, user);
      }
    }, 30_000);

    test("baseline: A reads own github_installation_id via workspaces RPC", async () => {
      const { data, error } = await aClient.rpc(
        "resolve_workspace_installation_id",
        { p_workspace_id: userA.id },
      );
      expect(error).toBeNull();
      // The RPC returns the seeded bigint for the caller's own workspace.
      expect(Number(data)).toBe(parseInt(userA.id.slice(0, 8), 16));
    });

    test("getInstallationId — A cannot read B's github_installation_id (membership deny → NULL)", async () => {
      const { data, error } = await aClient.rpc(
        "resolve_workspace_installation_id",
        { p_workspace_id: userB.id },
      );
      // Membership-scoped DEFINER RPC returns NULL for a non-member caller
      // (deny == not-connected by design, mig 079). No 42501, no row leak.
      expect(error).toBeNull();
      expect(data).toBeNull();
    });

    test("`:236` recordKbSyncHistory SELECT — A cannot read B's kb_sync_history", async () => {
      const { data, error } = await aClient
        .from("users")
        .select("kb_sync_history")
        .eq("id", userB.id);
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    test("`:254` recordKbSyncHistory UPDATE — A cannot UPDATE B's kb_sync_history", async () => {
      const poison = [{ date: "1999-01-01", count: 9999 }];
      const { data, error } = await aClient
        .from("users")
        .update({ kb_sync_history: poison })
        .eq("id", userB.id)
        .select("id");
      // Accept either RLS-deny (error=null, data=[]) or grant-deny (42501,
      // data=null). Both are load-bearing safe; see
      // 2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.
      if (error) {
        expect(error.code).toBe("42501");
        expect(data).toBeNull();
      } else {
        expect(data).toEqual([]);
      }

      // invariant: service-role re-read confirms B's row is unchanged.
      const { data: stillThere } = await service
        .from("users")
        .select("kb_sync_history")
        .eq("id", userB.id)
        .maybeSingle();
      expect(stillThere?.kb_sync_history).not.toEqual(poison);
    });

    test("`:270` updateLastSynced — A cannot UPDATE B's repo_last_synced_at", async () => {
      const poison = "1999-01-01T00:00:00.000Z";
      const { data, error } = await aClient
        .from("users")
        .update({ repo_last_synced_at: poison })
        .eq("id", userB.id)
        .select("id");
      if (error) {
        expect(error.code).toBe("42501");
        expect(data).toBeNull();
      } else {
        expect(data).toEqual([]);
      }

      // invariant: service-role re-read confirms B's row is unchanged.
      const { data: stillThere } = await service
        .from("users")
        .select("repo_last_synced_at")
        .eq("id", userB.id)
        .maybeSingle();
      expect(stillThere?.repo_last_synced_at).not.toBe(poison);
    });

    test("symmetric: B cannot read or write A's users row either", async () => {
      // Read side — SELECT does not require an UPDATE grant; RLS-deny is the
      // expected path. Accept either shape for methodology hygiene.
      const { data: readByB, error: readError } = await bClient
        .from("users")
        .select("kb_sync_history, repo_last_synced_at")
        .eq("id", userA.id);
      if (readError) {
        expect(readError.code).toBe("42501");
        expect(readByB).toBeNull();
      } else {
        expect(readByB).toEqual([]);
      }

      // Write side — destructure error: pre-fix this surfaced as "expected null to equal []".
      const poison = "1999-01-01T00:00:00.000Z";
      const { data: writeByB, error: writeError } = await bClient
        .from("users")
        .update({ repo_last_synced_at: poison })
        .eq("id", userA.id)
        .select("id");
      if (writeError) {
        expect(writeError.code).toBe("42501");
        expect(writeByB).toBeNull();
      } else {
        expect(writeByB).toEqual([]);
      }

      // invariant: service-role re-read confirms A's row is unchanged.
      const { data: stillThereA } = await service
        .from("users")
        .select("repo_last_synced_at")
        .eq("id", userA.id)
        .maybeSingle();
      expect(stillThereA?.repo_last_synced_at).not.toBe(poison);
    });

    // Positive control (defer): A successfully UPDATEs A's own users row.
    // Fails today under the missing GRANT UPDATE ON public.users TO authenticated
    // (intentional defense-in-depth, see migration 006). Tracked in #3869 item 1
    // (helper consolidation) where the helper + positive control land together.
    test.todo(
      "positive control: A can UPDATE own users.repo_last_synced_at (pending #3869 grant alignment)",
    );
  },
);
