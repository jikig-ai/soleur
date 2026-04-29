/**
 * Cross-tenant Realtime payload isolation — DB integration test.
 *
 * Phase 5b for plan 2026-04-29-feat-command-center-conversation-nav. Asserts
 * the load-bearing isolation guarantee: user A's `command-center` Realtime
 * subscription receives ZERO `postgres_changes` payloads triggered by user
 * B's INSERT/UPDATE/DELETE on the `conversations` table.
 *
 * Why a real-Supabase test: the e2e mock-supabase stub rejects /realtime/*
 * with HTTP 200 instead of upgrading the WebSocket, so RLS + filter
 * behaviour cannot be exercised against the mock. The user-visible
 * isolation contract therefore only has integration-test coverage here.
 *
 * Special attention to DELETE (per deepen-plan Risk #1 + Supabase docs):
 * Postgres cannot verify access to a deleted row, so DELETE payloads
 * bypass RLS. Defensive client-side `user_id !== uid` drops in
 * use-conversations.ts:243-246 are what catch this. This test exercises
 * the deeper invariant — user A's Realtime channel + filter combination
 * never delivers user B's DELETE event in the first place — so even if
 * the client drop check were ever removed, RLS-bypass + filter mismatch
 * would still keep the user's data isolated.
 *
 * Opt-in via SUPABASE_DEV_INTEGRATION=1. Run from apps/web-platform:
 *   doppler run -p soleur -c dev -- \
 *     env SUPABASE_DEV_INTEGRATION=1 \
 *     ./node_modules/.bin/vitest run test/conversations-rail-cross-tenant.integration.test.ts
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
  type RealtimeChannel,
  type RealtimePostgresChangesPayload,
} from "@supabase/supabase-js";
import { randomBytes } from "crypto";
import { ensureNodeWebSocketPolyfill } from "./helpers/node-websocket-polyfill";

const INTEGRATION_ENABLED =
  process.env.SUPABASE_DEV_INTEGRATION === "1";

// hr-destructive-prod-tests-allowlist: only synthetic emails matching this
// pattern may be created or deleted by this test.
const SYNTHETIC_EMAIL_PATTERN =
  /^conv-rail-cross-tenant-[a-f0-9]{16}@soleur\.test$/;

function syntheticEmail(): string {
  return `conv-rail-cross-tenant-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates conv-rail-cross-tenant-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`[conversations-rail.integration] ${name} is required`);
  }
  return value;
}

const SHARED_REPO_URL = "https://github.com/acme/cross-tenant-test";
const REALTIME_SETTLE_MS = 2_000;

describe.skipIf(!INTEGRATION_ENABLED)(
  "ConversationsRail cross-tenant Realtime isolation",
  () => {
    let service: SupabaseClient;
    let userAClient: SupabaseClient;

    const userA = {
      id: "",
      email: syntheticEmail(),
      password: randomBytes(16).toString("hex"),
    };
    const userB = {
      id: "",
      email: syntheticEmail(),
      password: randomBytes(16).toString("hex"),
    };

    let channelA: RealtimeChannel | null = null;
    const receivedPayloads: RealtimePostgresChangesPayload<{
      [key: string]: unknown;
    }>[] = [];

    beforeAll(async () => {
      // Must run BEFORE any createClient(). On Node without native WebSocket,
      // realtime-js's factory returns `unsupported` and JOIN times out at 10s
      // (issue #3052). See test/helpers/node-websocket-polyfill.ts.
      ensureNodeWebSocketPolyfill();

      const supabaseUrl = requireEnv("NEXT_PUBLIC_SUPABASE_URL");
      const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

      service = createClient(supabaseUrl, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      for (const user of [userA, userB]) {
        assertSynthetic(user.email);
        const { data, error } = await service.auth.admin.createUser({
          email: user.email,
          password: user.password,
          email_confirm: true,
        });
        if (data.user?.id) user.id = data.user.id;
        expect(error, `createUser(${user.email}) failed`).toBeNull();
        expect(user.id).toBeTruthy();
      }

      // Both users share the same repo_url — the rail's filter is
      // user_id-only, so cross-tenant isolation MUST come from RLS +
      // filter:user_id=eq, not from a serendipitous repo_url mismatch.
      for (const user of [userA, userB]) {
        const { error } = await service
          .from("users")
          .update({ repo_url: SHARED_REPO_URL })
          .eq("id", user.id);
        expect(error, `update users.repo_url for ${user.email}`).toBeNull();
      }

      // Sign in as user A to get a JWT for the rail-equivalent subscription.
      userAClient = createClient(supabaseUrl, anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { error: signInErr } = await userAClient.auth.signInWithPassword(
        { email: userA.email, password: userA.password },
      );
      expect(signInErr, "userA sign-in failed").toBeNull();

      // Mirror the rail's exact subscription contract: channel name +
      // postgres_changes event spec + filter shape.
      await new Promise<void>((resolve, reject) => {
        channelA = userAClient
          .channel("command-center")
          .on(
            "postgres_changes",
            {
              event: "*",
              schema: "public",
              table: "conversations",
              filter: `user_id=eq.${userA.id}`,
            },
            (payload) => {
              receivedPayloads.push(payload);
            },
          )
          .subscribe((status, err) => {
            if (status === "SUBSCRIBED") resolve();
            if (status === "CHANNEL_ERROR" || status === "CLOSED")
              reject(err ?? new Error(`channel status: ${status}`));
          });
      });
    }, 30_000);

    afterAll(async () => {
      if (channelA) await channelA.unsubscribe();
      if (userAClient) await userAClient.removeAllChannels();

      if (!service) return;

      // Two-pass cleanup to avoid an FK ordering hazard: if
      // conversations.user_id ever gains ON DELETE RESTRICT, deleting
      // user A first while B's row still references A would fail
      // mid-loop and leave B's auth.users row orphaned. Pass 1 deletes
      // every synthetic conversation; pass 2 deletes every synthetic
      // user. Each pass tolerates not-found.
      for (const user of [userA, userB]) {
        if (!user.id) continue;
        assertSynthetic(user.email);
        await service.from("conversations").delete().eq("user_id", user.id);
      }

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

    test("user A receives ZERO payloads from user B's INSERT", async () => {
      receivedPayloads.length = 0;

      const { data: inserted, error } = await service
        .from("conversations")
        .insert({
          user_id: userB.id,
          repo_url: SHARED_REPO_URL,
          status: "active",
        })
        .select("id")
        .single();
      expect(error, "userB INSERT (via service) failed").toBeNull();
      expect(inserted?.id).toBeTruthy();

      await new Promise((r) => setTimeout(r, REALTIME_SETTLE_MS));

      const leaks = receivedPayloads.filter(
        (p) =>
          (p.new as Record<string, unknown> | null)?.user_id === userB.id ||
          (p.old as Record<string, unknown> | null)?.user_id === userB.id,
      );
      expect(
        leaks,
        `INSERT leaked ${leaks.length} cross-tenant payload(s) to user A`,
      ).toEqual([]);
    });

    test("user A receives ZERO payloads from user B's UPDATE", async () => {
      receivedPayloads.length = 0;

      const { data: targetRow, error: lookupErr } = await service
        .from("conversations")
        .select("id")
        .eq("user_id", userB.id)
        .limit(1)
        .single();
      expect(lookupErr, "lookup userB row for UPDATE").toBeNull();

      const { error } = await service
        .from("conversations")
        .update({ status: "completed" })
        .eq("id", targetRow!.id);
      expect(error, "userB UPDATE (via service) failed").toBeNull();

      await new Promise((r) => setTimeout(r, REALTIME_SETTLE_MS));

      const leaks = receivedPayloads.filter(
        (p) =>
          (p.new as Record<string, unknown> | null)?.user_id === userB.id ||
          (p.old as Record<string, unknown> | null)?.user_id === userB.id,
      );
      expect(
        leaks,
        `UPDATE leaked ${leaks.length} cross-tenant payload(s) to user A`,
      ).toEqual([]);
    });

    test("user A receives ZERO payloads from user B's DELETE (RLS-bypass case)", async () => {
      receivedPayloads.length = 0;

      // Seed a fresh row to delete so the assertion is independent of
      // INSERT/UPDATE test ordering (each test self-seeds).
      const { data: seeded, error: seedErr } = await service
        .from("conversations")
        .insert({
          user_id: userB.id,
          repo_url: SHARED_REPO_URL,
          status: "active",
        })
        .select("id")
        .single();
      expect(seedErr, "seed userB row for DELETE").toBeNull();
      // The seed INSERT also broadcasts; flush settle window before the
      // DELETE so we measure DELETE leaks specifically.
      await new Promise((r) => setTimeout(r, REALTIME_SETTLE_MS));
      receivedPayloads.length = 0;

      const { error } = await service
        .from("conversations")
        .delete()
        .eq("id", seeded!.id);
      expect(error, "userB DELETE (via service) failed").toBeNull();

      await new Promise((r) => setTimeout(r, REALTIME_SETTLE_MS));

      // REPLICA IDENTITY canary. If migration 015 ever regresses to
      // DEFAULT, payload.old collapses to {id} only — `payload.old.user_id`
      // becomes undefined and the leak filter below would silently match
      // ZERO payloads, vacuously passing this load-bearing test. Fail
      // loudly here when the DELETE-payload shape doesn't carry user_id.
      const deletePayloads = receivedPayloads.filter(
        (p) => p.eventType === "DELETE",
      );
      for (const p of deletePayloads) {
        const old = p.old as Record<string, unknown> | null;
        expect(
          old && "user_id" in old,
          "REPLICA IDENTITY regression: DELETE payload.old missing user_id — " +
            "migration 015 is the source of truth and this assertion is the " +
            "regression gate. Restore REPLICA IDENTITY FULL on conversations.",
        ).toBe(true);
      }

      // DELETE bypasses RLS (Postgres cannot check access on the deleted
      // row), so this is the load-bearing case for the test. The expected
      // result is still ZERO payloads thanks to the per-user filter:
      // server-side `filter: user_id=eq.${userA.id}` excludes user B's
      // DELETEs even though RLS itself is silent on them.
      const leaks = receivedPayloads.filter(
        (p) =>
          (p.new as Record<string, unknown> | null)?.user_id === userB.id ||
          (p.old as Record<string, unknown> | null)?.user_id === userB.id,
      );
      expect(
        leaks,
        `DELETE leaked ${leaks.length} cross-tenant payload(s) to user A`,
      ).toEqual([]);
    });
  },
);
