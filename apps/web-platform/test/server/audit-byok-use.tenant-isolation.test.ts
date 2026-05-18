/**
 * audit_byok_use WORM enforcement — DB-layer integration test (PR-E #3887).
 *
 * Pins the Art. 5(2) accountability invariant: the WORM trigger on
 * `public.audit_byok_use` raises `P0001` on UPDATE and DELETE, even
 * for service-role. Complements the writer-side coverage already in
 * `agent-runner.tenant-isolation.test.ts` by asserting at the WORM-
 * trigger boundary directly.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Requires `doppler run -p soleur -c dev`.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/audit-byok-use.tenant-isolation.test.ts
 *
 * Synthesized fixtures only (cq-test-fixtures-synthesized-only).
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "node:crypto";

import { type MintedJwt, type UserId } from "@/lib/supabase/tenant";
import { installSharedMintCache } from "@/test/helpers/mint-once";

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
  if (!value) throw new Error(`[audit-byok-use] ${name} is required`);
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "audit_byok_use WORM enforcement (integration)",
  () => {
    let service: SupabaseClient;
    const userA = { id: "", email: syntheticEmail() };
    const userB = { id: "", email: syntheticEmail() };
    let seedRowId = "";
    let mintCache: Map<UserId, MintedJwt>;

    beforeAll(async () => {
      const url = requireEnv("SUPABASE_URL");
      requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
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
        expect(error, `createUser(${user.email}) failed`).toBeNull();
        if (data.user?.id) user.id = data.user.id;
        expect(user.id).toBeTruthy();
      }

      // Seed one audit row for userA via the canonical RPC (write_byok_audit).
      const { error: writeError } = await service.rpc("write_byok_audit", {
        p_invocation_id: randomUUID(),
        p_founder_id: userA.id,
        p_agent_role: "test-worm",
        p_token_count: 42,
        p_unit_cost_cents: 7,
      });
      expect(writeError, "write_byok_audit seed").toBeNull();

      // Look up the row id via service-role SELECT — RLS-bypass for fixture
      // setup only; production reads use the tenant-scoped client.
      const { data: rows, error: selError } = await service
        .from("audit_byok_use")
        .select("id")
        .eq("founder_id", userA.id)
        .eq("agent_role", "test-worm")
        .order("ts", { ascending: false })
        .limit(1);
      expect(selError, "select seed row").toBeNull();
      expect(rows?.length).toBe(1);
      seedRowId = rows![0].id;

      // Cap suite mint count to 2 — the RLS-scope test reads JWTs from
      // this map instead of calling `mintFounderJwt` per-test. See
      // test/helpers/mint-once.ts.
      mintCache = await installSharedMintCache([userA.id, userB.id]);
    });

    afterAll(async () => {
      // userB was provisioned for the RLS scope test but never had an
      // audit_byok_use row written for it, so its `users` row has no
      // dependent rows under the ON DELETE RESTRICT FK. Clean it.
      if (userB.id) {
        assertSynthetic(userB.email);
        await service.auth.admin.deleteUser(userB.id);
      }
      // userA holds the seeded test-worm audit row. The WORM trigger
      // blocks DELETE on `audit_byok_use`, and the founder_id FK is
      // ON DELETE RESTRICT, so userA cannot be removed without first
      // disabling the trigger inside a transaction. That maintenance
      // path is a synthetic-fixture sweeper RPC tracked as a follow-up
      // scope-out (see the PR-E review log / `denied_jti` cleanup
      // follow-up). For the closed-preview alpha the single per-run
      // orphan is acceptable; long-running CI nightlies should adopt the
      // sweeper before promotion.
    });

    test("UPDATE on audit_byok_use raises P0001 (service-role)", async () => {
      const { error } = await service
        .from("audit_byok_use")
        .update({ token_count: 999 })
        .eq("id", seedRowId);
      expect(error).not.toBeNull();
      expect(error!.code).toBe("P0001");
      expect(error!.message).toMatch(/append-only|WORM/i);
    });

    test("DELETE on audit_byok_use raises P0001 (service-role)", async () => {
      const { error } = await service
        .from("audit_byok_use")
        .delete()
        .eq("id", seedRowId);
      expect(error).not.toBeNull();
      expect(error!.code).toBe("P0001");
      expect(error!.message).toMatch(/append-only|WORM/i);
    });

    test("Tenant SELECT scoped to founder_id (RLS)", async () => {
      // userA's tenant client sees their own row; userB's tenant client
      // sees zero rows for userA's founder_id. Mints fresh JWTs via the
      // production mint path so the JWT carries the correct sub claim.
      const url = requireEnv("SUPABASE_URL");
      const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");

      const tenantClient = (userId: string) => {
        const cached = mintCache.get(userId);
        if (!cached) throw new Error(`no cached JWT for ${userId}`);
        return createClient(url, anonKey, {
          global: { headers: { Authorization: `Bearer ${cached.jwt}` } },
          auth: { persistSession: false, autoRefreshToken: false },
        });
      };

      const aClient = tenantClient(userA.id);
      const bClient = tenantClient(userB.id);

      const { data: aRows, error: aError } = await aClient
        .from("audit_byok_use")
        .select("id, founder_id")
        .eq("id", seedRowId);
      expect(aError).toBeNull();
      expect(aRows?.length).toBe(1);
      expect(aRows![0].founder_id).toBe(userA.id);

      const { data: bRows, error: bError } = await bClient
        .from("audit_byok_use")
        .select("id, founder_id")
        .eq("id", seedRowId);
      expect(bError).toBeNull();
      expect(bRows?.length).toBe(0);
    });
  },
);
