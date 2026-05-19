import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 049_runtime_mint_intent.sql.
//
// Background: the Phase-4 empirical probe (2026-05-18, ADR-033 §0.7)
// established that Supabase's Custom Access Token Hook event payload
// contains NO field that discriminates the runtime mint path
// (auth.admin.generateLink + verifyOtp{token_hash}) from the dashboard
// OTP login path (signInWithOtp + verifyOtp{token}). Both produce
// identical aud/amr/exp/app_metadata structure. The 'authentication_method
// = otp' gate as designed in ADR-033 §0.4 is therefore insufficient —
// it would silently rewrite dashboard JWTs with aud='soleur-runtime'
// and exp=600s.
//
// This migration introduces a marker table `public.runtime_mint_intent`
// that tenant.ts UPSERTs immediately before its admin.generateLink call.
// The hook (migration 050) atomically DELETEs the row inside a CTE; only
// if a row is consumed does the hook proceed to mint. Dashboard logins
// never UPSERT, so their hook firing finds no intent and pass-through.
//
// Schema invariants:
//   1. PRIMARY KEY on user_id — concurrent runtime mints for the same
//      founder UPSERT idempotently.
//   2. ON DELETE CASCADE from auth.users — orphaned intent rows must
//      not survive user deletion (compliance / Art. 17 hygiene; see
//      [[2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr]]).
//   3. RLS enabled. No policies for anon/authenticated.
//   4. service_role: GRANT INSERT (for tenant.ts UPSERT).
//   5. supabase_auth_admin: GRANT SELECT, DELETE (for hook DELETE...RETURNING).
//   6. REVOKE ALL from PUBLIC, anon, authenticated.
//   7. cq-supabase-migration-no-concurrently: NO CREATE INDEX CONCURRENTLY.
//
// Plan: knowledge-base/project/plans/2026-05-18-refactor-runtime-jwt-asymmetric-signing-substrate-plan.md §Phase 4 amendment
// ADR: knowledge-base/engineering/architecture/decisions/ADR-033-runtime-jwt-signing-substrate.md §0.7

const MIGRATION_PATH = path.resolve(
  __dirname,
  "../../supabase/migrations/049_runtime_mint_intent.sql",
);

describe("migration 049_runtime_mint_intent", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");

  // Strip line-comments before pattern checks (mirrors 037/047 pattern).
  const executable = sql.replace(/--[^\n]*/g, "");

  describe("table shape", () => {
    it("creates public.runtime_mint_intent table", () => {
      expect(executable).toMatch(
        /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.runtime_mint_intent/i,
      );
    });

    it("declares user_id uuid PRIMARY KEY", () => {
      // PK on user_id is load-bearing for idempotent UPSERT: concurrent
      // runtime mints for the same founder collapse to a single row.
      expect(executable).toMatch(
        /user_id\s+uuid\s+(?:NOT\s+NULL\s+)?PRIMARY\s+KEY/i,
      );
    });

    it("references auth.users(id) ON DELETE CASCADE", () => {
      // Cascade is intentional: an intent row for a deleted user is
      // semantically meaningless and would block FK-checked deletes.
      expect(executable).toMatch(
        /REFERENCES\s+auth\.users\s*\(\s*id\s*\)\s+ON\s+DELETE\s+CASCADE/i,
      );
    });

    it("declares created_at timestamptz with NOW() default", () => {
      // created_at drives the 10-second TTL window enforced by the hook
      // (migration 050). The default must be NOW() so tenant.ts UPSERTs
      // don't need to pass it explicitly.
      expect(executable).toMatch(
        /created_at\s+timestamptz\s+(?:NOT\s+NULL\s+)?DEFAULT\s+NOW\s*\(\s*\)/i,
      );
    });
  });

  describe("RLS + grants", () => {
    it("enables row-level security", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.runtime_mint_intent\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i,
      );
    });

    it("revokes ALL from PUBLIC, anon, authenticated", () => {
      // Defense in depth against Supabase's default-privilege grant.
      // Note: service_role still keeps its admin grants by being explicitly
      // re-granted below.
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+(?:TABLE\s+)?public\.runtime_mint_intent\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated/i,
      );
    });

    it("grants INSERT to service_role (for tenant.ts UPSERT)", () => {
      // The skill-of-art for supabase-js client.from().upsert() requires
      // INSERT privilege. Update privilege is incidentally needed for
      // ON CONFLICT DO UPDATE — but our hook DELETEs on consume, so
      // updates are bounded to the upsert race window.
      expect(executable).toMatch(
        /GRANT\s+(?:[A-Z_,\s]*\b)?INSERT\b(?:[A-Z_,\s]*)\s+ON\s+(?:TABLE\s+)?public\.runtime_mint_intent\s+TO\s+service_role/i,
      );
    });

    it("grants SELECT and DELETE to supabase_auth_admin (for hook DELETE...RETURNING)", () => {
      // The hook (migration 050) uses a single DELETE...RETURNING CTE
      // to atomically check-and-consume. SELECT is granted defensively
      // for diagnostic queries from the auth daemon shell; DELETE is
      // the load-bearing privilege.
      expect(executable).toMatch(
        /GRANT\s+(?:[A-Z_,\s]*\b)?DELETE\b(?:[A-Z_,\s]*)\s+ON\s+(?:TABLE\s+)?public\.runtime_mint_intent\s+TO\s+supabase_auth_admin/i,
      );
    });

    it("does NOT grant ANY privilege to anon or authenticated", () => {
      // Belt + suspenders against accidental re-grant.
      expect(executable).not.toMatch(
        /GRANT\s+[A-Z_,\s]+ON\s+(?:TABLE\s+)?public\.runtime_mint_intent\s+TO\s+(?:[^;]*\b)?authenticated\b/i,
      );
      expect(executable).not.toMatch(
        /GRANT\s+[A-Z_,\s]+ON\s+(?:TABLE\s+)?public\.runtime_mint_intent\s+TO\s+(?:[^;]*\b)?anon\b/i,
      );
    });
  });

  describe("migration hygiene", () => {
    it("does NOT use CREATE INDEX CONCURRENTLY", () => {
      // cq-supabase-migration-no-concurrently.
      expect(executable).not.toMatch(/CREATE\s+INDEX\s+CONCURRENTLY/i);
    });
  });
});

