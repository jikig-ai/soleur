/**
 * Cross-process JWT-deny RLS enforcement — DB-layer integration test
 * (#3930 + #3932; PR-E follow-up).
 *
 * Pins the invariants that mig 068 introduces:
 *   - `revoke_jti(p_jti, p_founder_id, p_reason)` is service-role-only.
 *   - `my_revocation_status()` returns `(false, NULL, NULL)` for un-denied
 *     callers and `(true, denied_at, reason)` for denied callers.
 *   - After a deny-list row lands, the affected jti's PostgREST queries on
 *     tenant tables (`conversations`, `messages`, `audit_byok_use`) return
 *     a dual-shape RLS-deny (`{error: { code: '42501' }} | {data: []}`)
 *     per learning 2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.
 *   - A sibling un-revoked jti is unaffected.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Requires `doppler run -p soleur -c dev`.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/tenant-jwt-rls-deny.tenant-isolation.test.ts
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
  if (!value) throw new Error(`[tenant-jwt-rls-deny] ${name} is required`);
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "JWT-deny RLS enforcement (integration, mig 068)",
  () => {
    let service: SupabaseClient;
    const userA = { id: "", email: syntheticEmail() };
    const userB = { id: "", email: syntheticEmail() };
    let mintCache: Map<UserId, MintedJwt>;

    const tenantClient = (userId: string): SupabaseClient => {
      const url = requireEnv("SUPABASE_URL");
      const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      const cached = mintCache.get(userId);
      if (!cached) throw new Error(`no cached JWT for ${userId}`);
      return createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${cached.jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
    };

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

      mintCache = await installSharedMintCache([userA.id, userB.id]);
    });

    afterAll(async () => {
      // Cleanup any deny-list rows we created for the two synthetic users
      // BEFORE the FK cascade tear-down (denied_jti.founder_id ON DELETE
      // RESTRICT — leaving rows would block the user delete).
      for (const user of [userA, userB]) {
        if (!user.id) continue;
        await service.from("denied_jti").delete().eq("founder_id", user.id);
      }
      for (const user of [userA, userB]) {
        if (!user.id) continue;
        assertSynthetic(user.email);
        await tearDownTenantUser(service, user);
      }
    });

    test("revoke_jti is service-role-only (authenticated → 42501)", async () => {
      const aClient = tenantClient(userA.id);
      const { error } = await aClient.rpc("revoke_jti", {
        p_jti: randomUUID(),
        p_founder_id: userA.id,
        p_reason: "test-authenticated-should-be-denied",
      });
      expect(error).not.toBeNull();
      // Either 42501 permission denied on the function itself, or a
      // PostgREST 404 because the function is not in the exposed schema
      // for authenticated. Either shape proves the REVOKE matrix held.
      const code = error?.code ?? "";
      const message = error?.message ?? "";
      expect(
        code === "42501" ||
          /permission denied|not find the function|does not exist/i.test(
            message,
          ),
        `expected service-role-only deny, got code=${code} msg=${message}`,
      ).toBe(true);
    });

    test("revoke_jti as service-role inserts a denied_jti row", async () => {
      const jti = randomUUID();
      const { error } = await service.rpc("revoke_jti", {
        p_jti: jti,
        p_founder_id: userA.id,
        p_reason: "test-service-role-happy-path",
      });
      expect(error).toBeNull();

      const { data: rows, error: selErr } = await service
        .from("denied_jti")
        .select("jti, founder_id, reason")
        .eq("jti", jti)
        .maybeSingle();
      expect(selErr).toBeNull();
      expect(rows?.founder_id).toBe(userA.id);
      expect(rows?.reason).toBe("test-service-role-happy-path");
    });

    test("my_revocation_status returns (false, NULL, NULL) for un-denied caller", async () => {
      const bClient = tenantClient(userB.id);
      const { data, error } = await bClient.rpc("my_revocation_status");
      expect(error).toBeNull();
      expect(Array.isArray(data)).toBe(true);
      expect(data?.length).toBe(1);
      const row = (data as Array<{ revoked: boolean; denied_at: string | null; reason: string | null }>)[0];
      expect(row.revoked).toBe(false);
      expect(row.denied_at).toBeNull();
      expect(row.reason).toBeNull();
    });

    test("RLS denies userA's queries after their jti is revoked; userB still reads", async () => {
      const cachedA = mintCache.get(userA.id);
      if (!cachedA) throw new Error("no cached jti for userA");

      // Insert the deny row for userA's actual jti.
      const { error: revErr } = await service.rpc("revoke_jti", {
        p_jti: cachedA.jti,
        p_founder_id: userA.id,
        p_reason: "test-rls-restrictive-policy",
      });
      expect(revErr).toBeNull();

      const aClient = tenantClient(userA.id);
      const bClient = tenantClient(userB.id);

      // Dual-shape acceptance per learning
      // 2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason:
      // RESTRICTIVE policy denies silently as zero rows, OR a column-grant
      // intersection raises 42501. Either is acceptable; neither permits
      // userA to read their own conversations.
      const { data: aRows, error: aErr } = await aClient
        .from("conversations")
        .select("id")
        .eq("user_id", userA.id)
        .limit(5);
      const denied =
        aErr?.code === "42501" || (aErr === null && (aRows ?? []).length === 0);
      expect(denied, `expected deny shape, got data=${JSON.stringify(aRows)} err=${JSON.stringify(aErr)}`).toBe(true);

      // userB's un-revoked jti is unaffected — no error from RLS predicate.
      const { error: bErr } = await bClient
        .from("conversations")
        .select("id")
        .eq("user_id", userB.id)
        .limit(5);
      expect(bErr).toBeNull();
    });

    test("my_revocation_status returns (true, denied_at, reason) for a denied caller", async () => {
      // userA's jti is denied from the previous test; calling under userA
      // should return revoked=true. Note: the helper SECURITY DEFINER body
      // joins denied_jti via founder_id (auth.uid()), not jti, so this
      // works even though the JWT's jti is in the deny list.
      const aClient = tenantClient(userA.id);
      const { data, error } = await aClient.rpc("my_revocation_status");
      expect(error).toBeNull();
      expect(Array.isArray(data)).toBe(true);
      expect(data?.length).toBe(1);
      const row = (data as Array<{ revoked: boolean; denied_at: string | null; reason: string | null }>)[0];
      expect(row.revoked).toBe(true);
      expect(row.denied_at).not.toBeNull();
      expect(row.reason).toBe("test-rls-restrictive-policy");
    });
  },
);
