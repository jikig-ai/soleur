/**
 * Tenant isolation — attachment-pipeline.ts + Storage RLS (PR-D §4, #3244).
 *
 * Covers the migrated surface:
 *
 *   - `cc-dispatcher.ts:1435` + `agent-runner.ts:2305` — `persistAndDownloadAttachments`
 *     called with tenant-scoped Supabase client (was service-role pre-PR-D).
 *   - `migration 045` — `storage.objects` FOR ALL policy on `chat-attachments`
 *     bucket scoped by `(storage.foldername(name))[1] = auth.uid()::text`.
 *   - `migration 045` — `message_attachments` INSERT policy joining through
 *     `messages.conversation_id → conversations.user_id = auth.uid()`.
 *
 * Closes the 3rd of 3 brand-survival vectors from umbrella #3244:
 *   1. cross-tenant `messages` INSERT (closed by PR-C #3854)
 *   2. cross-tenant sibling-query GET (closed by PR-C #3854)
 *   3. cross-tenant attachment read (closed by this PR)
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1.
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "node:crypto";

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
  "tenant isolation — attachment-pipeline.ts (Storage + message_attachments)",
  () => {
    let service: SupabaseClient;
    let aClient: SupabaseClient;
    let bClient: SupabaseClient;

    const userA = { id: "", email: syntheticEmail() };
    const userB = { id: "", email: syntheticEmail() };
    let convA = "";
    let convB = "";
    let messageB = "";
    let victimPath = "";

    // 1×1 transparent PNG fixture (synthetic content per
    // cq-test-fixtures-synthesized-only). Identifies as image/png to the
    // ALLOWED_ATTACHMENT_TYPES checker; small enough to avoid quota concerns.
    const PNG_1x1 = Buffer.from(
      "89504E470D0A1A0A0000000D49484452000000010000000108060000001F15C4890000000D49444154789C636000010000050001A1F8E9460000000049454E44AE426082",
      "hex",
    );

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

      // Seed each founder with a conversation.
      const { data: convARow } = await service
        .from("conversations")
        .insert({
          user_id: userA.id,
          session_id: `tenant-isolation-${randomBytes(4).toString("hex")}`,
          status: "active",
        })
        .select("id")
        .single();
      convA = convARow!.id;

      const { data: convBRow } = await service
        .from("conversations")
        .insert({
          user_id: userB.id,
          session_id: `tenant-isolation-${randomBytes(4).toString("hex")}`,
          status: "active",
        })
        .select("id")
        .single();
      convB = convBRow!.id;

      // Seed B with a `messages` row so the FK target exists. Without this,
      // the cross-tenant message_attachments INSERT test would fail via FK
      // violation (23503) BEFORE RLS evaluates — pass-for-wrong-reason per
      // 2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-
      // for-wrong-reason.md.
      messageB = randomUUID();
      const { error: msgErr } = await service.from("messages").insert({
        id: messageB,
        conversation_id: convB,
        role: "user",
        content: "tenant-isolation attachment seed",
        tool_calls: null,
        leader_id: null,
      });
      expect(msgErr).toBeNull();

      // Seed B's attachment object: real-shaped UUID path under B's folder.
      // Malformed paths produce NULL foldername result → false RLS-deny
      // signal; the path layout below mirrors production
      // `${userId}/${conversationId}/${random}.${ext}` exactly.
      victimPath = `${userB.id}/${convB}/${randomUUID()}.png`;
      const { error: uploadErr } = await service.storage
        .from("chat-attachments")
        .upload(victimPath, PNG_1x1, { contentType: "image/png" });
      expect(uploadErr).toBeNull();

      _resetTenantCache();
      const aMint = await mintFounderJwt(userA.id);
      aClient = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${aMint.jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const bMint = await mintFounderJwt(userB.id);
      bClient = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${bMint.jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      // Cap suite mint count to 2 — see test/helpers/mint-once.ts.
      registerSharedMintCache([
        [userA.id, aMint],
        [userB.id, bMint],
      ]);
    }, 30_000);

    afterAll(async () => {
      if (!service) return;
      // Storage bytes do NOT cascade via FK — explicit remove required per
      // gdpr-gate TS-05 finding.
      if (victimPath) {
        await service.storage
          .from("chat-attachments")
          .remove([victimPath])
          .catch(() => {});
      }
      for (const user of [userA, userB]) {
        if (!user.id) continue;
        assertSynthetic(user.email);
        await service.auth.admin.deleteUser(user.id).catch(() => {});
      }
    }, 30_000);

    // ──────────────────────────────────────────────────────────────────
    // FR1 — cross-tenant Storage SELECT deny (the brand-survival vector
    // PR-D is named for).
    // ──────────────────────────────────────────────────────────────────

    test("Storage download — A's tenant JWT cannot download B's attachment bytes (PR-D §4)", async () => {
      const { data, error } = await aClient.storage
        .from("chat-attachments")
        .download(victimPath);
      // RLS-deny shape from Storage: data === null, error is an opaque
      // "Object not found" rather than a 42501 — Storage masks RLS-deny
      // as not-found to avoid leaking existence. Accept either the
      // RLS-deny shape (error set + data null) or the
      // grant-deny shape (42501) per PR #3881 dual-shape pattern.
      expect(data).toBeNull();
      if (error) {
        // Storage error has `name`/`message`, not `code`. Just assert presence.
        expect(error).toBeTruthy();
      }
    });

    test("Storage download — B's own JWT CAN download B's attachment bytes (positive control)", async () => {
      // Without this control, a deny test could pass for the wrong reason
      // (fixture upload failed, bucket misconfigured, JWT broken).
      const { data, error } = await bClient.storage
        .from("chat-attachments")
        .download(victimPath);
      expect(error).toBeNull();
      expect(data).not.toBeNull();
    });

    // ──────────────────────────────────────────────────────────────────
    // FR2 — cross-tenant message_attachments INSERT deny.
    // ──────────────────────────────────────────────────────────────────

    test("message_attachments INSERT — A's JWT cannot INSERT row claiming B's messageId (RLS deny, NOT FK violation)", async () => {
      // FK target `messageB` exists (seeded above) so 23503 cannot fire.
      // The RLS policy joins through `messages.conversation_id →
      // conversations.user_id = auth.uid()`. A's JWT does not match
      // conversations.user_id for messageB → deny.
      const { data, error } = await aClient
        .from("message_attachments")
        .insert({
          id: randomUUID(),
          message_id: messageB,
          storage_path: `${userA.id}/${convA}/spoof.png`,
          filename: "spoof.png",
          content_type: "image/png",
          size_bytes: 1,
        })
        .select("id");
      // Dual-shape per PR #3881 pattern: RLS may surface as either
      //   (a) error=null, data=[] (PostgREST returning-clause shape under
      //       RLS with no matching rows visible to the caller)
      //   (b) error.code=42501, data=null (grant/policy deny)
      const succeeded = data && data.length > 0;
      expect(succeeded).toBeFalsy();
      if (error) {
        // Must NOT be a foreign-key violation; messageB was seeded above
        // expressly so RLS (not FK) is the load-bearing gate.
        expect(error.code).not.toBe("23503");
      }
      // Verify B's table has no spoofed row.
      const { data: rows } = await service
        .from("message_attachments")
        .select("id")
        .eq("message_id", messageB);
      expect(rows?.length ?? 0).toBe(0);
    });

    test("message_attachments INSERT — B's JWT CAN INSERT row for her own messageId (positive control)", async () => {
      const ownPath = `${userB.id}/${convB}/${randomUUID()}.png`;
      const insertId = randomUUID();
      const { error } = await bClient
        .from("message_attachments")
        .insert({
          id: insertId,
          message_id: messageB,
          storage_path: ownPath,
          filename: "own.png",
          content_type: "image/png",
          size_bytes: 1,
        });
      expect(error).toBeNull();
      // Cleanup the positive-control row so afterAll's auth.admin.deleteUser
      // cascade has a clean target set. PostgrestBuilder is a thenable but
      // not a Promise, so it has no `.catch` — await first, then ignore.
      try {
        await service
          .from("message_attachments")
          .delete()
          .eq("id", insertId);
      } catch {
        // best-effort cleanup
      }
    });

    // ──────────────────────────────────────────────────────────────────
    // Policy-shape codification (Kieran P3-1, AC25(a)): the no-WITH-CHECK
    // decision is asserted post-merge via `pg_policy` operator query
    // (Phase 8.4 step 1) rather than via a runtime probe — Storage RLS
    // surface is small enough and pg_policy is reliably reachable from
    // the operator's Doppler-pooled psql session.
    // ──────────────────────────────────────────────────────────────────
  },
);
