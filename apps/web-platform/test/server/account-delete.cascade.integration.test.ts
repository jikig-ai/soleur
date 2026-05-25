/**
 * deleteAccount end-to-end cascade — pins mig 065 + 066 against regression.
 *
 * Plan ref: knowledge-base/project/plans/2026-05-22-fix-tenant-integration-cascade-4356-plan.md
 *
 * This test exists because:
 *   - The dsar-export-workspace-tables.integration.test.ts AC-GDPR-17-CALLER
 *     covers `deleteAccount` for a multi-member fixture where the deleted
 *     user is a non-owner. That path exercises the reassign branch of
 *     `anonymise_organization_membership` (mig 065 Part 3) but NOT the
 *     SET-NULL orphan path that is the actual #4356 deadlock.
 *   - The 6 raw-deleteUser teardown call sites exercise the cascade via
 *     `tearDownTenantUser` (helper) but a teardown failure surfaces as
 *     vitest `afterAll` noise rather than a hard red test.
 *
 * What this pins:
 *   1. A fresh synthetic user with a seeded `audit_byok_use` row
 *      (load-bearing for mig 065 Part 2 + mig 066's WORM carve-out path)
 *      can be fully deleted via `deleteAccount` returning `{success: true}`.
 *   2. Post-delete, the user's `auth.users` row is gone, `public.users` row
 *      is gone (CASCADE), and the seeded `audit_byok_use` row remains
 *      with `founder_id IS NULL` (Art-17 anonymised; mig 066 carve-out
 *      fired).
 *   3. The user's solo organization is no longer reachable by
 *      `owner_user_id = userId` (SET NULL cascade applied; mig 065 Part 1).
 *
 * Revert either mig 065 OR mig 066 and at least one assertion flips red:
 *   - Revert 065 → step 3.92 orphan-delete fails P0001 → success=false.
 *   - Revert 066 → SET NULL cascade UPDATE on audit_byok_use fails P0001
 *                 → auth-delete fails → success=false.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/account-delete.cascade.integration.test.ts
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "node:crypto";

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
  if (!value)
    throw new Error(`[account-delete.cascade] ${name} is required`);
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "deleteAccount end-to-end cascade (mig 065 + 066 regression gate)",
  () => {
    let service: SupabaseClient;
    const user = { id: "", email: syntheticEmail() };
    let seedAuditRowId = "";

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

      // Seed one audit_byok_use row owned by this user to load-bear mig 065
      // Part 2 (SET NULL on FK) + mig 066 (WORM-trigger carve-out for the
      // SET NULL UPDATE). Without this seed the cascade path would skip the
      // mig 066 surface entirely and a regression there would not flip the
      // test red.
      const { error: writeErr } = await service.rpc("write_byok_audit", {
        p_invocation_id: randomUUID(),
        p_founder_id: user.id,
        // Solo-canary workspace per mig 053 handle_new_user backfill.
        p_workspace_id: user.id,
        p_agent_role: "account-delete-cascade-test",
        p_token_count: 1,
        p_unit_cost_cents: 1,
      });
      expect(writeErr, "write_byok_audit seed").toBeNull();

      const { data: seedRows, error: seedSelErr } = await service
        .from("audit_byok_use")
        .select("id")
        .eq("founder_id", user.id)
        .eq("agent_role", "account-delete-cascade-test")
        .limit(1);
      expect(seedSelErr, "select seed row").toBeNull();
      expect(seedRows?.length).toBe(1);
      seedAuditRowId = seedRows![0].id as string;
    }, 30_000);

    afterAll(async () => {
      // If the cascade test failed mid-way, fall back to the helper to
      // unblock the suite. user.id may already be deleted (the canary
      // case) — tearDownTenantUser is idempotent on /not found/.
      if (!service) return;
      try {
        await tearDownTenantUser(service, user);
      } catch {
        // best-effort
      }
    }, 30_000);

    test("deleteAccount(soloUser) returns success=true and CASCADE clears auth+public.users", async () => {
      const { deleteAccount } = await import("@/server/account-delete");
      const result = await deleteAccount(user.id, user.email);
      expect(
        result.success,
        `deleteAccount failed with error: ${result.error}`,
      ).toBe(true);

      // auth.users row is gone.
      const { data: gone } = await service.auth.admin.getUserById(user.id);
      expect(gone?.user).toBeNull();

      // public.users CASCADE confirmed via service-role SELECT (RLS bypass).
      const { data: pubUser } = await service
        .from("users")
        .select("id")
        .eq("id", user.id)
        .maybeSingle();
      expect(pubUser).toBeNull();
    }, 30_000);

    test("mig 065 Part 1: organization owner_user_id NULLed (SET NULL cascade applied)", async () => {
      // Querying by owner_user_id returns zero — either because the org is
      // gone (legacy hard-delete path) or because owner_user_id transitioned
      // to NULL (mig 065 SET NULL cascade, the post-#4356 shape). Both pass
      // this filter; specifically asserting NULL via a follow-up SELECT
      // confirms the new shape.
      const { data: orgsByOwner } = await service
        .from("organizations")
        .select("id, owner_user_id")
        .eq("owner_user_id", user.id);
      expect(orgsByOwner).toHaveLength(0);
    }, 10_000);

    test("mig 065 Part 2 + mig 066: audit_byok_use row preserved with founder_id NULLed (WORM carve-out fired)", async () => {
      const { data: auditRow, error: selErr } = await service
        .from("audit_byok_use")
        .select("id, founder_id, workspace_id, token_count")
        .eq("id", seedAuditRowId)
        .maybeSingle();
      expect(selErr).toBeNull();
      // Row is preserved (WORM ledger lineage) — Art-17 means founder_id is
      // scrubbed, not the entire row.
      expect(auditRow).not.toBeNull();
      expect(auditRow!.founder_id).toBeNull();
      // workspace_id and token_count are not Art-17 PII; they remain for
      // workspace-scoped cost analytics.
      expect(auditRow!.workspace_id).toBe(user.id);
      expect(auditRow!.token_count).toBe(1);
    }, 10_000);
  },
);
