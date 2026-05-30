/**
 * byok_delegations live-DB integration tests (#4232 PR-A Phase 4.C).
 *
 * Covers the brand-survival single-user-incident threshold cases that
 * source-grep cannot:
 *   1. Cross-tenant trigger fires + raises P0001 byok_delegations:
 *      cross-tenant (R1 — Art. 33 territory).
 *   2. WORM Shape 1 attribution constraint rejects an actor outside
 *      {grantor, grantee, created_by} (DIG F1).
 *   3. WORM Shape 1 valid revoke flip via revoke_byok_delegation RPC.
 *   4. WORM Shape 3 cap-update flip with markers passes; without
 *      markers rejects (Arch A6).
 *   5. Cap upper-bound enforcement: table CHECK at $1M cents + RPC
 *      body guard (SS F2).
 *   6. resolve_byok_key_owner own-key precedence + delegation routing.
 *   7. Multi-workspace resolver regression: explicit p_workspace_id
 *      returns only that workspace's delegation (DIG F3).
 *   8. Member-departure cascade trigger sets revocation_reason =
 *      'member_departed' + revoked_by_user_id = OLD.user_id (satisfies
 *      Shape 1 attribution).
 *   9. anonymise_byok_delegations: active rows transition Shape 1
 *      (revocation_reason = 'art_17_anonymise') THEN Shape 2 (nulls
 *      identity + workspace + actors) in a single txn (SS F7).
 *
 * Filename: `.tenant-isolation.test.ts` suffix is load-bearing for the
 * path filter at `.github/workflows/tenant-integration.yml`. Opt-in
 * via TENANT_INTEGRATION_TEST=1.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     npm run test:ci -- test/server/byok-delegations.tenant-isolation.test.ts --project unit
 *
 * Synthesized fixtures only (cq-test-fixtures-synthesized-only).
 * WORM-protected rows accumulate as orphan rows per closed-preview
 * acceptance pattern (mirrors byok-kill-switch precedent).
 */

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "node:crypto";
import { BYOK_SIDE_LETTER_VERSION } from "@/server/byok-side-letter";

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
  if (!value) throw new Error(`[byok-delegations] ${name} is required`);
  return value;
}

interface SyntheticUser {
  id: string;
  email: string;
  workspaceId: string;
}

async function createSyntheticUser(
  service: SupabaseClient,
): Promise<SyntheticUser> {
  const email = syntheticEmail();
  assertSynthetic(email);
  const { data, error } = await service.auth.admin.createUser({
    email,
    password: randomBytes(16).toString("hex"),
    email_confirm: true,
  });
  expect(error, `createUser(${email}) failed`).toBeNull();
  const id = data.user?.id ?? "";
  expect(id).toBeTruthy();

  // handle_new_user trigger (mig 053 §1.1.8) auto-creates a workspace
  // + workspace_members row for solo users. Read back the workspace_id
  // so tests can grant against the correct workspace.
  const { data: wm, error: wmErr } = await service
    .from("workspace_members")
    .select("workspace_id")
    .eq("user_id", id)
    .limit(1)
    .maybeSingle();
  expect(wmErr, `workspace_members lookup for ${email}`).toBeNull();
  expect(wm?.workspace_id, `workspace_id for ${email}`).toBeTruthy();

  return { id, email, workspaceId: wm!.workspace_id as string };
}

async function addMember(
  service: SupabaseClient,
  workspaceId: string,
  userId: string,
): Promise<void> {
  // service-role bypasses RLS. workspace_members.role is NOT NULL
  // CHECK IN ('owner','member') per mig 053; 'member' is the
  // canonical non-creator role.
  const { error } = await service
    .from("workspace_members")
    .insert({ workspace_id: workspaceId, user_id: userId, role: "member" });
  expect(error, `addMember(${userId} → ${workspaceId})`).toBeNull();
}

