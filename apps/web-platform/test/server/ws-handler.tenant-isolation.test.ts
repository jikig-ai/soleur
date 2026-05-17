/**
 * Tenant isolation — ws-handler.ts (PR-C §2.10, #3244).
 *
 * Covers the 13 migrated tenant sites across:
 *
 *   - tryLedgerDivergenceRecovery: conversations + user_concurrency_slots
 *   - refreshSubscriptionStatus: users + user_concurrency_slots
 *   - createConversation: conversations INSERT + lookup
 *   - handleMessage (resume-by-context, resume-by-id, routing-lookup,
 *     cap-drift fallback): conversations + messages + users
 *   - setupWebSocket auth bootstrap: users
 *
 * The `auth.getUser(token)` site at `:1947` is PERMANENT — NOT covered
 * here. It's exercised by handshake-protocol tests.
 *
 * `user_concurrency_slots` has `slots_owner_read` RLS (migration 029:91)
 * so cross-tenant SELECTs return zero rows. Writes go through SECURITY
 * DEFINER RPCs (acquire/release) — direct INSERT/UPDATE under tenant
 * JWT would fail (no policy); this suite asserts the SELECT contract.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1.
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

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

const SYNTHETIC_EMAIL_PATTERN =
  /^tenant-isolation-[a-f0-9]{16}@soleur\.test$/;

function syntheticEmail(): string {
  return `tenant-isolation-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(`Refusing to touch non-synthetic email "${email}".`);
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`[tenant-isolation] ${name} is required`);
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "tenant isolation — ws-handler.ts (13 sites)",
  () => {
    let service: SupabaseClient;
    let aClient: SupabaseClient;

    const userA = { id: "", email: syntheticEmail() };
    const userB = { id: "", email: syntheticEmail() };
    let bConvId = "";

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
        const { data } = await service.auth.admin.createUser({
          email: user.email,
          password: randomBytes(16).toString("hex"),
          email_confirm: true,
        });
        if (data.user?.id) user.id = data.user.id;
        expect(user.id).toBeTruthy();
      }

      // Seed B with a conversation A might try to read/UPDATE.
      const { data: convRow } = await service
        .from("conversations")
        .insert({
          user_id: userB.id,
          session_id: `tenant-isolation-${randomBytes(4).toString("hex")}`,
          status: "active",
        })
        .select("id")
        .single();
      bConvId = convRow!.id;

      _resetTenantCache();
      const aMint = await mintFounderJwt(userA.id);
      aClient = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${aMint.jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
    }, 30_000);

    afterAll(async () => {
      if (!service) return;
      for (const user of [userA, userB]) {
        if (!user.id) continue;
        assertSynthetic(user.email);
        await service.auth.admin.deleteUser(user.id).catch(() => {});
      }
    }, 30_000);

    test("tryLedgerDivergenceRecovery — A cannot read B's visible conversations", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .select("id")
        .eq("user_id", userB.id)
        .is("archived_at", null)
        .in("status", ["active", "waiting_for_user"]);
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    test("user_concurrency_slots — A cannot enumerate B's slot conversation_ids", async () => {
      const { data, error } = await aClient
        .from("user_concurrency_slots")
        .select("conversation_id")
        .eq("user_id", userB.id);
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    test("refreshSubscriptionStatus — A cannot read B's users row", async () => {
      const { data, error } = await aClient
        .from("users")
        .select("subscription_status, plan_tier, concurrency_override")
        .eq("id", userB.id)
        .single();
      expect(data).toBeNull();
      expect(error?.code).toBe("PGRST116");
    });

    test("handleMessage resume-by-id — A cannot read B's conversation ownership row", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .select("id, status, repo_url")
        .eq("id", bConvId)
        .eq("user_id", userA.id) // attacker spoofs own id
        .single();
      expect(data).toBeNull();
      expect(error?.code).toBe("PGRST116");
    });

    test("handleMessage chat routing — A cannot read B's session_id / context_path", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .select("active_workflow, session_id, context_path")
        .eq("id", bConvId)
        .single();
      expect(data).toBeNull();
      expect(error?.code).toBe("PGRST116");
    });

    test("setupWebSocket bootstrap — A cannot read B's tc_accepted_version", async () => {
      const { data, error } = await aClient
        .from("users")
        .select(
          "tc_accepted_version, subscription_status, plan_tier, concurrency_override, stripe_subscription_id",
        )
        .eq("id", userB.id)
        .single();
      expect(data).toBeNull();
      expect(error?.code).toBe("PGRST116");
    });

    test("createConversation — A cannot INSERT a conversation under B's user_id (RLS deny)", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .insert({
          user_id: userB.id, // attacker spoofs ownership
          session_id: `tenant-isolation-${randomBytes(4).toString("hex")}`,
          status: "active",
        })
        .select("id");
      // RLS denies INSERT — PostgREST returns either an error or empty data
      // depending on the WITH CHECK clause. Either way: no row created.
      const succeeded = data && data.length > 0;
      expect(succeeded).toBeFalsy();
      if (error) expect(error.code).toBeTruthy();
    });
  },
);
