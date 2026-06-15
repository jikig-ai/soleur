/**
 * deleteAccount × denied_jti — pins migration 106 (Art-17 founder-erasure gap).
 *
 * Plan ref: knowledge-base/project/plans/2026-06-15-fix-authusers-delete-cascade-dev-drift-plan.md
 *
 * Background (#5372 fold-in): migration 037 defined
 *   denied_jti.founder_id ... REFERENCES public.users(id) ON DELETE RESTRICT
 * with NO anonymise/cascade step in account-delete.ts. So a founder who has any
 * revoked-JTI row could not erase their account — the auth.users → public.users
 * delete cascade was FK-blocked by RESTRICT. Migration 106 switches the FK to
 * ON DELETE CASCADE (the deny KEY is `jti`; founder_id is metadata, and the
 * entry is meaningless once the user is gone), closing the erasure gap.
 *
 * What this pins:
 *   1. A fresh synthetic user with a seeded denied_jti row can be fully
 *      deleted via deleteAccount returning {success: true}.
 *   2. Post-delete, the denied_jti row is gone (CASCADE fired) and the
 *      auth.users / public.users rows are gone.
 *
 * Revert migration 106 (FK back to RESTRICT) and assertion (1) flips red:
 * the cascade aborts at auth-delete with an FK violation → success=false.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/account-delete.denied-jti-cascade.integration.test.ts
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "node:crypto";

import { tearDownTenantUser } from "@/test/helpers/tenant-isolation-teardown";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

const SYNTHETIC_EMAIL_PATTERN = /^tenant-isolation-[a-f0-9]{16}@soleur\.test$/;

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
  if (!value)
    throw new Error(`[account-delete.denied-jti-cascade] ${name} is required`);
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "deleteAccount × denied_jti cascade (migration 106 Art-17 gate)",
  () => {
    let service: SupabaseClient;
    const user = { id: "", email: syntheticEmail() };
    let seededJti = "";

    beforeAll(async () => {
      const url = requireEnv("SUPABASE_URL");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

      service = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      assertSynthetic(user.email);
      const { data, error } = await service.auth.admin.createUser({
        email: user.email,
        password: randomBytes(16).toString("hex"),
        email_confirm: true,
      });
      expect(error, `createUser(${user.email}) failed`).toBeNull();
      user.id = data.user!.id;
      expect(user.id).toBeTruthy();

      // Seed one denied_jti row owned by this user. denied_jti has zero RLS
      // policies (service-role-only); the service client bypasses RLS.
      seededJti = randomUUID();
      const { error: insErr } = await service.from("denied_jti").insert({
        jti: seededJti,
        founder_id: user.id,
        reason: "account-delete-denied-jti-cascade-test",
      });
      expect(insErr, "seed denied_jti row").toBeNull();
    }, 30_000);

    afterAll(async () => {
      if (!service) return;
      // Best-effort cleanup if the cascade did not run (RED path on un-migrated
      // dev): remove the seeded row, then the user.
      try {
        await service.from("denied_jti").delete().eq("jti", seededJti);
      } catch {
        // best-effort
      }
      try {
        await tearDownTenantUser(service, user);
      } catch {
        // best-effort
      }
    }, 30_000);

    test("deleteAccount succeeds with a seeded denied_jti row (CASCADE clears it)", async () => {
      const { deleteAccount } = await import("@/server/account-delete");
      const result = await deleteAccount(user.id, user.email);
      expect(
        result.success,
        `deleteAccount failed with error: ${result.error}`,
      ).toBe(true);

      // The denied_jti row was removed by the ON DELETE CASCADE FK.
      const { data: denyRow, error: selErr } = await service
        .from("denied_jti")
        .select("jti")
        .eq("jti", seededJti)
        .maybeSingle();
      expect(selErr).toBeNull();
      expect(denyRow).toBeNull();

      // auth.users + public.users rows are gone.
      const { data: gone } = await service.auth.admin.getUserById(user.id);
      expect(gone?.user).toBeNull();
      const { data: pubUser } = await service
        .from("users")
        .select("id")
        .eq("id", user.id)
        .maybeSingle();
      expect(pubUser).toBeNull();
    }, 30_000);
  },
);
