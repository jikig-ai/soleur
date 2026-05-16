/**
 * Tenant isolation — current-repo-url.ts (PR-C §2.6, #3244).
 *
 * Covers the single migrated site at `:26` — SELECT users.repo_url
 * scoped to the caller's own id. RLS on `users`: `auth.uid() = id`.
 *
 * Asserts: A's tenant JWT cannot read B's `users.repo_url`. A spoofed
 * `.eq("id", userB.id)` MUST return null (maybeSingle on 0 rows).
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
  "tenant isolation — current-repo-url.ts (1 site)",
  () => {
    let service: SupabaseClient;
    let aClient: SupabaseClient;

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
        const { data } = await service.auth.admin.createUser({
          email: user.email,
          password: randomBytes(16).toString("hex"),
          email_confirm: true,
        });
        if (data.user?.id) user.id = data.user.id;
        expect(user.id).toBeTruthy();
      }

      for (const user of [userA, userB]) {
        const { error } = await service
          .from("users")
          .update({ repo_url: `https://github.com/test/${user.id.slice(0, 8)}.git` })
          .eq("id", user.id);
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

    test("baseline: A reads own repo_url", async () => {
      const { data, error } = await aClient
        .from("users")
        .select("repo_url")
        .eq("id", userA.id)
        .maybeSingle();
      expect(error).toBeNull();
      expect(data?.repo_url).toContain("github.com/test/");
    });

    test("`:26` — A's tenant JWT cannot read B's repo_url", async () => {
      const { data, error } = await aClient
        .from("users")
        .select("repo_url")
        .eq("id", userB.id)
        .maybeSingle();
      expect(error).toBeNull();
      expect(data).toBeNull();
    });
  },
);
