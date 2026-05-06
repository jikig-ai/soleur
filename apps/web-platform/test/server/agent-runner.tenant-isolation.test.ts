/**
 * Tenant isolation — DB-layer integration test (PR-B §1.3.1).
 *
 * Asserts the load-bearing PR-B invariant: founder A's runtime JWT
 * (from `mintFounderJwt(A.id)`) cannot read founder B's tenant data —
 * `messages`, `conversations`, `api_keys` — under RLS.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Runs against the dev Supabase
 * project; requires `doppler run -p soleur -c dev` to provide
 * SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
 * and SUPABASE_JWT_SECRET.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/agent-runner.tenant-isolation.test.ts
 *
 * Synthesized fixtures only (cq-test-fixtures-synthesized-only):
 *   - Synthetic emails matching `tenant-isolation-[a-f0-9]{16}@soleur.test`.
 *   - Email allowlist enforced before any auth.admin.deleteUser call.
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
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates tenant-isolation-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`[tenant-isolation] ${name} is required`);
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "tenant isolation — A's JWT cannot read B's data (integration)",
  () => {
    let service: SupabaseClient;
    let aClient: SupabaseClient;
    let bClient: SupabaseClient;

    const userA = {
      id: "",
      email: syntheticEmail(),
    };
    const userB = {
      id: "",
      email: syntheticEmail(),
    };

    let aConversationId = "";
    let bConversationId = "";

    beforeAll(async () => {
      const url = requireEnv("SUPABASE_URL");
      const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      requireEnv("SUPABASE_JWT_SECRET");

      service = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      // 1. Provision two synthetic founders via auth admin.
      for (const user of [userA, userB]) {
        assertSynthetic(user.email);
        const { data, error } = await service.auth.admin.createUser({
          email: user.email,
          password: randomBytes(16).toString("hex"),
          email_confirm: true,
        });
        if (data.user?.id) user.id = data.user.id;
        expect(error, `createUser(${user.email}) failed`).toBeNull();
        expect(user.id).toBeTruthy();
      }

      // 2. Seed each founder with one conversation + one message + one api_key.
      // Owners are RLS-isolated by user_id; A must not be able to read B's rows.
      for (const [user, ref] of [
        [userA, "aConversationId"] as const,
        [userB, "bConversationId"] as const,
      ]) {
        const { data: convRow, error: convError } = await service
          .from("conversations")
          .insert({
            user_id: user.id,
            session_id: `tenant-isolation-${randomBytes(4).toString("hex")}`,
          })
          .select("id")
          .single();
        expect(convError, `seed conversations for ${user.email}`).toBeNull();
        if (ref === "aConversationId") aConversationId = convRow!.id;
        else bConversationId = convRow!.id;

        const { error: msgError } = await service.from("messages").insert({
          conversation_id: convRow!.id,
          role: "user",
          content: `synthesized message for ${user.email}`,
        });
        expect(msgError, `seed messages for ${user.email}`).toBeNull();

        const { error: keyError } = await service.from("api_keys").insert({
          user_id: user.id,
          provider: "anthropic",
          encrypted_key: Buffer.from(`fake-${user.id}`).toString("base64"),
          iv: Buffer.from("000000000000").toString("base64"),
          auth_tag: Buffer.from("0000000000000000").toString("base64"),
          is_valid: true,
          key_version: 2,
        });
        expect(keyError, `seed api_keys for ${user.email}`).toBeNull();

        // Seed a team_names row so A↔B cross-tenant reads have a target.
        const { error: nameError } = await service.from("team_names").insert({
          user_id: user.id,
          leader_id: "cpo",
          custom_name: `Synthetic-${user.id.slice(0, 8)}`,
        });
        expect(nameError, `seed team_names for ${user.email}`).toBeNull();
      }

      // 3. Mint runtime JWTs for A and B via tenant.ts (the SUT).
      _resetTenantCache();
      const aMint = await mintFounderJwt(userA.id);
      const bMint = await mintFounderJwt(userB.id);

      // 4. Build raw clients per-JWT (bypassing the cache so each test is
      // unambiguous about which JWT it's exercising). The cache layer is
      // covered by the unit tests in tenant-jwt-refresh.test.ts.
      aClient = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${aMint.jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      bClient = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${bMint.jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
    }, 30_000);

    afterAll(async () => {
      if (!service) return;
      for (const user of [userA, userB]) {
        if (!user.id) continue;
        assertSynthetic(user.email);

        // Allowlist round-trip: confirm Supabase still has the synthetic
        // email under user.id before deleting (matches byok.integration
        // pattern for defense-in-depth).
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

    test("baseline: A's JWT can read A's own conversations row", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .select("id, user_id")
        .eq("id", aConversationId)
        .maybeSingle();
      expect(error).toBeNull();
      expect(data?.id).toBe(aConversationId);
      expect(data?.user_id).toBe(userA.id);
    });

    test("conversations: A's JWT cannot read B's conversation (RLS deny)", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .select("id")
        .eq("id", bConversationId);
      // PostgREST returns 200 with [] for RLS-filtered reads.
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    test("messages: A's JWT cannot read B's message (RLS deny via conversations FK)", async () => {
      const { data, error } = await aClient
        .from("messages")
        .select("id, conversation_id, content")
        .eq("conversation_id", bConversationId);
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    test("api_keys: A's JWT cannot read B's encrypted key (RLS deny)", async () => {
      const { data, error } = await aClient
        .from("api_keys")
        .select("user_id, encrypted_key")
        .eq("user_id", userB.id);
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    test("symmetric: B's JWT cannot read A's data either (no policy asymmetry)", async () => {
      // Catches a class of bug where a policy that names auth.uid()
      // works one way but a sibling policy (e.g., on messages) leaks the
      // other direction.
      const { data: convsViaB } = await bClient
        .from("conversations")
        .select("id")
        .eq("id", aConversationId);
      const { data: msgsViaB } = await bClient
        .from("messages")
        .select("id")
        .eq("conversation_id", aConversationId);
      const { data: keysViaB } = await bClient
        .from("api_keys")
        .select("user_id")
        .eq("user_id", userA.id);

      expect(convsViaB).toEqual([]);
      expect(msgsViaB).toEqual([]);
      expect(keysViaB).toEqual([]);
    });

    // Per user-impact-reviewer FINDING 5 (#3244): the `users` SELECT site at
    // session start is a high-value cross-tenant probe surface. A leak of
    // `github_installation_id` enumerates which founders connected which
    // GitHub orgs. Per RLS-policy `Users can read own profile` (auth.uid() = id),
    // a cross-founder probe must return zero rows.
    test("users: A's JWT cannot read B's users row (RLS deny via auth.uid()=id)", async () => {
      const { data, error } = await aClient
        .from("users")
        .select("workspace_path, repo_status, github_installation_id")
        .eq("id", userB.id);
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    // Per user-impact-reviewer FINDING 4 (#3244): team_names is a known
    // prior-incident surface (`2026-04-12-silent-rls-failures-in-team-names`).
    // PR-B's sendUserMessage routing path reads team_names under tenant client.
    test("team_names: A's JWT cannot read B's custom names (RLS deny)", async () => {
      const { data, error } = await aClient
        .from("team_names")
        .select("custom_name")
        .eq("user_id", userB.id);
      expect(error).toBeNull();
      expect(data).toEqual([]);
    });

    // Per user-impact-reviewer FINDING 3 (#3244): the conversations RLS
    // policy on PR-B's RLS-audit (plan §94) lacks `WITH CHECK` — `USING`
    // governs both read AND write. A future maintainer adding `WITH CHECK
    // (true)` "to be explicit" would silently defeat write-side isolation.
    // This test documents the invariant by asserting cross-founder UPDATE
    // affects zero rows under tenant JWT.
    test("conversations: A's JWT cannot UPDATE B's conversation (RLS deny via USING)", async () => {
      const { data, error } = await aClient
        .from("conversations")
        .update({ status: "failed" })
        .eq("id", bConversationId)
        .select("id");
      // RLS-filtered UPDATE returns [] (zero rows affected). PostgREST
      // returns 200, no error — same shape as RLS-filtered SELECT.
      expect(error).toBeNull();
      expect(data).toEqual([]);

      // Verify B's conversation status is unchanged.
      const { data: stillThere } = await service
        .from("conversations")
        .select("id, status")
        .eq("id", bConversationId)
        .maybeSingle();
      expect(stillThere?.id).toBe(bConversationId);
      expect(stillThere?.status).not.toBe("failed");
    });

    test("audit-row write under tenant client is rejected (write_byok_audit is service-role only)", async () => {
      // The audit-row writer is intentionally NOT exposed to tenantClient;
      // founder JWTs must NOT be able to insert audit rows directly.
      const { error } = await aClient.rpc("write_byok_audit", {
        p_invocation_id: "00000000-0000-0000-0000-000000000001",
        p_founder_id: userA.id,
        p_agent_role: "test",
        p_token_count: 1,
        p_unit_cost_cents: 1,
      });
      // PostgREST returns 42501 (insufficient_privilege) when role lacks EXECUTE.
      expect(error).not.toBeNull();
      expect(error!.code === "42501" || /permission/i.test(error!.message)).toBe(
        true,
      );
    });

    test("precheck_jwt_mint under tenant client is rejected (RPC is service-role only)", async () => {
      const { error } = await aClient.rpc("precheck_jwt_mint", {
        p_founder_id: userA.id,
        p_ttl_sec: 600,
      });
      expect(error).not.toBeNull();
      expect(error!.code === "42501" || /permission/i.test(error!.message)).toBe(
        true,
      );
    });
  },
);
