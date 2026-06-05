/**
 * `users`-table RLS regression guard (originally PR-C §2.8, #3244).
 *
 * History: both KB-root helpers have now migrated OFF the tenant `users` read.
 * `resolveUserKbRoot` was removed in the ADR-044 share+upload consolidation
 * (#4953); `authenticateAndResolveKbPath` migrated to the membership-scoped
 * service-role resolvers `resolveActiveWorkspaceKbRoot` /
 * `resolveActiveWorkspaceRepoMeta` in #4956. Neither helper reads
 * `users.{workspace_path,workspace_status,repo_url,github_installation_id}`
 * via a tenant client any more.
 *
 * These cases survive as a standalone RLS regression guard on the `users`
 * row + extras columns (`auth.uid() = id`): the columns remain RLS-protected
 * and other code paths still read them, so a policy regression must stay
 * caught even though the KB write routes no longer depend on this read.
 *
 * Asserts: A's tenant JWT cannot read B's `users` row / extras columns.
 * Tested at the data-layer. The KB route handlers' 404/503/400 behavior is
 * covered by route-level tests (kb-rename / kb-delete / kb-route-helpers).
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
  "users-table RLS regression guard (post-#4956 KB resolver migration)",
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

      for (const user of [userA, userB]) {
        const { error } = await service
          .from("users")
          .update({
            workspace_path: `/tmp/synthetic/${user.id.slice(0, 8)}`,
            workspace_status: "ready",
            repo_url: `https://github.com/test/${user.id.slice(0, 8)}.git`,
            github_installation_id: parseInt(user.id.slice(0, 8), 16),
          })
          .eq("id", user.id);
        expect(error).toBeNull();
      }

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
        .select(
          "workspace_path, workspace_status, repo_url, github_installation_id",
        )
        .eq("id", userA.id)
        .single();
      expect(error).toBeNull();
      expect(data?.workspace_path).toContain("/tmp/synthetic/");
    });

    test("users-RLS — A cannot read B's workspace tuple (former KB-helper read shape)", async () => {
      const { data, error } = await aClient
        .from("users")
        .select(
          "workspace_path, workspace_status, repo_url, github_installation_id",
        )
        .eq("id", userB.id)
        .single();
      expect(data).toBeNull();
      expect(error?.code).toBe("PGRST116");
    });

    test("users-extras RLS guard — A cannot read B's extras (repo_url, installation_id)", async () => {
      const { data, error } = await aClient
        .from("users")
        .select(
          "workspace_path, workspace_status, repo_url, github_installation_id",
        )
        .eq("id", userB.id)
        .single<{
          workspace_path: string;
          repo_url: string;
          github_installation_id: number;
        }>();
      expect(data).toBeNull();
      expect(error?.code).toBe("PGRST116");
    });
  },
);
