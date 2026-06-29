/**
 * Tenant isolation — `users` `auth.uid() = id` RLS deny (PR-C §2.6, #3244).
 *
 * Originally guarded `users.repo_url`, but ADR-044 PR-2b (mig 112,
 * `112_drop_legacy_users_repo_columns.sql`) dropped `users.repo_url`
 * (repo state moved to the `workspaces` table). The regression property
 * this suite protects is the `users` table's row-level `auth.uid() = id`
 * policy itself — that one founder's tenant JWT cannot read another
 * founder's `users` row. We assert it against a surviving `users` column
 * (`email`); the column choice is incidental, the RLS deny is the point.
 *
 * Asserts: A's tenant JWT cannot read B's `users` row. A spoofed
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

      // No seed needed: `users.repo_url` was dropped by mig 112 (ADR-044
      // PR-2b). `email` is set by createUser above and survives, so the
      // `auth.uid() = id` deny can be probed against it without a seed.

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

    test("baseline: A reads own users row", async () => {
      const { data, error } = await aClient
        .from("users")
        .select("email")
        .eq("id", userA.id)
        .maybeSingle();
      expect(error).toBeNull();
      expect(data?.email).toBe(userA.email);
    });

    test("`users` RLS — A's tenant JWT cannot read B's users row", async () => {
      const { data, error } = await aClient
        .from("users")
        .select("email")
        .eq("id", userB.id)
        .maybeSingle();
      expect(error).toBeNull();
      expect(data).toBeNull();
    });
  },
);
