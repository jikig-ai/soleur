/**
 * Trigger integration test — archive must release the concurrency slot.
 *
 * Opt-in via SLOT_TRIGGER_INTEGRATION_TEST=1. Runs against the real Supabase
 * dev project; requires `doppler run -p soleur -c dev` to provide env vars.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env SLOT_TRIGGER_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run test/conversation-archive-release-slot.integration.test.ts
 *
 * Plan: 2026-05-04-fix-cc-conversation-limit-archive-plan.md AC6 / AC14.
 *
 * Vitest cannot exercise Postgres triggers natively — the migration-shape
 * test (test/supabase-migrations/036-release-slot-on-archive.test.ts) pins
 * the SQL contract, but only a real DB run can verify the trigger actually
 * fires. This file closes that loop: insert a slot, archive the conversation,
 * assert the slot row is gone.
 */

import { afterAll, afterEach, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "crypto";

const INTEGRATION_ENABLED = process.env.SLOT_TRIGGER_INTEGRATION_TEST === "1";

// Only synthetic emails matching this pattern may be created or deleted by
// this test. Enforces hr-destructive-prod-tests-allowlist.
const SYNTHETIC_EMAIL_PATTERN = /^slot-trigger-[a-f0-9]{16}@soleur\.test$/;

function syntheticEmail(): string {
  return `slot-trigger-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates slot-trigger-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`[slot-trigger.integration] ${name} is required`);
  }
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "release_slot_on_archive trigger (integration)",
  () => {
    let service: SupabaseClient;

    const user = {
      id: "",
      email: syntheticEmail(),
      password: randomBytes(16).toString("hex"),
    };

    beforeAll(async () => {
      const supabaseUrl = requireEnv("NEXT_PUBLIC_SUPABASE_URL");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

      service = createClient(supabaseUrl, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      assertSynthetic(user.email);
      const { data, error } = await service.auth.admin.createUser({
        email: user.email,
        password: user.password,
        email_confirm: true,
      });
      // Assign id BEFORE asserting so afterAll cleanup runs even if a flaky
      // post-create assertion below trips. Same pattern as byok.integration.
      user.id = data.user?.id ?? "";
      expect(error, `createUser(${user.email}) failed`).toBeNull();
      expect(user.id).toBeTruthy();
    }, 30_000);

    afterEach(async () => {
      if (!service || !user.id) return;
      // Per-test cleanup so slot/conversation rows from one test do not
      // skew the next test's slotCount() or trigger ordering coupling.
      // Conversations: cascade through user_concurrency_slots is NOT
      // present (slot FK is on users, not conversations) — clean both.
      await service
        .from("user_concurrency_slots")
        .delete()
        .eq("user_id", user.id);
      await service.from("conversations").delete().eq("user_id", user.id);
    });

    afterAll(async () => {
      if (!service || !user.id) return;
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
    }, 30_000);

    async function insertConversation(repoUrl: string): Promise<string> {
      const id = randomUUID();
      const sessionId = randomUUID();
      const { error } = await service.from("conversations").insert({
        id,
        user_id: user.id,
        session_id: sessionId,
        repo_url: repoUrl,
        status: "active",
        title: "slot-trigger integration",
      });
      expect(error, `insert conversation failed: ${error?.message}`).toBeNull();
      return id;
    }

    async function acquireSlot(
      conversationId: string,
      cap = 1,
    ): Promise<{ status: string; active_count: number }> {
      const { data, error } = await service.rpc("acquire_conversation_slot", {
        p_user_id: user.id,
        p_conversation_id: conversationId,
        p_effective_cap: cap,
      });
      expect(
        error,
        `acquire_conversation_slot failed: ${error?.message}`,
      ).toBeNull();
      // RPC returns TABLE — supabase-js gives us an array.
      const row = Array.isArray(data) ? data[0] : data;
      return { status: row.status, active_count: row.active_count };
    }

    async function slotCount(): Promise<number> {
      const { count, error } = await service
        .from("user_concurrency_slots")
        .select("*", { count: "exact", head: true })
        .eq("user_id", user.id);
      expect(error, `slot count query failed: ${error?.message}`).toBeNull();
      return count ?? 0;
    }

    test("archiving a conversation releases its concurrency slot", async () => {
      const repoUrl = `https://github.com/synthetic/${randomBytes(4).toString("hex")}`;
      const convId = await insertConversation(repoUrl);

      const acquireResult = await acquireSlot(convId, 1);
      expect(acquireResult.status).toBe("ok");
      expect(await slotCount()).toBe(1);

      const { error: archiveError } = await service
        .from("conversations")
        .update({ archived_at: new Date().toISOString() })
        .eq("id", convId);
      expect(archiveError).toBeNull();

      // The trigger fires AFTER UPDATE OF archived_at — synchronous; the
      // slot row should be gone before the UPDATE returns.
      expect(await slotCount()).toBe(0);
    }, 30_000);

    test("free-tier user can start a new conversation immediately after archiving", async () => {
      // Reproduces the user's reported scenario: cap = 1, archive the
      // current conversation, start a new one. Pre-fix: cap_hit. Post-fix: ok.
      const repoUrl = `https://github.com/synthetic/${randomBytes(4).toString("hex")}`;
      const oldConv = await insertConversation(repoUrl);

      expect((await acquireSlot(oldConv, 1)).status).toBe("ok");

      const { error: archiveError } = await service
        .from("conversations")
        .update({ archived_at: new Date().toISOString() })
        .eq("id", oldConv);
      expect(archiveError).toBeNull();

      const newConv = await insertConversation(repoUrl);
      const acquireNew = await acquireSlot(newConv, 1);

      // Post-fix: the trigger released the old slot, so this acquire fits
      // under cap = 1. Pre-fix would have returned cap_hit because the old
      // slot was still in the ledger.
      expect(acquireNew.status).toBe("ok");
      expect(acquireNew.active_count).toBe(1);
    }, 30_000);

    test("regression guard: trigger MUST NOT broaden to release on unarchive", async () => {
      // Negative-space regression test. This test PASSES on the pre-fix
      // branch too (no trigger means no release on unarchive either — the
      // slot just leaks). It guards against a future broadening of the
      // trigger's WHEN clause that would drop the `NEW.archived_at IS NOT
      // NULL` filter and start releasing on unarchive (NULL → non-NULL →
      // NULL). That broadening would silently break re-acquire-on-resume.
      const repoUrl = `https://github.com/synthetic/${randomBytes(4).toString("hex")}`;
      const convId = await insertConversation(repoUrl);

      expect((await acquireSlot(convId, 1)).status).toBe("ok");
      expect(await slotCount()).toBe(1);

      // Archive — slot released.
      await service
        .from("conversations")
        .update({ archived_at: new Date().toISOString() })
        .eq("id", convId);
      expect(await slotCount()).toBe(0);

      // Re-acquire (simulating a "+ New conversation" after archive).
      const newConv = await insertConversation(repoUrl);
      expect((await acquireSlot(newConv, 1)).status).toBe("ok");
      expect(await slotCount()).toBe(1);

      // Unarchive the OLD row — trigger must NOT fire (NEW.archived_at
      // IS NULL fails the WHEN clause). The new conversation's slot must
      // remain.
      await service
        .from("conversations")
        .update({ archived_at: null })
        .eq("id", convId);
      expect(await slotCount()).toBe(1);
    }, 30_000);

    test("regression guard: trigger MUST NOT broaden to release on status='completed'", async () => {
      // Negative-space regression test. PASSES pre-fix too. Guards against
      // a future widening of the AFTER UPDATE OF column list that would
      // include `status` — see plan Risk #5: releasing on completed alone
      // would let `resume_session` bypass the cap, because resume_session
      // (ws-handler.ts:812) does not call acquireSlot.
      const repoUrl = `https://github.com/synthetic/${randomBytes(4).toString("hex")}`;
      const convId = await insertConversation(repoUrl);

      expect((await acquireSlot(convId, 1)).status).toBe("ok");
      expect(await slotCount()).toBe(1);

      const { error: statusError } = await service
        .from("conversations")
        .update({ status: "completed" })
        .eq("id", convId);
      expect(statusError).toBeNull();

      // Slot still held.
      expect(await slotCount()).toBe(1);
    }, 30_000);
  },
);
