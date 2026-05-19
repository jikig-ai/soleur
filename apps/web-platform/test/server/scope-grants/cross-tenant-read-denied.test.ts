/**
 * Cross-tenant denial for scope_grants + audit_byok_use — TR2 (PR-G #3947).
 *
 * Asserts the brand-survival invariant: founder A's queries against
 * `scope_grants` and `audit_byok_use` return zero rows of founder B's
 * data. Covers two distinct trust boundaries:
 *
 *   1. RLS boundary — tenant-scoped clients (founder JWT) see only
 *      their own rows; cross-tenant SELECTs return zero rows even
 *      when the caller knows the other founder's id.
 *   2. Service-role boundary (webhook predicate) — `isGranted()` runs
 *      in service-role context (no founder JWT). The
 *      `.eq("founder_id", founderId)` is the load-bearing tenant
 *      filter, NOT belt-and-suspenders. A typo-but-real-other-founder
 *      id WOULD match (this is the upstream risk gate that lives at
 *      the customer→founder lookup, not here). A typoed never-seen
 *      id returns null — this is the founderId-typo regression case
 *      per Kieran P1-3 / AC3.
 *
 * Synthetic UUIDs use `crypto.randomUUID()` (NOT
 * `randomBytes(16).toString("hex")`) per learning
 * 2026-05-16-rls-deny-tests-payload-must-type-validate.md — non-UUID
 * payloads fail with `22P02` BEFORE RLS evaluates, masking a real
 * deny outcome.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Requires `doppler run -p soleur -c dev`.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/scope-grants/cross-tenant-read-denied.test.ts
 *
 * Synthesized fixtures only (cq-test-fixtures-synthesized-only).
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "node:crypto";

import { mintFounderJwt } from "@/lib/supabase/tenant";
import { isGranted } from "@/server/scope-grants/is-granted";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

const SYNTHETIC_EMAIL_PATTERN =
  /^tenant-isolation-[a-f0-9]{16}@soleur\.test$/;

const ACTION_CLASS = "finance.payment_failed";

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
  if (!value) {
    throw new Error(`[cross-tenant-read-denied] ${name} is required`);
  }
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "scope_grants + audit_byok_use cross-tenant denial (integration)",
  () => {
    let service: SupabaseClient;
    let url: string;
    let anonKey: string;
    const userA = { id: "", email: syntheticEmail() };
    const userB = { id: "", email: syntheticEmail() };

    const tenantClient = async (userId: string): Promise<SupabaseClient> => {
      const { jwt } = await mintFounderJwt(userId, { ttlSec: 600 });
      return createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
    };

    beforeAll(async () => {
      url = requireEnv("SUPABASE_URL");
      anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
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

      // Seed scope_grants for A and B via the founder-callable RPC,
      // which derives founder_id from auth.uid(). Service-role cannot
      // call it (auth.uid() is NULL) — must mint a tenant JWT.
      for (const user of [userA, userB]) {
        const client = await tenantClient(user.id);
        const { error } = await client.rpc("grant_action_class", {
          p_action_class: ACTION_CLASS,
          p_tier: "draft_one_click",
        });
        expect(error, `grant_action_class(${user.id}) failed`).toBeNull();
      }

      // Seed one audit_byok_use row for each user via the canonical
      // write_byok_audit RPC (service-role; RLS-bypass for fixture
      // setup only).
      for (const user of [userA, userB]) {
        const { error } = await service.rpc("write_byok_audit", {
          p_invocation_id: randomUUID(),
          p_founder_id: user.id,
          p_agent_role: "cross-tenant-read-denied",
          p_token_count: 11,
          p_unit_cost_cents: 3,
        });
        expect(error, `write_byok_audit(${user.id}) failed`).toBeNull();
      }
    });

    afterAll(async () => {
      // Tear down in FK-safe order: anonymise scope_grants first
      // (ON DELETE RESTRICT FK on founder_id), then delete the auth
      // user. audit_byok_use has the same RESTRICT FK + WORM trigger
      // so userA/userB rows leak per the precedent at
      // audit-byok-use.tenant-isolation.test.ts — sweeper RPC tracked
      // as a follow-up scope-out.
      for (const user of [userA, userB]) {
        if (!user.id) continue;
        assertSynthetic(user.email);
        await service.rpc("anonymise_scope_grants", { p_user_id: user.id });
        // Best-effort deleteUser — may fail if audit_byok_use rows
        // still hold the FK. Test-runner orphans are acceptable for
        // closed-preview alpha (see precedent file's afterAll note).
        await service.auth.admin.deleteUser(user.id);
      }
    });

    test("A reads own scope_grants via tenant client — 1 row", async () => {
      const aClient = await tenantClient(userA.id);
      const { data, error } = await aClient
        .from("scope_grants")
        .select("id, founder_id, action_class, tier")
        .is("revoked_at", null);
      expect(error).toBeNull();
      expect(data?.length).toBe(1);
      expect(data![0].founder_id).toBe(userA.id);
      expect(data![0].action_class).toBe(ACTION_CLASS);
    });

    test("A's tenant client filtering by B.id — 0 rows (RLS blocks)", async () => {
      // Even when the caller knows B's id and filters explicitly, RLS
      // (`auth.uid() = founder_id`) hides the row. This is the pure
      // RLS-boundary assertion.
      const aClient = await tenantClient(userA.id);
      const { data, error } = await aClient
        .from("scope_grants")
        .select("id, founder_id")
        .eq("founder_id", userB.id);
      expect(error).toBeNull();
      expect(data?.length).toBe(0);
    });

    test("A reads own audit_byok_use via tenant client — 1 row", async () => {
      const aClient = await tenantClient(userA.id);
      const { data, error } = await aClient
        .from("audit_byok_use")
        .select("id, founder_id, agent_role")
        .eq("agent_role", "cross-tenant-read-denied");
      expect(error).toBeNull();
      expect(data?.length).toBe(1);
      expect(data![0].founder_id).toBe(userA.id);
    });

    test("A's tenant client filtering audit_byok_use by B.id — 0 rows (belt-and-suspenders typo regression)", async () => {
      // If a viewer route ever typoes the founder filter to a known
      // OTHER founder's id, RLS still returns zero rows. The
      // .eq("founder_id", ...) on a tenant-scoped client is
      // belt-and-suspenders here — the RLS policy is the load-bearing
      // gate.
      const aClient = await tenantClient(userA.id);
      const { data, error } = await aClient
        .from("audit_byok_use")
        .select("id, founder_id")
        .eq("founder_id", userB.id);
      expect(error).toBeNull();
      expect(data?.length).toBe(0);
    });

    test("isGranted via service-role looks up by passed founderId (Kieran P1-3 founderId-typo regression)", async () => {
      // Service-role bypasses RLS, so the .eq("founder_id", founderId)
      // filter inside is-granted.ts IS the tenant gate. Two cases:
      //
      //   (a) Passing B's real id returns B's grant. A typo that
      //       happens to collide with a real other-founder id WOULD
      //       leak — that risk lives at the customer→founder lookup
      //       upstream (unique stripe_customer_id constraint), not
      //       inside isGranted. We pin the behavior here so future
      //       refactors don't regress the contract.
      //
      //   (b) Passing a never-seen UUID returns null. This is the
      //       founderId-typo regression case per AC3: a typoed id
      //       that doesn't match any founder MUST NOT match A's or
      //       B's grant.
      const grantForB = await isGranted(service, userB.id, ACTION_CLASS);
      expect(grantForB).not.toBeNull();
      expect(grantForB?.tier).toBe("draft_one_click");

      const unrelatedFounderId = randomUUID();
      const grantForUnrelated = await isGranted(
        service,
        unrelatedFounderId,
        ACTION_CLASS,
      );
      expect(grantForUnrelated).toBeNull();
    });
  },
);
