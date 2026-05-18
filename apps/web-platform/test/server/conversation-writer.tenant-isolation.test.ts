/**
 * Tenant isolation — conversation-writer.ts (PR-C §2.4, #3244).
 *
 * Covers the single migrated site at `conversation-writer.ts:157`:
 *
 *   - UPDATE conversations (composite-key targeted write)
 *
 * RLS on `conversations`: `auth.uid() = user_id`. The wrapper layers
 * an explicit `.eq("id", convId).eq("user_id", userId)` composite-key
 * filter on top. The cross-tenant deny test below validates that even
 * if a caller supplied a foreign convId, RLS would still 0-row the
 * UPDATE.
 *
 * This is the load-bearing surface for issue #3244's UPDATE-side
 * isolation invariant (per `user-impact-reviewer` FINDING 3): a future
 * maintainer adding `WITH CHECK (true)` to the `conversations` policy
 * "to be explicit" would silently defeat write-side isolation. The
 * test documents the invariant by asserting cross-founder UPDATE
 * affects zero rows under tenant JWT.
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
  "tenant isolation — conversation-writer.ts (1 UPDATE site)",
  () => {
    let service: SupabaseClient;
    let aClient: SupabaseClient;
    let bClient: SupabaseClient;

    const userA = { id: "", email: syntheticEmail() };
    const userB = { id: "", email: syntheticEmail() };

    let aConversationId = "";
    let bConversationId = "";

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

      for (const [user, ref] of [
        [userA, "a"] as const,
        [userB, "b"] as const,
      ]) {
        const { data: convRow, error: convError } = await service
          .from("conversations")
          .insert({
            user_id: user.id,
            session_id: `tenant-isolation-${randomBytes(4).toString("hex")}`,
            status: "active",
          })
          .select("id")
          .single();
        expect(convError, `seed conversations for ${user.email}`).toBeNull();
        if (ref === "a") aConversationId = convRow!.id;
        else bConversationId = convRow!.id;
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

    test("baseline: A can UPDATE own conversation (composite key match)", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .update({ status: "completed" })
        .eq("id", aConversationId)
        .eq("user_id", userA.id)
        .select("id");
      expect(error).toBeNull();
      expect(data?.length).toBe(1);
    });

    test("`:157` UPDATE — A cannot UPDATE B's conversation by id (RLS deny via USING)", async () => {
      // Even if A supplies the correct user_id (B's), RLS denies the
      // write because `auth.uid()` is A, not B. RLS-filtered UPDATE
      // returns [] (zero rows affected).
      const { data, error } = await aClient
        .from("conversations")
        .update({ status: "failed" })
        .eq("id", bConversationId)
        .eq("user_id", userB.id)
        .select("id");
      expect(error).toBeNull();
      expect(data).toEqual([]);

      // Verify B's conversation status is unchanged.
      const { data: stillThere } = await service
        .from("conversations")
        .select("id, status")
        .eq("id", bConversationId)
        .maybeSingle();
      expect(stillThere?.id).toBe(bConversationId);
      expect(stillThere?.status).not.toBe("failed");
    });

    test("`:157` UPDATE — A spoofing own user_id but B's convId is denied", async () => {
      // Even if the attacker forgets to update user_id and leaves their
      // own (matching auth.uid()), the wrapper's composite-key filter
      // (.eq("user_id", userId)) won't match B's row. Combined with
      // RLS, this is belt-and-suspenders.
      const { data, error } = await aClient
        .from("conversations")
        .update({ status: "failed" })
        .eq("id", bConversationId)
        .eq("user_id", userA.id) // attacker's own id
        .select("id");
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    test("symmetric: B cannot UPDATE A's conversation either", async () => {
      const { data } = await bClient
        .from("conversations")
        .update({ status: "failed" })
        .eq("id", aConversationId)
        .eq("user_id", userA.id)
        .select("id");
      expect(data).toEqual([]);
    });
  },
);