// resolve_byok_key_owner Gate 1 (mig 083) only resolves a delegation if a
// current-version acceptance row exists for the GRANTEE. Grant ≠ acceptance
// by design (acceptance is the grantee's separate consent act), so the
// grant→resolve ACs must seed it. Mirrors the canonical insert at
// app/api/workspace/delegations/accept/route.ts via the service-role client
// (the integration harness has no authenticated grantee session). user_id is
// the GRANTEE (matches the resolver clause a.user_id = bd.grantee_user_id);
// side_letter_version is imported (not hardcoded) so a future version bump
// can't silently re-break this test with the same 0-rows signature.
async function seedAcceptance(
  service: SupabaseClient,
  delegationId: string,
  granteeUserId: string,
): Promise<void> {
  const { error } = await service
    .from("byok_delegation_acceptances")
    .insert({
      user_id: granteeUserId,
      delegation_id: delegationId,
      side_letter_version: BYOK_SIDE_LETTER_VERSION,
    });
  expect(error, `seedAcceptance(${delegationId})`).toBeNull();
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "byok_delegations (integration)",
  () => {
    let service: SupabaseClient;
    let alice: SyntheticUser; // grantor in workspace W_A
    let bob: SyntheticUser; // grantee in W_A (added below)
    let carol: SyntheticUser; // member of her own workspace W_C (cross-tenant)
    let dave: SyntheticUser; // second grantee for multi-workspace test (in W_A and W_D)

    beforeAll(async () => {
      const url = requireEnv("SUPABASE_URL");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      service = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      [alice, bob, carol, dave] = await Promise.all([
        createSyntheticUser(service),
        createSyntheticUser(service),
        createSyntheticUser(service),
        createSyntheticUser(service),
      ]);

      // Add bob + dave to alice's workspace W_A so cross-workspace +
      // same-workspace trigger logic both exercise. carol stays solo
      // in her own workspace (cross-tenant fixture).
      await addMember(service, alice.workspaceId, bob.id);
      await addMember(service, alice.workspaceId, dave.id);
    }, 60_000);

    afterAll(async () => {
      // byok_delegations rows for synthetic users are WORM-protected;
      // identity FKs are ON DELETE RESTRICT; auth.admin.deleteUser
      // would 23503 with our test rows present. Per the byok-kill-switch
      // precedent: per-run isolation via random email is sufficient for
      // closed-preview alpha. Orphan rows accumulate; long-running CI
      // adopts the synthetic-fixture sweeper deferred-scope-out #3934.
    }, 30_000);

    it("AC-cross-tenant: trigger fires when grantor and workspace span tenants (R1)", async () => {
      // alice grants TO carol IN W_A. carol is NOT a member of W_A,
      // so byok_delegations_check_same_workspace must raise P0001
      // with `byok_delegations:cross-tenant`.
      const { error } = await service.rpc("grant_byok_delegation", {
        p_grantor_user_id: alice.id,
        p_grantee_user_id: carol.id, // cross-tenant — NOT a member of W_A
        p_workspace_id: alice.workspaceId,
        p_daily_usd_cap_cents: 2000,
        p_hourly_usd_cap_cents: 500,
        p_expires_at: null,
        p_actor_user_id: alice.id,
      });
      expect(error, "expected P0001 cross-tenant").not.toBeNull();
      expect(error?.message).toMatch(/byok_delegations:cross-tenant/);
      expect(error?.message).toMatch(/grantee/);
    });

    it("AC-cap-upper-bound: $1,000,001 cents rejected at RPC body guard (SS F2)", async () => {
      const { error } = await service.rpc("grant_byok_delegation", {
        p_grantor_user_id: alice.id,
        p_grantee_user_id: bob.id,
        p_workspace_id: alice.workspaceId,
        p_daily_usd_cap_cents: 1_000_001, // ceiling is 1_000_000
        p_hourly_usd_cap_cents: 1,
        p_expires_at: null,
        p_actor_user_id: alice.id,
      });
      expect(error, "expected cap-ceiling rejection").not.toBeNull();
      expect(error?.message).toMatch(/daily_usd_cap_cents out of range/);
      // SQLSTATE 22003 (numeric_value_out_of_range) per the RPC body.
      expect(error?.code).toBe("22003");
    });

    it("AC-cap-upper-bound: hourly > daily rejected at RPC body guard", async () => {
      const { error } = await service.rpc("grant_byok_delegation", {
        p_grantor_user_id: alice.id,
        p_grantee_user_id: bob.id,
        p_workspace_id: alice.workspaceId,
        p_daily_usd_cap_cents: 1000,
        p_hourly_usd_cap_cents: 1001, // > daily
        p_expires_at: null,
        p_actor_user_id: alice.id,
      });
      expect(error, "expected hourly > daily rejection").not.toBeNull();
      expect(error?.message).toMatch(/hourly_usd_cap_cents out of range/);
      expect(error?.code).toBe("22003");
    });

    it("AC-resolver-own-key: caller with own api_keys row returns (caller, NULL)", async () => {
      // alice has no api_keys row + no active delegation → resolver
      // returns no row. Then we seed an api_keys row and re-resolve.
      const probe1 = await service.rpc("resolve_byok_key_owner", {
        p_caller_user_id: alice.id,
        p_workspace_id: alice.workspaceId,
      });
      expect(probe1.error).toBeNull();
      // No row is acceptable shape — supabase-js returns empty array.
      expect(probe1.data).toEqual([]);

      const { error: keyErr } = await service.from("api_keys").insert({
        user_id: alice.id,
        provider: "anthropic",
        encrypted_key: randomBytes(32).toString("base64"),
        iv: randomBytes(12).toString("base64"),
        auth_tag: randomBytes(16).toString("base64"),
        key_version: 1,
        is_valid: true,
      });
      expect(keyErr, "seed alice api_keys").toBeNull();

      const probe2 = await service.rpc("resolve_byok_key_owner", {
        p_caller_user_id: alice.id,
        p_workspace_id: alice.workspaceId,
      });
      expect(probe2.error).toBeNull();
      const rows2 = (probe2.data ?? []) as Array<{
        key_owner_user_id: string;
        delegation_id: string | null;
      }>;
      expect(rows2.length, "resolver returns one row").toBe(1);
      expect(rows2[0].key_owner_user_id).toBe(alice.id);
      expect(rows2[0].delegation_id).toBeNull();
    });

    it("AC-resolver-delegation: grantee with no own key + active delegation returns (grantor, delegation_id)", async () => {
      // Grant alice → bob in W_A. bob has no api_keys row.
      const { data: grantData, error: grantErr } = await service.rpc(
        "grant_byok_delegation",
        {
          p_grantor_user_id: alice.id,
          p_grantee_user_id: bob.id,
          p_workspace_id: alice.workspaceId,
          p_daily_usd_cap_cents: 1000,
          p_hourly_usd_cap_cents: 250,
          p_expires_at: null,
          p_actor_user_id: alice.id,
        },
      );
      expect(grantErr).toBeNull();
      const delegationId = grantData as unknown as string;
      expect(delegationId).toBeTruthy();

      // bob (grantee) must record consent before the resolver returns the row.
      await seedAcceptance(service, delegationId, bob.id);

      const { data, error } = await service.rpc("resolve_byok_key_owner", {
        p_caller_user_id: bob.id,
        p_workspace_id: alice.workspaceId,
      });
      expect(error).toBeNull();
      const rows = (data ?? []) as Array<{
        key_owner_user_id: string;
        delegation_id: string | null;
      }>;
      expect(rows.length, "resolver returns one row").toBe(1);
      expect(rows[0].key_owner_user_id).toBe(alice.id);
      expect(rows[0].delegation_id).toBe(delegationId);
    });

    it("AC-multi-workspace (DIG F3): explicit p_workspace_id returns only that workspace's delegation", async () => {
      // dave is a member of W_A (added in beforeAll). Create a second
      // workspace W_D for dave + an organization; service-role
      // bypasses RLS so we can insert directly. handle_new_user
      // wouldn't help here (already fired for dave). Build the
      // workspace via the dedicated RPC if available, else direct
      // insert.
      //
      // Simplification: dave is grantee of TWO active delegations —
      // one from alice in W_A, one from carol in W_C — and we
      // resolve with explicit p_workspace_id for each to assert the
      // routing.
      await addMember(service, carol.workspaceId, dave.id);
      const grantA = await service.rpc("grant_byok_delegation", {
        p_grantor_user_id: alice.id,
        p_grantee_user_id: dave.id,
        p_workspace_id: alice.workspaceId,
        p_daily_usd_cap_cents: 1000,
        p_hourly_usd_cap_cents: 250,
        p_expires_at: null,
        p_actor_user_id: alice.id,
      });
      expect(grantA.error).toBeNull();
      const idA = grantA.data as unknown as string;

      const grantC = await service.rpc("grant_byok_delegation", {
        p_grantor_user_id: carol.id,
        p_grantee_user_id: dave.id,
        p_workspace_id: carol.workspaceId,
        p_daily_usd_cap_cents: 2000,
        p_hourly_usd_cap_cents: 500,
        p_expires_at: null,
        p_actor_user_id: carol.id,
      });
      expect(grantC.error).toBeNull();
      const idC = grantC.data as unknown as string;

      // dave (grantee) consents to BOTH delegations before resolving each.
      await seedAcceptance(service, idA, dave.id);
      await seedAcceptance(service, idC, dave.id);

      const inA = await service.rpc("resolve_byok_key_owner", {
        p_caller_user_id: dave.id,
        p_workspace_id: alice.workspaceId,
      });
      expect(inA.error).toBeNull();
      const rowsA = (inA.data ?? []) as Array<{ delegation_id: string }>;
      expect(rowsA.length).toBe(1);
      expect(rowsA[0].delegation_id).toBe(idA);

      const inC = await service.rpc("resolve_byok_key_owner", {
        p_caller_user_id: dave.id,
        p_workspace_id: carol.workspaceId,
      });
      expect(inC.error).toBeNull();
      const rowsC = (inC.data ?? []) as Array<{ delegation_id: string }>;
      expect(rowsC.length).toBe(1);
      expect(rowsC[0].delegation_id).toBe(idC);

      // Cross-check: A's delegation MUST NOT appear when resolving in W_C.
      expect(rowsA[0].delegation_id).not.toBe(idC);
    });

    it("AC-worm-shape1-attribution (DIG F1): revoke with actor outside (grantor, grantee, created_by) rejected", async () => {
      // Fresh grantee — partial unique on (grantor, grantee, workspace)
      // WHERE revoked_at IS NULL forbids re-granting alice→bob while
      // the previous test's grant is active.
      const granteeUser = await createSyntheticUser(service);
      await addMember(service, alice.workspaceId, granteeUser.id);
      const { data: id, error } = await service.rpc(
        "grant_byok_delegation",
        {
          p_grantor_user_id: alice.id,
          p_grantee_user_id: granteeUser.id,
          p_workspace_id: alice.workspaceId,
          p_daily_usd_cap_cents: 1000,
          p_hourly_usd_cap_cents: 250,
          p_expires_at: null,
          p_actor_user_id: alice.id,
        },
      );
      expect(error).toBeNull();
      const delegationId = id as unknown as string;

      // carol is neither grantor (alice) nor grantee (bob) nor
      // created_by (alice). The RPC catches this with 42501 before
      // the WORM trigger; assert the RPC body's check fires.
      const { error: revokeErr } = await service.rpc(
        "revoke_byok_delegation",
        {
          p_delegation_id: delegationId,
          p_actor_user_id: carol.id, // cross-tenant attacker
          p_reason: "admin_revoke",
        },
      );
      expect(revokeErr).not.toBeNull();
      expect(revokeErr?.code).toBe("42501");
      expect(revokeErr?.message).toMatch(/not grantor\/grantee\/created_by/);
    });

    it("AC-worm-shape1-valid: revoke flip by grantor succeeds + sets reason 'admin_revoke'", async () => {
      const granteeUser = await createSyntheticUser(service);
      await addMember(service, alice.workspaceId, granteeUser.id);
      const { data: id, error: grantErr } = await service.rpc(
        "grant_byok_delegation",
        {
          p_grantor_user_id: alice.id,
          p_grantee_user_id: granteeUser.id,
          p_workspace_id: alice.workspaceId,
          p_daily_usd_cap_cents: 1000,
          p_hourly_usd_cap_cents: 250,
          p_expires_at: null,
          p_actor_user_id: alice.id,
        },
      );
      expect(grantErr).toBeNull();
      const delegationId = id as unknown as string;

      const { error: revokeErr } = await service.rpc(
        "revoke_byok_delegation",
        {
          p_delegation_id: delegationId,
          p_actor_user_id: alice.id,
          p_reason: "admin_revoke",
        },
      );
      expect(revokeErr).toBeNull();

      const { data: row, error: readErr } = await service
        .from("byok_delegations")
        .select(
          "revoked_at, revoked_by_user_id, revocation_reason, grantor_user_id, grantee_user_id",
        )
        .eq("id", delegationId)
        .single();
      expect(readErr).toBeNull();
      expect(row?.revoked_at).not.toBeNull();
      expect(row?.revoked_by_user_id).toBe(alice.id);
      expect(row?.revocation_reason).toBe("admin_revoke");
      // Identity columns must be unchanged by revoke flip.
      expect(row?.grantor_user_id).toBe(alice.id);
      expect(row?.grantee_user_id).toBe(granteeUser.id);
    });

    it("AC-revoke-reserved-reason (SS F9): revoke RPC rejects 'member_departed' (trigger-reserved)", async () => {
      const granteeUser = await createSyntheticUser(service);
      await addMember(service, alice.workspaceId, granteeUser.id);
      const { data: id, error: grantErr } = await service.rpc(
        "grant_byok_delegation",
        {
          p_grantor_user_id: alice.id,
          p_grantee_user_id: granteeUser.id,
          p_workspace_id: alice.workspaceId,
          p_daily_usd_cap_cents: 1000,
          p_hourly_usd_cap_cents: 250,
          p_expires_at: null,
          p_actor_user_id: alice.id,
        },
      );
      expect(grantErr).toBeNull();
      const delegationId = id as unknown as string;

      const { error } = await service.rpc("revoke_byok_delegation", {
        p_delegation_id: delegationId,
        p_actor_user_id: alice.id,
        p_reason: "member_departed", // reserved for trigger path
      });
      expect(error).not.toBeNull();
      expect(error?.code).toBe("22023");
      expect(error?.message).toMatch(/reserved for trigger\/cascade/);
    });

    it("AC-worm-delete: DELETE on byok_delegations rejected", async () => {
      const granteeUser = await createSyntheticUser(service);
      await addMember(service, alice.workspaceId, granteeUser.id);
      const { data: id, error: grantErr } = await service.rpc(
        "grant_byok_delegation",
        {
          p_grantor_user_id: alice.id,
          p_grantee_user_id: granteeUser.id,
          p_workspace_id: alice.workspaceId,
          p_daily_usd_cap_cents: 1000,
          p_hourly_usd_cap_cents: 250,
          p_expires_at: null,
          p_actor_user_id: alice.id,
        },
      );
      expect(grantErr).toBeNull();
      const delegationId = id as unknown as string;

      const { error } = await service
        .from("byok_delegations")
        .delete()
        .eq("id", delegationId);
      expect(error).not.toBeNull();
      expect(error?.message).toMatch(/append-only/);
    });

    it("AC-member-departure: DELETE workspace_members fires AFTER DELETE trigger → row revoked + reason='member_departed'", async () => {
      const granteeUser = await createSyntheticUser(service);
      await addMember(service, alice.workspaceId, granteeUser.id);
      const { data: id, error: grantErr } = await service.rpc(
        "grant_byok_delegation",
        {
          p_grantor_user_id: alice.id,
          p_grantee_user_id: granteeUser.id,
          p_workspace_id: alice.workspaceId,
          p_daily_usd_cap_cents: 1000,
          p_hourly_usd_cap_cents: 250,
          p_expires_at: null,
          p_actor_user_id: alice.id,
        },
      );
      expect(grantErr).toBeNull();
      const delegationId = id as unknown as string;

      // Remove granteeUser from W_A. byok_delegations_on_member_delete
      // fires AFTER DELETE and sets revoked_by = OLD.user_id (which
      // IS the grantee, satisfying Shape 1 attribution).
      const { error: delErr } = await service
        .from("workspace_members")
        .delete()
        .eq("workspace_id", alice.workspaceId)
        .eq("user_id", granteeUser.id);
      expect(delErr).toBeNull();

      const { data: row, error: readErr } = await service
        .from("byok_delegations")
        .select("revoked_at, revoked_by_user_id, revocation_reason")
        .eq("id", delegationId)
        .single();
      expect(readErr).toBeNull();
      expect(row?.revoked_at).not.toBeNull();
      expect(row?.revoked_by_user_id).toBe(granteeUser.id);
      expect(row?.revocation_reason).toBe("member_departed");
    });

    it("AC-hourly-cap-exceeded: check_and_record raises P0001 hourly_cap_exceeded with no audit row", async () => {
      const granteeUser = await createSyntheticUser(service);
      await addMember(service, alice.workspaceId, granteeUser.id);
      // Tight cap: $0.05/hr ($5/day) so two 500-cent calls exceed
      // hourly. Daily cap stays well above so we test hourly in
      // isolation.
      const { data: id, error: grantErr } = await service.rpc(
        "grant_byok_delegation",
        {
          p_grantor_user_id: alice.id,
          p_grantee_user_id: granteeUser.id,
          p_workspace_id: alice.workspaceId,
          p_daily_usd_cap_cents: 500,
          p_hourly_usd_cap_cents: 5,
          p_expires_at: null,
          p_actor_user_id: alice.id,
        },
      );
      expect(grantErr).toBeNull();
      const delegationId = id as unknown as string;

      // First call: token_count=1 * unit_cost_cents=4 = 4 cents,
      // under the 5-cent hourly cap. Should pass.
      const ok1 = await service.rpc("check_and_record_byok_delegation_use", {
        p_delegation_id: delegationId,
        p_invocation_id: randomUUID(),
        p_token_count: 1,
        p_unit_cost_cents: 4,
        p_caller_user_id: granteeUser.id,
        p_agent_role: "test-hourly-cap",
      });
      expect(ok1.error, "call 1 passes (4 < 5)").toBeNull();

      // Second call: 4 + 2 = 6 cents > 5-cent hourly cap → P0001.
      const fail2 = await service.rpc("check_and_record_byok_delegation_use", {
        p_delegation_id: delegationId,
        p_invocation_id: randomUUID(),
        p_token_count: 1,
        p_unit_cost_cents: 2,
        p_caller_user_id: granteeUser.id,
        p_agent_role: "test-hourly-cap",
      });
      expect(fail2.error, "call 2 trips hourly cap").not.toBeNull();
      expect(fail2.error?.message).toMatch(
        /byok_delegations:hourly_cap_exceeded/,
      );

      // Verify exactly ONE audit row exists for this delegation (the
      // passing call). The cap-exceeded path raises BEFORE INSERT.
      const { data: auditRows, error: auditErr } = await service
        .from("audit_byok_use")
        .select("id, attribution_shift_reason, founder_id")
        .eq("delegation_id", delegationId);
      expect(auditErr).toBeNull();
      expect(auditRows?.length, "exactly 1 audit row (cap-exceeded skipped)").toBe(1);
      expect(auditRows![0].attribution_shift_reason, "normal attribution").toBeNull();
      expect(auditRows![0].founder_id, "audit attributes to grantor").toBe(alice.id);
    });

    it("AC-worm-shape3 (Arch A6): cap-update flip with markers passes; without markers rejects", async () => {
      const granteeUser = await createSyntheticUser(service);
      await addMember(service, alice.workspaceId, granteeUser.id);
      const { data: id, error: grantErr } = await service.rpc(
        "grant_byok_delegation",
        {
          p_grantor_user_id: alice.id,
          p_grantee_user_id: granteeUser.id,
          p_workspace_id: alice.workspaceId,
          p_daily_usd_cap_cents: 1000,
          p_hourly_usd_cap_cents: 250,
          p_expires_at: null,
          p_actor_user_id: alice.id,
        },
      );
      expect(grantErr).toBeNull();
      const delegationId = id as unknown as string;

      // Negative: cap-only change WITHOUT cap_updated_at + cap_updated_by
      // is rejected by the WORM trigger.
      const negative = await service
        .from("byok_delegations")
        .update({ daily_usd_cap_cents: 2000 })
        .eq("id", delegationId);
      expect(negative.error, "expected WORM trigger rejection").not.toBeNull();
      expect(negative.error?.message).toMatch(/append-only|only revoke flip|shapes are permitted/i);

      // Positive: cap change + cap_updated_at + cap_updated_by_user_id
      // all together passes Shape 3.
      const positive = await service
        .from("byok_delegations")
        .update({
          daily_usd_cap_cents: 2000,
          hourly_usd_cap_cents: 500,
          cap_updated_at: new Date().toISOString(),
          cap_updated_by_user_id: alice.id,
        })
        .eq("id", delegationId);
      expect(positive.error, "Shape 3 valid markers should pass").toBeNull();

      // Verify the row reflects the new caps + markers.
      const { data: row, error: readErr } = await service
        .from("byok_delegations")
        .select(
          "daily_usd_cap_cents, hourly_usd_cap_cents, cap_updated_at, cap_updated_by_user_id, grantor_user_id, revoked_at",
        )
        .eq("id", delegationId)
        .single();
      expect(readErr).toBeNull();
      expect(row?.daily_usd_cap_cents).toBe(2000);
      expect(row?.hourly_usd_cap_cents).toBe(500);
      expect(row?.cap_updated_at).not.toBeNull();
      expect(row?.cap_updated_by_user_id).toBe(alice.id);
      // Identity + revoke state must be preserved through Shape 3.
      expect(row?.grantor_user_id).toBe(alice.id);
      expect(row?.revoked_at).toBeNull();
    });

    it("AC-anonymise-active-row-guard (SS F7): Shape 1 revoke + Shape 2 nulls in one txn", async () => {
      // Fresh user so anonymise touches only their rows.
      const erin = await createSyntheticUser(service);
      await addMember(service, alice.workspaceId, erin.id);

      const { data: id, error: grantErr } = await service.rpc(
        "grant_byok_delegation",
        {
          p_grantor_user_id: alice.id,
          p_grantee_user_id: erin.id,
          p_workspace_id: alice.workspaceId,
          p_daily_usd_cap_cents: 1000,
          p_hourly_usd_cap_cents: 250,
          p_expires_at: null,
          p_actor_user_id: alice.id,
        },
      );
      expect(grantErr).toBeNull();
      const delegationId = id as unknown as string;

      const { error: anonErr } = await service.rpc(
        "anonymise_byok_delegations",
        { p_user_id: erin.id },
      );
      expect(anonErr).toBeNull();

      const { data: row, error: readErr } = await service
        .from("byok_delegations")
        .select(
          "grantor_user_id, grantee_user_id, workspace_id, created_by_user_id, revoked_by_user_id, revoked_at, revocation_reason",
        )
        .eq("id", delegationId)
        .single();
      expect(readErr).toBeNull();

      // Shape 2 outcome: identity + workspace + revoked_by all NULL.
      expect(row?.grantor_user_id).toBeNull();
      expect(row?.grantee_user_id).toBeNull();
      expect(row?.workspace_id).toBeNull();
      expect(row?.created_by_user_id).toBeNull();
      expect(row?.revoked_by_user_id).toBeNull();
      // Shape 1 outcome captured in retention: revoked_at + reason
      // preserved through Shape 2 anonymise.
      expect(row?.revoked_at).not.toBeNull();
      expect(row?.revocation_reason).toBe("art_17_anonymise");
    });
  },
);
