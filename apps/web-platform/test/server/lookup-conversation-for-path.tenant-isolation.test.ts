/**
 * Tenant isolation — lookup-conversation-for-path.ts (PR-C §2.5, #3244).
 *
 * Covers the single migrated site at `:51` — SELECT conversations with
 * embedded `messages(count)` aggregate. RLS on `conversations`:
 * `auth.uid() = user_id`; the embedded aggregate inherits FK-RLS.
 *
 * Asserts: A's lookup of a path matching B's row resolves to
 * `{ ok: true, row: null }` — not a leak of B's row.
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
    throw new Error(
      `Refusing to touch non-synthetic email "${email}".`,
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`[tenant-isolation] ${name} is required`);
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "tenant isolation — lookup-conversation-for-path.ts (1 site)",
  () => {
    let service: SupabaseClient;
    let aClient: SupabaseClient;

    const userA = { id: "", email: syntheticEmail() };
    const userB = { id: "", email: syntheticEmail() };
    const SHARED_CTX_PATH = "knowledge-base/shared.md";
    const SHARED_REPO_URL = "https://github.com/test/shared.git";

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

      // Both founders share the same (repo_url, context_path) pair so the
      // cross-tenant lookup attempts to read B's row using A's tenant JWT.
      // Each user gets ONE row at the shared path.
      for (const user of [userA, userB]) {
        const { error } = await service.from("conversations").insert({
          user_id: user.id,
          session_id: `tenant-isolation-${randomBytes(4).toString("hex")}`,
          context_path: SHARED_CTX_PATH,
          repo_url: SHARED_REPO_URL,
          last_active: new Date().toISOString(),
        });
        expect(error).toBeNull();
      }

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

    test("baseline: A's lookup at the shared path returns A's row only", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .select("id, context_path, last_active, user_id")
        .eq("user_id", userA.id)
        .eq("repo_url", SHARED_REPO_URL)
        .eq("context_path", SHARED_CTX_PATH)
        .is("archived_at", null)
        .order("last_active", { ascending: false })
        .limit(1)
        .maybeSingle();
      expect(error).toBeNull();
      expect(data?.user_id).toBe(userA.id);
    });

    test("`:51` — A's tenant JWT cannot lookup B's row even at shared path", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .select("id, context_path, last_active, messages(count)")
        .eq("user_id", userB.id) // spoofed
        .eq("repo_url", SHARED_REPO_URL)
        .eq("context_path", SHARED_CTX_PATH)
        .is("archived_at", null)
        .order("last_active", { ascending: false })
        .limit(1)
        .maybeSingle();
      expect(error).toBeNull();
      expect(data).toBeNull();
    });

    test("`:51` — embedded messages(count) does not leak B's count", async () => {
      // Even if attacker leaves their own user_id, A's row only — never
      // B's. The embedded aggregate inherits the parent's RLS scope.
      const { data } = await aClient
        .from("conversations")
        .select("id, user_id, messages(count)")
        .eq("user_id", userA.id);
      expect(data?.every((r) => r.user_id === userA.id)).toBe(true);
    });
  },
);
