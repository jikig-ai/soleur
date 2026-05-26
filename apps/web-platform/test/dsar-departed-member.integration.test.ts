/**
 * DSAR departed-workspace-member coverage — Phase 3 integration test
 * (issue #4230, PR #4294, plan
 * `2026-05-22-feat-dsar-departed-member-coverage-plan.md`).
 *
 * AC6: golden-fixture end-to-end test asserting that after a
 * workspace member is removed via `remove_workspace_member`, their
 * DSAR bundle still contains:
 *   (a) workspace metadata for the workspace they left
 *       (Approach A — workspaceIds UNION with historical attestations)
 *   (b) the `workspace_member_removals` row recording the removal event
 *       (Approach B — new WORM ledger)
 *   (c) BOTH invitee-side AND inviter-side attestation rows for the
 *       departed user (Kieran P1-1 — .or() filter + two-arm
 *       assertReadScope)
 *   (d) post-removal `exportSqlTable` succeeds for the removed user
 *       (no CrossTenantViolation; no PGRST205; bundle is complete)
 *
 * AC2 (RPC failure propagation — Kieran P0-2): the INSERT into
 * `workspace_member_removals` lives inside the same SECURITY DEFINER
 * body as the DELETE from `workspace_members`. plpgsql function
 * semantics guarantee that any uncaught exception (e.g., FK violation
 * on `removed_user_id`) aborts and rolls back ALL prior statements in
 * the same function body. This atomicity is **structural**, verified
 * at the migration-shape lint layer
 * (`test/supabase-migrations/062-workspace-member-removals.test.ts`
 * "AC2: INSERT precedes DELETE"). Forcing a live FK violation in this
 * test would require dropping the FK constraint or installing a
 * temporary always-raise trigger — both add dev-Supabase drift and
 * verify a property already provable from the migration shape. Lint
 * is the cheaper gate.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1 (consistent with the existing
 * dsar-export-workspace-tables.integration.test.ts gate so a single
 * env var enables the whole team-workspace integration surface). Run
 * from apps/web-platform:
 *
 *   doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/dsar-departed-member.integration.test.ts
 *
 * Synthetic-fixture invariant per `cq-test-fixtures-synthesized-only`:
 * uses the shared `workspace-members-fixtures.ts` helper whose emails
 * match `^workspace-fixture-[a-f0-9]{16}@soleur\.test$`.
 *
 * Prerequisites:
 *   1. Migration 062 applied to dev-Supabase (plan §Sharp Edge says
 *      do NOT apply ahead of main — this test is .skipIf-gated so it
 *      runs only when an operator has explicitly enabled it post-apply).
 *   2. Workspace primitives present on dev (organizations,
 *      workspace_members, workspace_member_attestations,
 *      workspace_member_removals). Currently blocked on #4325
 *      (dev drift: 053/058 tracked but tables missing).
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import {
  createSharedWorkspaceMembers,
  tearDownSharedWorkspace,
  type SharedWorkspaceFixture,
} from "@/test/helpers/workspace-members-fixtures";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

function requireEnv(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing env: ${key}`);
  return v;
}

// PostgREST schema-cache readiness flag per learning
// 2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md §1.
// If migration 062 was just applied via the direct-pg pooler, supabase-js
// may return PGRST205 until the natural ~10-min poll cycle — skip rather
// than fail.
let SCHEMA_CACHE_READY: boolean | null = null;

describe.skipIf(!INTEGRATION_ENABLED)(
  "DSAR departed-member coverage (#4230, AC6)",
  () => {
    let service: SupabaseClient;
    let fixture: SharedWorkspaceFixture;
    // Slot 0 = owner (Jean); 1 = member who will be removed (Harry);
    // 2 = third member Harry invites (Bob) so Harry accrues an
    // inviter-side attestation row before he's removed.
    let jean: SharedWorkspaceFixture["members"][number];
    let harry: SharedWorkspaceFixture["members"][number];
    let bob: SharedWorkspaceFixture["members"][number];

    beforeAll(async () => {
      service = createClient(
        requireEnv("SUPABASE_URL"),
        requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
        { auth: { persistSession: false, autoRefreshToken: false } },
      );

      // Probe schema cache for the new table.
      const { error: probeErr } = await service
        .from("workspace_member_removals")
        .select("id")
        .limit(0);
      if (probeErr && (probeErr as { code?: string }).code === "PGRST205") {
        SCHEMA_CACHE_READY = false;
        console.warn(
          "[dsar-departed-member] SKIP: PostgREST schema cache stale " +
            "(PGRST205 for workspace_member_removals). Wait for natural " +
            "poll cycle or reload via Supabase Management API.",
        );
        return;
      }
      SCHEMA_CACHE_READY = true;

      // Jean (owner) + Harry (member) + Bob (member-to-be-invited-by-Harry).
      fixture = await createSharedWorkspaceMembers(service, 3);
      jean = fixture.members[0];
      harry = fixture.members[1];
      bob = fixture.members[2];

      // Synthesize one invitee-side attestation row for Harry
      // (workspace_member_attestations.invitee_user_id = Harry).
      // The shared fixture inserts the workspace_members row with
      // attestation_id=NULL; here we append the WORM attestation row
      // so the symmetric-export test has something to find.
      const { error: attHarryErr } = await service
        .from("workspace_member_attestations")
        .insert({
          workspace_id: fixture.workspaceId,
          inviter_user_id: jean.userId,
          invitee_user_id: harry.userId,
          attestation_text: "Harry accepted Jean's invite (fixture)",
          ip_hash: "fixture-ip-hash-harry",
          user_agent: "fixture-ua",
        });
      if (attHarryErr) {
        throw new Error(
          `attestation insert (Harry as invitee) failed: ${attHarryErr.message}`,
        );
      }

      // Synthesize one inviter-side attestation row for Harry
      // (workspace_member_attestations.inviter_user_id = Harry). This
      // is the row that AC4's two-arm assertReadScope + .or() change
      // must recover — under the pre-#4230 code, Harry's DSAR bundle
      // would miss this row entirely.
      const { error: attBobErr } = await service
        .from("workspace_member_attestations")
        .insert({
          workspace_id: fixture.workspaceId,
          inviter_user_id: harry.userId,
          invitee_user_id: bob.userId,
          attestation_text: "Bob accepted Harry's invite (fixture)",
          ip_hash: "fixture-ip-hash-bob",
          user_agent: "fixture-ua",
        });
      if (attBobErr) {
        throw new Error(
          `attestation insert (Harry as inviter) failed: ${attBobErr.message}`,
        );
      }

      // Jean (owner) removes Harry via the SECURITY DEFINER RPC. The
      // RPC's INSERT into workspace_member_removals fires inside the
      // same body as the DELETE — atomic.
      //
      // The RPC pulls v_caller_user_id from auth.uid(); the service
      // client bypasses PostgREST's role-switching, so we need to
      // either (a) mint a runtime JWT for Jean and call via an
      // anon-role client, or (b) impersonate via the auth header. The
      // existing dsar-export-workspace-tables test takes path (b) by
      // setting Authorization on the request via the service client's
      // global headers.
      const jeanClient = createClient(
        requireEnv("SUPABASE_URL"),
        requireEnv("SUPABASE_ANON_KEY"),
        { auth: { persistSession: false, autoRefreshToken: false } },
      );
      // Sign Jean in to get a real user-scope JWT.
      const { data: jeanSignIn, error: jeanSignInErr } =
        await service.auth.admin.generateLink({
          type: "magiclink",
          email: jean.email,
        });
      if (jeanSignInErr || !jeanSignIn?.properties?.hashed_token) {
        throw new Error(
          `generateLink for Jean failed: ${jeanSignInErr?.message ?? "no token"}`,
        );
      }
      const { error: jeanVerifyErr } = await jeanClient.auth.verifyOtp({
        token_hash: jeanSignIn.properties.hashed_token,
        type: "magiclink",
      });
      if (jeanVerifyErr) {
        throw new Error(`verifyOtp for Jean failed: ${jeanVerifyErr.message}`);
      }

      const { error: rmErr } = await jeanClient.rpc("remove_workspace_member", {
        p_workspace_id: fixture.workspaceId,
        p_user_id: harry.userId,
      });
      if (rmErr) {
        throw new Error(
          `remove_workspace_member(harry) raised: ${rmErr.message}`,
        );
      }
    }, 120_000);

    afterAll(async () => {
      if (!fixture) return;
      // Best-effort: anonymise any workspace_member_removals rows we
      // created so the FK on removed_user_id doesn't block teardown.
      try {
        await service.rpc("anonymise_workspace_member_removals", {
          p_user_id: harry?.userId ?? "",
        });
      } catch {}
      try {
        await service.rpc("anonymise_workspace_member_removals", {
          p_user_id: jean?.userId ?? "",
        });
      } catch {}
      // Anonymise the attestation rows too — they FK to users(id) RESTRICT.
      try {
        await service.rpc("anonymise_workspace_member_attestations", {
          p_user_id: harry?.userId ?? "",
        });
      } catch {}
      try {
        await service.rpc("anonymise_workspace_member_attestations", {
          p_user_id: jean?.userId ?? "",
        });
      } catch {}
      try {
        await service.rpc("anonymise_workspace_member_attestations", {
          p_user_id: bob?.userId ?? "",
        });
      } catch {}
      await tearDownSharedWorkspace(service, fixture);
    }, 120_000);

    test("AC6(d): Harry's DSAR export pipeline runs end-to-end post-removal (no CrossTenantViolation)", async () => {
      if (SCHEMA_CACHE_READY === false) return;
      const { exportSqlTable } = await import("@/server/dsar-export");
      const controller = new AbortController();
      // Must not throw. The Approach A + B + .or() changes ensure
      // pipeline traversal succeeds even though Harry no longer has a
      // workspace_members row.
      const { randomBytes } = await import("node:crypto");
      const tables = await exportSqlTable(harry.userId, randomBytes(32), controller.signal);
      expect(tables.length).toBeGreaterThan(0);
    }, 60_000);

    test("AC6(b): Harry's bundle contains his workspace_member_removals row", async () => {
      if (SCHEMA_CACHE_READY === false) return;
      const { exportSqlTable } = await import("@/server/dsar-export");
      const controller = new AbortController();
      const { randomBytes } = await import("node:crypto");
      const tables = await exportSqlTable(harry.userId, randomBytes(32), controller.signal);
      const removals = tables.find((t) => t.table === "workspace_member_removals");
      expect(removals).toBeDefined();
      expect(removals!.rows.length).toBeGreaterThanOrEqual(1);
      const row = removals!.rows.find(
        (r) =>
          (r as { workspace_id?: string }).workspace_id === fixture.workspaceId &&
          (r as { removed_user_id?: string }).removed_user_id === harry.userId,
      );
      expect(row).toBeDefined();
      expect((row as { removed_by_user_id?: string }).removed_by_user_id).toBe(
        jean.userId,
      );
    }, 60_000);

    test("AC6(a): Harry's bundle contains workspace metadata for Jean's workspace via Approach-A UNION", async () => {
      if (SCHEMA_CACHE_READY === false) return;
      const { exportSqlTable } = await import("@/server/dsar-export");
      const controller = new AbortController();
      const { randomBytes } = await import("node:crypto");
      const tables = await exportSqlTable(harry.userId, randomBytes(32), controller.signal);
      const workspaces = tables.find((t) => t.table === "workspaces");
      expect(workspaces).toBeDefined();
      const left = workspaces!.rows.find(
        (r) => (r as { id?: string }).id === fixture.workspaceId,
      );
      expect(left).toBeDefined();
    }, 60_000);

    test("AC6(c) + Kieran P1-1: Harry's bundle contains BOTH invitee-side AND inviter-side attestation rows", async () => {
      if (SCHEMA_CACHE_READY === false) return;
      const { exportSqlTable } = await import("@/server/dsar-export");
      const controller = new AbortController();
      const { randomBytes } = await import("node:crypto");
      const tables = await exportSqlTable(harry.userId, randomBytes(32), controller.signal);
      const attestations = tables.find(
        (t) => t.table === "workspace_member_attestations",
      );
      expect(attestations).toBeDefined();
      const inviteeSide = attestations!.rows.find(
        (r) => (r as { invitee_user_id?: string }).invitee_user_id === harry.userId,
      );
      const inviterSide = attestations!.rows.find(
        (r) => (r as { inviter_user_id?: string }).inviter_user_id === harry.userId,
      );
      expect(inviteeSide).toBeDefined();
      expect(inviterSide).toBeDefined();
      // assertReadScope two-arm: each row's owner field MUST match
      // Harry on either invitee_user_id OR inviter_user_id.
      for (const row of attestations!.rows) {
        const r = row as {
          invitee_user_id?: string;
          inviter_user_id?: string;
        };
        expect(
          r.invitee_user_id === harry.userId ||
            r.inviter_user_id === harry.userId,
        ).toBe(true);
      }
    }, 60_000);
  },
);
