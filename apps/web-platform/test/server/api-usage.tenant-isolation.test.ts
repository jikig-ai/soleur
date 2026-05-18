/**
 * Tenant isolation — api-usage.ts (PR-C §2.3, #3244).
 *
 * Covers the 1 migrated tenant site in `server/api-usage.ts`:
 *
 *   - `:96` SELECT conversations (MTD list — cost-bearing rows for the
 *     user's API-usage dashboard)
 *
 * The `:104` `sum_user_mtd_cost` RPC is PERMANENT service-role — REVOKE
 * EXECUTE FROM authenticated (migration 027:68). A tenant-JWT call to
 * that RPC must 42501 (insufficient_privilege); this suite asserts the
 * deny.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Same env-var matrix as the
 * canonical PR-B `agent-runner.tenant-isolation.test.ts`.
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
  "tenant isolation — api-usage.ts (1 site + REVOKED RPC)",
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

      // Seed cost-bearing conversations for each founder so the SELECT
      // surface has something to deny.
      for (const user of [userA, userB]) {
        const { error } = await service.from("conversations").insert({
          user_id: user.id,
          session_id: `tenant-isolation-${randomBytes(4).toString("hex")}`,
          total_cost_usd: "0.001000",
        });
        expect(error, `seed conversations for ${user.email}`).toBeNull();
      }

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
        const { error } = await service.auth.admin.deleteUser(user.id);
        if (error && !/not found/i.test(error.message)) {
          throw new Error(
            `afterAll: deleteUser(${user.email}) failed: ${error.message}`,
          );
        }
      }
    }, 30_000);

    test("baseline: A sees own cost-bearing conversation row", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .select("id, total_cost_usd")
        .eq("user_id", userA.id)
        .gt("total_cost_usd", 0);
      expect(error).toBeNull();
      expect(data?.length).toBeGreaterThan(0);
    });

    test("`:96` conversations SELECT — A's filter on B's user_id returns []", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .select(
          "id, domain_leader, created_at, input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens, total_cost_usd",
        )
        .eq("user_id", userB.id)
        .gt("total_cost_usd", 0)
        .order("created_at", { ascending: false })
        .limit(50);
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    test("`:104` sum_user_mtd_cost RPC under tenant JWT is denied (42501)", async () => {
      // The RPC is REVOKE EXECUTE FROM authenticated per migration 027:68;
      // tenant JWTs must NOT call it. This is the load-bearing reason the
      // file stays on `.service-role-allowlist` as PERMANENT.
      const { error } = await aClient.rpc("sum_user_mtd_cost", {
        uid: userA.id,
        since: "2026-01-01T00:00:00.000Z",
      });
      expect(error).not.toBeNull();
      expect(
        error!.code === "42501" || /permission/i.test(error!.message),
      ).toBe(true);
    });

    test("symmetric: B's filter on A's user_id returns []", async () => {
      const { data } = await bClient
        .from("conversations")
        .select("id")
        .eq("user_id", userA.id)
        .gt("total_cost_usd", 0);
      expect(data).toEqual([]);
    });
  },
);
