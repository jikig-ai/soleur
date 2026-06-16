/**
 * deleteAccount × routine_runs — pins migration 107 Art-17 erasure (#5372 / #5345).
 *
 * Background: 107_routine_runs.sql defines a WORM run-log with FKs
 * actor_id / delegating_principal → users(id) ON DELETE RESTRICT. Without an
 * anonymise step, a user who ever triggered a routine run would be un-erasable
 * (the auth.users → public.users cascade is FK-blocked by RESTRICT; and the
 * original SET NULL + statement-level WORM trigger aborted the cascade as a
 * GoTrue 500 — the #5372 incident). The fix: account-delete.ts step 5.14 calls
 * anonymise_routine_runs() (worm-bypassing) BEFORE auth-delete, NULLing the
 * actor columns while preserving the append-only row.
 *
 * What this pins:
 *   1. A user with a seeded routine_runs row (actor_id = them) can be fully
 *      deleted via deleteAccount returning {success: true}.
 *   2. Post-delete, the routine_runs row is PRESERVED (WORM) with actor_id and
 *      delegating_principal NULLed (Art-17 scrub, not row-delete), and the
 *      auth.users / public.users rows are gone.
 *
 * Revert the fix (FK back to SET NULL, or drop the anonymise step) and
 * assertion (1) flips red: the cascade aborts at auth-delete.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/account-delete.routine-runs-cascade.integration.test.ts
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
    throw new Error(`[account-delete.routine-runs-cascade] ${name} is required`);
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "deleteAccount × routine_runs cascade (migration 107 Art-17 gate)",
  () => {
    let service: SupabaseClient;
    const user = { id: "", email: syntheticEmail() };
    let seededRunId = "";

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

      // Seed one routine_runs row attributed to this user via the append-only
      // write RPC (service-role only). actor_id = the user → the row references
      // them and exercises the RESTRICT FK + anonymise path.
      seededRunId = randomUUID();
      const startedAt = new Date(Date.now() - 5000).toISOString();
      const endedAt = new Date().toISOString();
      const { error: wErr } = await service.rpc("write_routine_run", {
        p_routine_id: "account-delete-routine-runs-cascade-test",
        p_run_id: seededRunId,
        p_status: "completed",
        p_trigger_source: "manual",
        p_actor_class: "human",
        p_actor_id: user.id,
        p_delegating_principal: user.id,
        p_started_at: startedAt,
        p_ended_at: endedAt,
        p_duration_ms: 5000,
        p_error_summary: null,
      });
      expect(wErr, "write_routine_run seed").toBeNull();
    }, 30_000);

    afterAll(async () => {
      if (!service) return;
      // Best-effort cleanup on the RED path (deletion failed → user + row left).
      // The row is WORM; anonymise it via the RPC so teardown's user delete is
      // not FK-blocked, then tear the user down.
      try {
        await service.rpc("anonymise_routine_runs", { p_user_id: user.id });
      } catch {
        // best-effort
      }
      try {
        await tearDownTenantUser(service, user);
      } catch {
        // best-effort
      }
    }, 30_000);

    test("deleteAccount succeeds with a routine_runs row (anonymised, row preserved)", async () => {
      // Positive control: the seeded row exists and references the user BEFORE delete.
      const { data: preRow, error: preErr } = await service
        .from("routine_runs")
        .select("id, actor_id, delegating_principal")
        .eq("run_id", seededRunId)
        .maybeSingle();
      expect(preErr, "pre-delete read of seeded routine_runs row").toBeNull();
      expect(preRow, "seeded routine_runs row must exist before deleteAccount").not.toBeNull();
      expect(preRow!.actor_id).toBe(user.id);

      const { deleteAccount } = await import("@/server/account-delete");
      const result = await deleteAccount(user.id, user.email);
      expect(
        result.success,
        `deleteAccount failed with error: ${result.error}`,
      ).toBe(true);

      // The run-log row is PRESERVED (WORM) with the subject's PII NULLed.
      const { data: postRow, error: postErr } = await service
        .from("routine_runs")
        .select("id, actor_id, delegating_principal")
        .eq("run_id", seededRunId)
        .maybeSingle();
      expect(postErr).toBeNull();
      expect(postRow, "routine_runs row must be preserved (WORM)").not.toBeNull();
      expect(postRow!.actor_id).toBeNull();
      expect(postRow!.delegating_principal).toBeNull();

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
