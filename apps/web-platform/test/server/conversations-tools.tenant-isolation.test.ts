/**
 * Tenant isolation — conversations-tools.ts (PR-C §2.9, #3244).
 *
 * Covers the 4 migrated sites (one per tool factory):
 *
 *   - `:156` conversations_list — SELECT
 *   - `:217` conversation_archive — UPDATE
 *   - `:254` conversation_unarchive — UPDATE
 *   - `:297` conversation_update_status — UPDATE
 *
 * Each tool's WHERE clause is a 3-column composite key (id, user_id,
 * repo_url) layered on top of RLS `auth.uid() = user_id`. Both controls
 * must fail closed: A's tenant JWT spoofing B's conversationId returns
 * 0 rows (composite key miss); A's tenant JWT spoofing B's user_id
 * filter returns 0 rows (RLS); A using their own user_id but a foreign
 * conversationId returns 0 rows (RLS deny via FK).
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
  "tenant isolation — conversations-tools.ts (4 sites)",
  () => {
    let service: SupabaseClient;
    let aClient: SupabaseClient;

    const userA = { id: "", email: syntheticEmail() };
    const userB = { id: "", email: syntheticEmail() };
    const REPO_URL_A = `https://github.com/test/${randomBytes(4).toString("hex")}.git`;
    const REPO_URL_B = `https://github.com/test/${randomBytes(4).toString("hex")}.git`;
    let aConvId = "";
    let bConvId = "";

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

      for (const [user, repoUrl, ref] of [
        [userA, REPO_URL_A, "a"] as const,
        [userB, REPO_URL_B, "b"] as const,
      ]) {
        const { data: convRow } = await service
          .from("conversations")
          .insert({
            user_id: user.id,
            session_id: `tenant-isolation-${randomBytes(4).toString("hex")}`,
            repo_url: repoUrl,
            status: "active",
          })
          .select("id")
          .single();
        if (ref === "a") aConvId = convRow!.id;
        else bConvId = convRow!.id;
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

    test("baseline: A's tenant JWT lists own conversation", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .select("id, status, repo_url")
        .eq("user_id", userA.id)
        .eq("repo_url", REPO_URL_A)
        .is("archived_at", null);
      expect(error).toBeNull();
      expect(data?.some((r) => r.id === aConvId)).toBe(true);
    });

    test("`:156` conversations_list — A's tenant JWT cannot list B's rows", async () => {
      const { data } = await aClient
        .from("conversations")
        .select("id, status, domain_leader, last_active, created_at, archived_at")
        .eq("user_id", userB.id)
        .eq("repo_url", REPO_URL_B);
      expect(data).toEqual([]);
    });

    test("`:217` conversation_archive — A cannot archive B's row", async () => {
      const { data } = await aClient
        .from("conversations")
        .update({ archived_at: new Date().toISOString() })
        .eq("id", bConvId)
        .eq("user_id", userB.id)
        .eq("repo_url", REPO_URL_B)
        .select("id, archived_at");
      expect(data).toEqual([]);
    });

    test("`:254` conversation_unarchive — A cannot unarchive B's row", async () => {
      const { data } = await aClient
        .from("conversations")
        .update({ archived_at: null })
        .eq("id", bConvId)
        .eq("user_id", userB.id)
        .eq("repo_url", REPO_URL_B)
        .select("id, archived_at");
      expect(data).toEqual([]);
    });

    test("`:297` conversation_update_status — A cannot set B's status to failed", async () => {
      const { data } = await aClient
        .from("conversations")
        .update({ status: "failed" })
        .eq("id", bConvId)
        .eq("user_id", userB.id)
        .eq("repo_url", REPO_URL_B)
        .select("id, status");
      expect(data).toEqual([]);

      const { data: stillThere } = await service
        .from("conversations")
        .select("status")
        .eq("id", bConvId)
        .maybeSingle();
      expect(stillThere?.status).not.toBe("failed");
    });

    test("composite key — A using own user_id but B's convId still fails", async () => {
      const { data } = await aClient
        .from("conversations")
        .update({ status: "failed" })
        .eq("id", bConvId)
        .eq("user_id", userA.id) // attacker's own id
        .eq("repo_url", REPO_URL_A)
        .select("id");
      expect(data).toEqual([]);
    });
  },
);
