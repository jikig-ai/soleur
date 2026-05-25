/**
 * action_sends WORM + Art-17 cascade + DB CHECK enum-absence — DB-layer
 * integration test (PR-H #4077).
 *
 * Covers 9 invariants per plan Phase 2.1:
 *   (a) INSERT happy → 201
 *   (b) UPDATE → P0001 (pure-reject trigger, mig 037 pattern)
 *   (c) DELETE → P0001
 *   (d) INSERT with NULL template_hash → 23502
 *   (e) scope_grants.tier = 'auto_with_digest' → INSERT accepted
 *   (f) scope_grants.tier = 'garbage' → 23514
 *   (g) action_sends.action_class = 'payment.refund' → 23514
 *       (DB CHECK enum-absence regex; defense-in-depth per Arch F3)
 *   (h) anonymise_action_sends(uuid) → action_sends.user_id IS NULL +
 *       recipient_id_hash '__anonymised__' (Art-17 erasure; cascade
 *       integration covered by account-delete-scope-grants-cascade.test.ts)
 *   (i) Cross-tenant SELECT → 0 rows (RLS owner-select)
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Requires `doppler run -p soleur -c dev`.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/action-sends-worm.test.ts
 *
 * Synthesized fixtures only (cq-test-fixtures-synthesized-only).
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { createHash, randomBytes, randomUUID } from "node:crypto";

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
  if (!value) throw new Error(`[action-sends-worm] ${name} is required`);
  return value;
}

const ACTION_CLASS = "finance.payment_failed";
const FORBIDDEN_CLASS = "payment.refund"; // DB CHECK regex must reject

function sha256(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

interface SeededMessage {
  id: string;
}

async function seedDraftMessage(
  service: SupabaseClient,
  userId: string,
  actionClass: string,
): Promise<SeededMessage> {
  // PR-F (#3244) — messages with external_* tier require status IN (draft,
  // archived) per messages_external_tier_status_check. Use external_low_stakes
  // so the FK from action_sends.message_id has a valid row to point at.
  // messages.conversation_id is NOT NULL — seed a parent conversation first.
  const { data: conv, error: convErr } = await service
    .from("conversations")
    // mig 059 made conversations.workspace_id NOT NULL; solo-canary
    // convention (workspace_id = user_id) per mig 059 backfill predicate.
    .insert({ user_id: userId, workspace_id: userId })
    .select("id")
    .single();
  if (convErr) {
    throw new Error(`seedDraftMessage failed (conversation): ${convErr.message}`);
  }

  const { data, error } = await service
    .from("messages")
    .insert({
      role: "assistant",
      content: "synthetic draft for action_sends WORM test",
      user_id: userId,
      // mig 059 made messages.workspace_id NOT NULL; same solo-canary.
      workspace_id: userId,
      conversation_id: conv!.id,
      tier: "external_low_stakes",
      source: "test",
      owning_domain: "finance",
      draft_preview: "test draft preview",
      status: "draft",
      action_class: actionClass,
      // PR-I (#4078, migration 053_template_authorizations.sql) added
      // template_id NOT NULL with CHECK (template_id ~ '^[a-z][a-z0-9_]*$').
      // Match the migration's backfill value so the FK shape stays stable.
      template_id: "default_legacy",
    })
    .select("id")
    .single();
  if (error) throw new Error(`seedDraftMessage failed: ${error.message}`);
  return { id: data!.id as string };
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "action_sends WORM + Art-17 cascade + enum-absence (integration)",
  () => {
    let service: SupabaseClient;
    let tenantA: SupabaseClient;
    let tenantB: SupabaseClient;
    const userA = { id: "", email: syntheticEmail() };
    const userB = { id: "", email: syntheticEmail() };
    let userA_grantId = "";

    beforeAll(async () => {
      const url = requireEnv("SUPABASE_URL");
      const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      requireEnv("SUPABASE_JWT_SECRET");

      service = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      for (const u of [userA, userB]) {
        assertSynthetic(u.email);
        const { data, error } = await service.auth.admin.createUser({
          email: u.email,
          password: randomBytes(16).toString("hex"),
          email_confirm: true,
        });
        expect(error, `createUser(${u.email})`).toBeNull();
        if (data.user?.id) u.id = data.user.id;
        expect(u.id).toBeTruthy();
      }

      const { jwt: jwtA } = await mintFounderJwt(userA.id, { ttlSec: 600 });
      const { jwt: jwtB } = await mintFounderJwt(userB.id, { ttlSec: 600 });
      tenantA = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${jwtA}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      tenantB = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${jwtB}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });

      // Grant userA the finance.payment_failed class so action_sends rows
      // can FK back to a valid scope_grants row.
      const { error: grantErr } = await tenantA.rpc("grant_action_class", {
        p_action_class: ACTION_CLASS,
        p_tier: "draft_one_click",
      });
      expect(grantErr, "grant_action_class(userA)").toBeNull();

      const { data: grantRows, error: grantSelErr } = await service
        .from("scope_grants")
        .select("id")
        .eq("founder_id", userA.id)
        .eq("action_class", ACTION_CLASS)
        .is("revoked_at", null)
        .limit(1);
      expect(grantSelErr).toBeNull();
      expect(grantRows?.length).toBe(1);
      userA_grantId = grantRows![0].id as string;
    });

    afterAll(async () => {
      // anonymise + delete users. Anonymise runs even if individual tests
      // failed — keeps the test DB cleanish.
      for (const u of [userA, userB]) {
        if (!u.id) continue;
        assertSynthetic(u.email);
        try {
          await service.rpc("anonymise_action_sends", { p_user_id: u.id });
        } catch {
          /* tolerate teardown failures */
        }
        try {
          await service.rpc("anonymise_scope_grants", { p_user_id: u.id });
        } catch {
          /* tolerate teardown failures */
        }
        try {
          await service.auth.admin.deleteUser(u.id);
        } catch {
          /* tolerate teardown failures */
        }
      }
    });

    test("(a) INSERT happy → 201", async () => {
      const msg = await seedDraftMessage(service, userA.id, ACTION_CLASS);
      const { error } = await service.from("action_sends").insert({
        user_id: userA.id,
        message_id: msg.id,
        action_class: ACTION_CLASS,
        tier_at_send: "draft_one_click",
        template_hash: sha256("template-a"),
        per_send_body_sha256: sha256("body-a"),
        recipient_id_hash: sha256("recipient-a"),
        confirmed_typed: false,
        grant_id: userA_grantId,
      });
      expect(error).toBeNull();
    });

    test("(b) UPDATE → P0001 (pure-reject)", async () => {
      const msg = await seedDraftMessage(service, userA.id, ACTION_CLASS);
      const { data: row, error: insErr } = await service
        .from("action_sends")
        .insert({
          user_id: userA.id,
          message_id: msg.id,
          action_class: ACTION_CLASS,
          tier_at_send: "draft_one_click",
          template_hash: sha256("template-b"),
          per_send_body_sha256: sha256("body-b"),
          recipient_id_hash: sha256("recipient-b"),
          grant_id: userA_grantId,
        })
        .select("id")
        .single();
      expect(insErr).toBeNull();

      const { error: updErr } = await service
        .from("action_sends")
        .update({ recipient_id_hash: sha256("attacker-rewrite") })
        .eq("id", row!.id);
      expect(updErr).not.toBeNull();
      expect(updErr!.code).toBe("P0001");
      expect(updErr!.message).toMatch(/append-only|WORM/i);
    });

    test("(c) DELETE → P0001", async () => {
      const msg = await seedDraftMessage(service, userA.id, ACTION_CLASS);
      const { data: row, error: insErr } = await service
        .from("action_sends")
        .insert({
          user_id: userA.id,
          message_id: msg.id,
          action_class: ACTION_CLASS,
          tier_at_send: "draft_one_click",
          template_hash: sha256("template-c"),
          per_send_body_sha256: sha256("body-c"),
          recipient_id_hash: sha256("recipient-c"),
          grant_id: userA_grantId,
        })
        .select("id")
        .single();
      expect(insErr).toBeNull();

      const { error: delErr } = await service
        .from("action_sends")
        .delete()
        .eq("id", row!.id);
      expect(delErr).not.toBeNull();
      expect(delErr!.code).toBe("P0001");
    });

    test("(d) INSERT with NULL template_hash → 23502 (NOT NULL violation)", async () => {
      const msg = await seedDraftMessage(service, userA.id, ACTION_CLASS);
      const { error } = await service.from("action_sends").insert({
        user_id: userA.id,
        message_id: msg.id,
        action_class: ACTION_CLASS,
        tier_at_send: "draft_one_click",
        template_hash: null,
        per_send_body_sha256: sha256("body-d"),
        recipient_id_hash: sha256("recipient-d"),
        grant_id: userA_grantId,
      });
      expect(error).not.toBeNull();
      expect(error!.code).toBe("23502");
    });

    test("(e) scope_grants.tier = 'auto_with_digest' → grant accepted", async () => {
      // grant_action_class RPC accepts the 4th tier value. Verifies both
      // the CHECK widening AND the RPC literal-list widening.
      const { error: grantErr } = await tenantA.rpc("grant_action_class", {
        p_action_class: "infra.dependency_bump",
        p_tier: "auto_with_digest",
      });
      expect(grantErr, "grant_action_class(auto_with_digest)").toBeNull();

      const { data, error } = await service
        .from("scope_grants")
        .select("tier")
        .eq("founder_id", userA.id)
        .eq("action_class", "infra.dependency_bump")
        .is("revoked_at", null)
        .limit(1);
      expect(error).toBeNull();
      expect(data?.[0]?.tier).toBe("auto_with_digest");
    });

    test("(f) scope_grants.tier = 'garbage' → 22P02", async () => {
      const { error } = await tenantA.rpc("grant_action_class", {
        p_action_class: ACTION_CLASS,
        p_tier: "garbage",
      });
      expect(error).not.toBeNull();
      // grant_action_class raises 22P02 from the literal-list guard
      // BEFORE the DB CHECK has a chance to fire — both signals are
      // load-bearing; the literal-list is the first defense.
      expect(["22P02", "23514"]).toContain(error!.code);
    });

    test("(g) action_sends.action_class = 'payment.refund' → 23514 (DB CHECK enum-absence)", async () => {
      // The FK to scope_grants would normally block this — the 5th class
      // is enum-absent from ACTION_CLASSES so no grant exists. But the
      // DB CHECK regex action_sends_action_class_not_locked fires first
      // (it inspects the new row's action_class value before FK resolution).
      // This test asserts the CHECK rejects the value with 23514.
      const msg = await seedDraftMessage(service, userA.id, ACTION_CLASS);
      const { error } = await service.from("action_sends").insert({
        user_id: userA.id,
        message_id: msg.id,
        action_class: FORBIDDEN_CLASS,
        tier_at_send: "draft_one_click",
        template_hash: sha256("template-g"),
        per_send_body_sha256: sha256("body-g"),
        recipient_id_hash: sha256("recipient-g"),
        grant_id: userA_grantId,
      });
      expect(error).not.toBeNull();
      // 23514 = check_violation. Either the CHECK on action_sends or the
      // sibling CHECK on scope_grants would fire — both are P-H scope.
      expect(error!.code).toBe("23514");
    });

    test("(h) anonymise_action_sends → action_sends.user_id IS NULL", async () => {
      // Use a throwaway user for this destructive test so we don't tear
      // down the shared userA mid-suite.
      const u = { id: "", email: syntheticEmail() };
      assertSynthetic(u.email);
      const { data: created, error: createErr } =
        await service.auth.admin.createUser({
          email: u.email,
          password: randomBytes(16).toString("hex"),
          email_confirm: true,
        });
      expect(createErr).toBeNull();
      u.id = created.user!.id;

      const { jwt } = await mintFounderJwt(u.id, { ttlSec: 600 });
      const uClient = createClient(
        requireEnv("SUPABASE_URL"),
        requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
        {
          global: { headers: { Authorization: `Bearer ${jwt}` } },
          auth: { persistSession: false, autoRefreshToken: false },
        },
      );
      await uClient.rpc("grant_action_class", {
        p_action_class: ACTION_CLASS,
        p_tier: "draft_one_click",
      });
      const { data: g } = await service
        .from("scope_grants")
        .select("id")
        .eq("founder_id", u.id)
        .eq("action_class", ACTION_CLASS)
        .is("revoked_at", null)
        .single();

      const msg = await seedDraftMessage(service, u.id, ACTION_CLASS);
      await service.from("action_sends").insert({
        user_id: u.id,
        message_id: msg.id,
        action_class: ACTION_CLASS,
        tier_at_send: "draft_one_click",
        template_hash: sha256("template-h"),
        per_send_body_sha256: sha256("body-h"),
        recipient_id_hash: sha256("recipient-h"),
        grant_id: g!.id,
      });

      // Run the anonymise RPC.
      const { data: rowsAffected, error: anonErr } = await service.rpc(
        "anonymise_action_sends",
        { p_user_id: u.id },
      );
      expect(anonErr, "anonymise_action_sends RPC").toBeNull();
      expect(typeof rowsAffected).toBe("number");
      expect(rowsAffected as unknown as number).toBeGreaterThan(0);

      // Post-condition: user_id zeroed.
      const { data: afterRows } = await service
        .from("action_sends")
        .select("user_id, recipient_id_hash")
        .eq("message_id", msg.id);
      expect(afterRows?.length).toBe(1);
      expect(afterRows![0].user_id, "user_id zeroed").toBeNull();
      expect(afterRows![0].recipient_id_hash, "recipient_id_hash overwritten").toBe("__anonymised__");

      // Best-effort cleanup of the throwaway user — independent of the
      // assertion under test. Cascade-ordering owned by
      // account-delete-scope-grants-cascade.test.ts.
      try {
        await service.rpc("anonymise_scope_grants", { p_user_id: u.id });
      } catch { /* tolerate teardown failure */ }
      try {
        await service.auth.admin.deleteUser(u.id);
      } catch { /* tolerate teardown failure */ }
    });

    test("(i) cross-tenant SELECT → 0 rows", async () => {
      // userA has rows; userB queries via JWT → RLS owner-select must
      // return 0 of userA's rows.
      const { data, error } = await tenantB
        .from("action_sends")
        .select("id")
        .eq("user_id", userA.id);
      expect(error).toBeNull();
      expect(data?.length ?? 0).toBe(0);
    });
  },
);