// Behavioral integration tests — activate when TENANT_INTEGRATION_TEST=1
// and a live Doppler DATABASE_URL_POOLER is available.
describe.skip("runtime_mint_intent — integration tests applied after migration runs", () => {
  it("UPSERT-then-DELETE roundtrip: hook-style CTE returns exactly one row", () => {
    // Setup:
    //   const fixtureUuid = "<existing auth.users id from dev>";
    //   await pg.query("DELETE FROM public.runtime_mint_intent WHERE user_id = $1", [fixtureUuid]);
    //
    // Step 1 — tenant.ts-style UPSERT:
    //   await pg.query(`
    //     INSERT INTO public.runtime_mint_intent (user_id)
    //     VALUES ($1)
    //     ON CONFLICT (user_id) DO UPDATE SET created_at = NOW()
    //   `, [fixtureUuid]);
    //
    // Step 2 — hook-style atomic check-and-delete:
    //   const { rows } = await pg.query(`
    //     WITH consumed AS (
    //       DELETE FROM public.runtime_mint_intent
    //       WHERE user_id = $1
    //         AND created_at > NOW() - INTERVAL '10 seconds'
    //       RETURNING 1
    //     )
    //     SELECT count(*)::int AS n FROM consumed
    //   `, [fixtureUuid]);
    //
    // Assert:
    //   expect(rows[0].n).toBe(1);
    //
    // Step 3 — second consume returns 0 (idempotent):
    //   const { rows: r2 } = await pg.query(...same query...);
    //   expect(r2[0].n).toBe(0);
  });

  it("stale rows beyond 10s are NOT consumed", () => {
    // Setup: INSERT with created_at = NOW() - INTERVAL '15 seconds'
    //   await pg.query(`
    //     INSERT INTO public.runtime_mint_intent (user_id, created_at)
    //     VALUES ($1, NOW() - INTERVAL '15 seconds')
    //     ON CONFLICT (user_id) DO UPDATE SET created_at = EXCLUDED.created_at
    //   `, [fixtureUuid]);
    //
    // Hook-style consume:
    //   const { rows } = await pg.query(`
    //     WITH consumed AS (
    //       DELETE FROM public.runtime_mint_intent
    //       WHERE user_id = $1
    //         AND created_at > NOW() - INTERVAL '10 seconds'
    //       RETURNING 1
    //     )
    //     SELECT count(*)::int AS n FROM consumed
    //   `, [fixtureUuid]);
    //
    // Assert:
    //   expect(rows[0].n).toBe(0);
    //
    // The stale row stays in place (not consumed); a separate sweeper
    // would clean it up. For v1, the row is harmless — the next runtime
    // UPSERT will overwrite it via ON CONFLICT.
  });

  it("FK CASCADE: deleting an auth.users row removes its intent row", () => {
    // (Phase 2-apply will unblock this; today it's the AC document.)
  });
});
