/**
 * Tenant isolation — api-messages.ts (PR-C §2.2, #3244).
 *
 * Covers the 2 migrated tenant sites in `server/api-messages.ts`:
 *
 *   - `:55` SELECT conversations (ownership row hydration)
 *   - `:79` SELECT messages (FK-joined via conversations.user_id)
 *
 * The `:36` `supabase.auth.getUser(token)` site is PERMANENT (auth-domain
 * bootstrap, pre-tenant-JWT) — NOT covered here; the route's HTTP
 * 401 contract is exercised by route-level tests, not this RLS suite.
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
  "tenant isolation — api-messages.ts (2 sites)",
  () => {
    let service: SupabaseClient;
    let aClient: SupabaseClient;
    let bClient: SupabaseClient;

    const userA = { id: "", email: syntheticEmail() };
    const userB = { id: "", email: syntheticEmail() };

    let aConversationId = "";
    let bConversationId = "";
    let bMessageId = "";

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

      // Seed one conversation + one message per founder.
      for (const [user, ref] of [
        [userA, "a"] as const,
        [userB, "b"] as const,
      ]) {
        const { data: convRow, error: convError } = await service
          .from("conversations")
          .insert({
            user_id: user.id,
            session_id: `tenant-isolation-${randomBytes(4).toString("hex")}`,
          })
          .select("id")
          .single();
        expect(convError, `seed conversations for ${user.email}`).toBeNull();
        if (ref === "a") aConversationId = convRow!.id;
        else bConversationId = convRow!.id;

        const { data: msgRow, error: msgError } = await service
          .from("messages")
          .insert({
            conversation_id: convRow!.id,
            role: "user",
            content: `synthesized message for ${user.email}`,
          })
          .select("id")
          .single();
        expect(msgError, `seed messages for ${user.email}`).toBeNull();
        if (ref === "b") bMessageId = msgRow!.id;
      }

      _resetTenantCache();
      const aMint = await mintFounderJwt(userA.id);
      const bMint = await mintFounderJwt(userB.id);

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

    test("baseline: A reads own conversation row (mirrors `:55` site)", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .select("id")
        .eq("id", aConversationId)
        .eq("user_id", userA.id)
        .maybeSingle();
      expect(error).toBeNull();
      expect(data?.id).toBe(aConversationId);
    });

    test("`:55` conversations SELECT — A cannot read B's conversation by id", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .select(
          "id, total_cost_usd, input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens, workflow_ended_at, created_at",
        )
        .eq("id", bConversationId)
        .eq("user_id", userA.id);
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    test("`:79` messages SELECT — A cannot read B's messages by conversation_id (FK-RLS join)", async () => {
      const { data, error } = await aClient
        .from("messages")
        .select("id, content")
        .eq("conversation_id", bConversationId);
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    test("`:79` messages SELECT — A spoofing B's message_id is denied", async () => {
      const { data, error } = await aClient
        .from("messages")
        .select("id, content")
        .eq("id", bMessageId);
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    test("symmetric: B cannot read A's conversations or messages", async () => {
      const { data: convsByB } = await bClient
        .from("conversations")
        .select("id")
        .eq("id", aConversationId);
      const { data: msgsByB } = await bClient
        .from("messages")
        .select("id")
        .eq("conversation_id", aConversationId);
      expect(convsByB).toEqual([]);
      expect(msgsByB).toEqual([]);
    });
  },
);
