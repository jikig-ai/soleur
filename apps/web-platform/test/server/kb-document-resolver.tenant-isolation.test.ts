/**
 * Tenant isolation — Concierge document workspace-path resolution.
 *
 * ADR-044 cutover (feat-one-shot-concierge-doc-context-parity): the Concierge
 * document resolver + agent sandbox cwd no longer read `users.workspace_path`.
 * `fetchUserWorkspacePath` (kb-document-resolver.ts) now resolves the caller's
 * ACTIVE workspace via `resolveActiveWorkspacePath` → `resolveCurrentWorkspaceId`,
 * which SELECTs `user_session_state.current_workspace_id` scoped to the caller's
 * own id. RLS on `user_session_state`: `user_session_state_owner_select`
 * (`auth.uid() = user_id`, migrations 060/064).
 *
 * Asserts: A's tenant JWT cannot read B's `user_session_state` row. B's row
 * EXISTS (seeded via the service role), so a null result proves RLS DENIAL — not
 * mere row-absence. This is the isolation guarantee behind the workspace-path
 * resolution: A can never resolve B's active workspace, so the membership
 * self-heal in `resolveActiveWorkspaceIdWithMembership` cannot be tricked into
 * reading a sibling's workspace files.
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
  "tenant isolation — Concierge workspace-path resolution (user_session_state)",
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

      // Seed a user_session_state row for BOTH users so the cross-tenant read
      // tests RLS DENIAL (B's row exists) rather than row-absence. Only user_id
      // is required (current_organization_id / current_workspace_id are nullable
      // FKs; updated_at defaults). Leaving current_workspace_id NULL avoids the
      // workspaces FK — the row's existence is what the deny test needs.
      for (const user of [userA, userB]) {
        const { error } = await service
          .from("user_session_state")
          .upsert({ user_id: user.id }, { onConflict: "user_id" });
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
        // user_session_state row cascades on user delete (ON DELETE CASCADE).
        await service.auth.admin.deleteUser(user.id).catch(() => {});
      }
    }, 30_000);

    test("baseline: A reads own user_session_state row", async () => {
      const { data, error } = await aClient
        .from("user_session_state")
        .select("user_id, current_workspace_id")
        .eq("user_id", userA.id)
        .maybeSingle();
      expect(error).toBeNull();
      expect(data?.user_id).toBe(userA.id);
    });

    test("A's tenant JWT cannot read B's user_session_state (RLS denial)", async () => {
      const { data, error } = await aClient
        .from("user_session_state")
        .select("user_id, current_workspace_id")
        .eq("user_id", userB.id)
        .maybeSingle();
      // B's row EXISTS — a null result is RLS denying the cross-tenant read,
      // not an absent row.
      expect(error).toBeNull();
      expect(data).toBeNull();
    });
  },
);
