/**
 * Tenant isolation — cc-dispatcher.ts (PR-C §2.11, #3244).
 *
 * Covers the migrated tenant sites:
 *
 *   - `:878-879` BYOK fetch via `runWithByokLease` + `lease.getApiKey()`.
 *     `api_keys` SELECT under tenant JWT — cross-tenant must return 0
 *     rows (RLS deny on `auth.uid() = user_id`).
 *   - Migrated `:1367` (user message INSERT) — tenant-scoped.
 *   - Migrated `:1464` (assistant message INSERT) — tenant-scoped.
 *
 * `:1395` attachments injection (`supabase: supabase()`) stays
 * service-role — NOT covered here. It's PR-D scope (attachments-storage
 * RLS audit).
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1.
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "node:crypto";

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
    throw new Error(`Refusing to touch non-synthetic email "${email}".`);
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`[tenant-isolation] ${name} is required`);
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "tenant isolation — cc-dispatcher.ts (BYOK + 2 message inserts)",
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

      // Seed B with an api_key + a conversation A might try to write into.
      await service.from("api_keys").insert({
        user_id: userB.id,
        provider: "anthropic",
        encrypted_key: Buffer.from(`fake-${userB.id}`).toString("base64"),
        iv: Buffer.from("000000000000").toString("base64"),
        auth_tag: Buffer.from("0000000000000000").toString("base64"),
        is_valid: true,
        key_version: 2,
      });
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
      // Cap suite mint count to 1 — see test/helpers/mint-once.ts.
      registerSharedMintCache([[userA.id, aMint]]);
    }, 30_000);

    afterAll(async () => {
      if (!service) return;
      for (const user of [userA, userB]) {
        if (!user.id) continue;
        assertSynthetic(user.email);
        await service.auth.admin.deleteUser(user.id).catch(() => {});
      }
    }, 30_000);

    test("BYOK fetch — A's tenant JWT cannot read B's api_keys row (PR-C §2.11)", async () => {
      // `runWithByokLease` → `fetchAndDecryptIntoSlot` runs this SELECT
      // shape. RLS on `api_keys` enforces `auth.uid() = user_id`.
      const { data, error } = await aClient
        .from("api_keys")
        .select("id, encrypted_key, iv, auth_tag, key_version")
        .eq("user_id", userB.id)
        .eq("is_valid", true)
        .eq("provider", "anthropic")
        .limit(1)
        .maybeSingle();
      expect(error).toBeNull();
      expect(data).toBeNull();
    });

    test("user-message INSERT — A's JWT cannot INSERT into B's conversation_id (FK-RLS deny)", async () => {
      // `messages` RLS FK-joins through `conversations.user_id`. A's
      // tenant JWT INSERTing with B's conversation_id violates the FK
      // policy.
      const { data, error } = await aClient
        .from("messages")
        .insert({
          id: randomUUID(),
          conversation_id: bConvId,
          role: "user",
          content: "spoofed by A",
          tool_calls: null,
          leader_id: null,
        })
        .select("id");
      // RLS denies the INSERT; PostgREST returns error code 42501 or
      // similar. Either way, the row is NOT persisted.
      const succeeded = data && data.length > 0;
      expect(succeeded).toBeFalsy();
      if (error) expect(error.code).toBeTruthy();

      // Verify B's conversation has no spoofed message.
      const { data: msgs } = await service
        .from("messages")
        .select("content")
        .eq("conversation_id", bConvId);
      const spoofed = (msgs ?? []).some(
        (m: { content: string }) => m.content === "spoofed by A",
      );
      expect(spoofed).toBe(false);
    });

    test("assistant-message INSERT — same FK-RLS deny on saveAssistantMessage shape", async () => {
      const { data } = await aClient
        .from("messages")
        .insert({
          id: randomUUID(),
          conversation_id: bConvId,
          role: "assistant",
          content: "fake assistant text",
          tool_calls: null,
          leader_id: "cc_router",
        })
        .select("id");
      const succeeded = data && data.length > 0;
      expect(succeeded).toBeFalsy();
    });
  },
);
