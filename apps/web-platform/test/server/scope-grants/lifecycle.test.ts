/**
 * scope_grants lifecycle + WORM enforcement — DB-layer integration test (PR-G #3947).
 *
 * Pins the append-only invariant for `public.scope_grants`:
 *   1. grant_action_class inserts a fresh active row.
 *   2. Re-grant at a different tier revokes the previous row with
 *      revoked_reason = 'tier_change' and inserts a new active row.
 *   3. revoke_action_class flips revoked_at (no DELETE).
 *   4. Re-grant after revoke inserts a fresh active row (no resurrection).
 *   5. The WORM trigger raises P0001 on UPDATE of non-revoke columns even
 *      under service-role (RLS bypass does NOT bypass the trigger).
 *   6. The WORM trigger raises P0001 on DELETE under service-role.
 *   7. anonymise_scope_grants bypasses the trigger via the GUC gate and
 *      zeros founder_id for every row owned by p_user_id.
 *
 * Plan: knowledge-base/project/plans/2026-05-18-feat-pr-g-cohort-onboarding-plan.md (TR4).
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Requires `doppler run -p soleur -c dev`.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/scope-grants/lifecycle.test.ts
 *
 * Synthesized fixtures only (cq-test-fixtures-synthesized-only).
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { randomBytes } from "node:crypto";

import { mintFounderJwt } from "@/lib/supabase/tenant";

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
  if (!value) throw new Error(`[scope-grants/lifecycle] ${name} is required`);
  return value;
}

const ACTION_CLASS = "finance.payment_failed";

describe.skipIf(!INTEGRATION_ENABLED)(
  "scope_grants lifecycle + WORM enforcement (integration)",
  () => {
    let service: SupabaseClient;
    let tenant: SupabaseClient;
    const userA = { id: "", email: syntheticEmail() };

    beforeAll(async () => {
      const url = requireEnv("SUPABASE_URL");
      const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      requireEnv("SUPABASE_JWT_SECRET");

      service = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      assertSynthetic(userA.email);
      const { data, error } = await service.auth.admin.createUser({
        email: userA.email,
        password: randomBytes(16).toString("hex"),
        email_confirm: true,
      });
      expect(error, `createUser(${userA.email}) failed`).toBeNull();
      if (data.user?.id) userA.id = data.user.id;
      expect(userA.id).toBeTruthy();

      // Tenant-scoped client carrying userA's founder JWT — exercises the
      // founder-callable RPCs (grant_action_class, revoke_action_class)
      // through the production mint path so auth.uid() resolves to userA.id.
      const { jwt } = await mintFounderJwt(userA.id, { ttlSec: 600 });
      tenant = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
    });

    afterAll(async () => {
      // anonymise_scope_grants (step 7) zeros founder_id for every row
      // owned by userA. The `users.id` FK is ON DELETE RESTRICT, but with
      // founder_id = NULL there are no dependent rows blocking the
      // auth.admin.deleteUser cascade — so the synthetic auth user can be
      // reaped cleanly. If step 7 didn't run (e.g. earlier failure), the
      // delete may fail; we tolerate that here so the failure surface is
      // the original assertion, not the teardown.
      if (userA.id) {
        assertSynthetic(userA.email);
        await service.auth.admin.deleteUser(userA.id);
      }
    });

    test("lifecycle: grant → tier change → revoke → re-grant", async () => {
      // ── 1. Grant fresh ────────────────────────────────────────────────
      const { error: g1Err } = await tenant.rpc("grant_action_class", {
        p_action_class: ACTION_CLASS,
        p_tier: "draft_one_click",
      });
      expect(g1Err, "grant_action_class #1").toBeNull();

      let { data: rows, error: sel1Err } = await service
        .from("scope_grants")
        .select("id, tier, revoked_at, revoked_reason, granted_at")
        .eq("founder_id", userA.id)
        .eq("action_class", ACTION_CLASS)
        .order("granted_at", { ascending: true });
      expect(sel1Err).toBeNull();
      expect(rows?.length).toBe(1);
      expect(rows![0].revoked_at).toBeNull();
      expect(rows![0].tier).toBe("draft_one_click");

      // ── 2. Re-grant at a different tier (tier_change auto-revoke) ─────
      const { error: g2Err } = await tenant.rpc("grant_action_class", {
        p_action_class: ACTION_CLASS,
        p_tier: "approve_every_time",
      });
      expect(g2Err, "grant_action_class #2 (tier change)").toBeNull();

      ({ data: rows, error: sel1Err } = await service
        .from("scope_grants")
        .select("id, tier, revoked_at, revoked_reason, granted_at")
        .eq("founder_id", userA.id)
        .eq("action_class", ACTION_CLASS)
        .order("granted_at", { ascending: true }));
      expect(sel1Err).toBeNull();
      expect(rows?.length).toBe(2);

      const prev = rows![0];
      const curr = rows![1];
      expect(prev.revoked_at).not.toBeNull();
      expect(prev.revoked_reason).toBe("tier_change");
      expect(curr.revoked_at).toBeNull();
      expect(curr.tier).toBe("approve_every_time");

      // ── 3. Revoke (user_revoke) ───────────────────────────────────────
      const { error: revErr } = await tenant.rpc("revoke_action_class", {
        p_action_class: ACTION_CLASS,
        p_reason: "user_revoke",
      });
      expect(revErr, "revoke_action_class").toBeNull();

      ({ data: rows, error: sel1Err } = await service
        .from("scope_grants")
        .select("id, tier, revoked_at, revoked_reason, granted_at")
        .eq("founder_id", userA.id)
        .eq("action_class", ACTION_CLASS)
        .order("granted_at", { ascending: true }));
      expect(sel1Err).toBeNull();
      expect(rows?.length).toBe(2); // No DELETE — count unchanged.

      const justRevoked = rows![1]; // the previously-active row
      expect(justRevoked.revoked_at).not.toBeNull();
      expect(justRevoked.revoked_reason).toBe("user_revoke");

      const { data: activeRows, error: activeErr } = await service
        .from("scope_grants")
        .select("id")
        .eq("founder_id", userA.id)
        .eq("action_class", ACTION_CLASS)
        .is("revoked_at", null);
      expect(activeErr).toBeNull();
      expect(activeRows?.length).toBe(0);

      // ── 4. Re-grant after revoke ──────────────────────────────────────
      const { error: g3Err } = await tenant.rpc("grant_action_class", {
        p_action_class: ACTION_CLASS,
        p_tier: "draft_one_click",
      });
      expect(g3Err, "grant_action_class #3 (re-grant after revoke)").toBeNull();

      ({ data: rows, error: sel1Err } = await service
        .from("scope_grants")
        .select("id, tier, revoked_at, revoked_reason, granted_at")
        .eq("founder_id", userA.id)
        .eq("action_class", ACTION_CLASS)
        .order("granted_at", { ascending: true }));
      expect(sel1Err).toBeNull();
      expect(rows?.length).toBe(3);

      const newest = rows![2];
      expect(newest.revoked_at).toBeNull();
      expect(newest.tier).toBe("draft_one_click");
    });

    test("WORM: UPDATE on non-revoke column raises P0001 (service-role)", async () => {
      // Grab the current active row for userA / ACTION_CLASS — created by
      // the lifecycle test above. Service-role SELECT bypasses RLS.
      const { data: rows, error: selErr } = await service
        .from("scope_grants")
        .select("id")
        .eq("founder_id", userA.id)
        .eq("action_class", ACTION_CLASS)
        .is("revoked_at", null)
        .limit(1);
      expect(selErr).toBeNull();
      expect(rows?.length).toBe(1);
      const activeId = rows![0].id;

      // Attempt to mutate `tier` directly. Service-role bypasses RLS but
      // NOT the WORM trigger — the trigger is the load-bearing primitive.
      const { error } = await service
        .from("scope_grants")
        .update({ tier: "auto" })
        .eq("id", activeId);
      expect(error).not.toBeNull();
      expect(error!.code).toBe("P0001");
      expect(error!.message).toMatch(/append-only/);
    });

    test("WORM: DELETE raises P0001 (service-role)", async () => {
      const { data: rows, error: selErr } = await service
        .from("scope_grants")
        .select("id")
        .eq("founder_id", userA.id)
        .eq("action_class", ACTION_CLASS)
        .limit(1);
      expect(selErr).toBeNull();
      expect(rows?.length).toBe(1);
      const someId = rows![0].id;

      const { error } = await service
        .from("scope_grants")
        .delete()
        .eq("id", someId);
      expect(error).not.toBeNull();
      expect(error!.code).toBe("P0001");
      expect(error!.message).toMatch(/append-only|anonymise_scope_grants/);
    });

    test("anonymise_scope_grants bypasses WORM trigger and zeros founder_id", async () => {
      // Snapshot the row count BEFORE anonymise so we can assert the RPC
      // returned a row count > 0 AND that every row owned by userA was
      // zeroed.
      const { data: before, error: beforeErr } = await service
        .from("scope_grants")
        .select("id")
        .eq("founder_id", userA.id);
      expect(beforeErr).toBeNull();
      const beforeCount = before?.length ?? 0;
      expect(beforeCount).toBeGreaterThan(0);

      const { data: anonRows, error: anonErr } = await service.rpc(
        "anonymise_scope_grants",
        { p_user_id: userA.id },
      );
      expect(anonErr, "anonymise_scope_grants RPC").toBeNull();
      // anonymise_scope_grants returns int (row count).
      expect(typeof anonRows).toBe("number");
      expect(anonRows as unknown as number).toBeGreaterThan(0);

      // Post-condition: zero rows remain attributable to userA.
      const { data: after, error: afterErr } = await service
        .from("scope_grants")
        .select("id")
        .eq("founder_id", userA.id);
      expect(afterErr).toBeNull();
      expect(after?.length ?? 0).toBe(0);
    });
  },
);
