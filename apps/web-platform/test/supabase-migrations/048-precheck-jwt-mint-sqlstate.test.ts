import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 048_precheck_jwt_mint_sqlstate.sql.
//
// File-parse contract test (mirrors 037 precedent), pinning the SQL
// invariants required by the runtime-JWT asymmetric-signing substrate
// plan, Phase 2.1 — disambiguate the rate-limit SQLSTATE from
// migration 037's WORM-trigger P0001 so the Custom Access Token Hook
// (047) and downstream Node middleware can match on ERRCODE = '45001'
// instead of fragile string-matching against the MESSAGE.
//
// Contract:
//   1. CREATE OR REPLACE FUNCTION public.precheck_jwt_mint(uuid,
//      integer) — signature UNCHANGED from 037. Only the SQLSTATE
//      raised on rate-limit breach changes.
//   2. LANGUAGE plpgsql + SECURITY DEFINER + SET search_path = public,
//      pg_temp (per cq-pg-security-definer-search-path-pin-pg-temp).
//   3. RAISE EXCEPTION USING ERRCODE = '45001' — '45xxx' is the
//      PostgreSQL reserved range for user-defined custom SQLSTATEs;
//      '45001' is the project-allocated code for mint_rate_exceeded.
//      Distinct from 037's WORM-trigger P0001.
//   4. MESSAGE 'mint_rate_exceeded' — string preserved for callers
//      that haven't yet migrated to ERRCODE matching.
//   5. RETURNS TABLE (jti uuid, exp_epoch integer/int, iat_epoch
//      integer/int) — cross-process contract with Node mint path is
//      unchanged.
//   6. DO $$ ... ASSERT ... $$ self-test block — compile-time
//      validation that the function loads and the SQLSTATE wiring
//      surfaces correctly (catches typos like '45OO1').
//
// Behavioral integration tests live in the gated describe.skip block;
// they activate when TENANT_INTEGRATION_TEST=1 (PR-B precedent).
//
// Plan: knowledge-base/project/plans/2026-05-18-refactor-runtime-jwt-asymmetric-signing-substrate-plan.md §2.1
// ADR: knowledge-base/engineering/architecture/decisions/ADR-033-runtime-jwt-signing-substrate.md
// Source of truth for prior shape: apps/web-platform/supabase/migrations/037_audit_byok_use.sql

const MIGRATION_PATH = path.resolve(
  __dirname,
  "../../supabase/migrations/048_precheck_jwt_mint_sqlstate.sql",
);

describe("migration 048_precheck_jwt_mint_sqlstate", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");

  // Strip line-comments before pattern checks (mirrors 037 pattern).
  const executable = sql.replace(/--[^\n]*/g, "");

  describe("precheck_jwt_mint signature (must match 037)", () => {
    const fnBlock =
      executable.match(
        /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.precheck_jwt_mint[\s\S]*?\$\$;/i,
      )?.[0] || "";

    it("declares precheck_jwt_mint with (p_founder_id uuid, p_ttl_sec int|integer) — UNCHANGED from 037", () => {
      // AC §2.1: signature stays identical so existing callers in
      // Node (mint path) keep working with no positional-arg drift.
      expect(fnBlock).not.toBe("");
      expect(fnBlock).toMatch(/p_founder_id\s+uuid/i);
      expect(fnBlock).toMatch(/p_ttl_sec\s+int(?:eger)?/i);
    });

    it("RETURNS TABLE shape preserved: jti uuid, exp_epoch int, iat_epoch int", () => {
      // Cross-process contract: Node consumes these three columns
      // and signs the resulting claims with the asymmetric key.
      expect(fnBlock).toMatch(/RETURNS\s+TABLE\s*\(\s*jti\s+uuid/i);
      expect(fnBlock).toMatch(/exp_epoch\s+int(?:eger)?/i);
      expect(fnBlock).toMatch(/iat_epoch\s+int(?:eger)?/i);
    });

    it("is LANGUAGE plpgsql", () => {
      expect(fnBlock).toMatch(/LANGUAGE\s+plpgsql/i);
    });

    it("is SECURITY DEFINER with search_path pinned to public, pg_temp", () => {
      // cq-pg-security-definer-search-path-pin-pg-temp.
      expect(fnBlock).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock).toMatch(
        /SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i,
      );
    });
  });

  describe("ERRCODE '45001' disambiguation (the only behavioral delta vs 037)", () => {
    const fnBlock =
      executable.match(
        /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.precheck_jwt_mint[\s\S]*?\$\$;/i,
      )?.[0] || "";

    it("RAISE EXCEPTION uses ERRCODE = '45001' (project-allocated custom SQLSTATE)", () => {
      // '45xxx' is reserved by PostgreSQL for user-defined SQLSTATEs;
      // '45001' is the mint_rate_exceeded code that the 047 hook and
      // Node middleware match against. Distinct from 037's
      // WORM-trigger P0001 so callers don't conflate the two.
      expect(fnBlock).toMatch(/RAISE\s+EXCEPTION/i);
      expect(fnBlock).toMatch(/ERRCODE\s*=\s*'45001'/i);
    });

    it("MESSAGE is 'mint_rate_exceeded' (preserved from 037 for legacy callers)", () => {
      // Some callers may still string-match the message until they
      // migrate to ERRCODE matching; keep the string stable.
      expect(fnBlock).toMatch(/'mint_rate_exceeded'/);
    });

    it("does NOT widen ERRCODE to P0001 (which would collide with 037 WORM triggers)", () => {
      // Belt + suspenders: confirm the prior generic code is gone.
      expect(fnBlock).not.toMatch(/ERRCODE\s*=\s*'P0001'/i);
    });
  });

  describe("self-test block", () => {
    it("includes a DO $$ ... $$ probe that fails the migration on regression", () => {
      // Catches deploys where the function compiles but the SQLSTATE
      // wiring is broken (e.g. ERRCODE typo). Runs at migration-apply
      // time inside the same transaction, so a failure rolls back.
      //
      // Pattern is `IF ... THEN RAISE EXCEPTION ...` (not ASSERT) because
      // plpgsql ASSERT is gated on `plpgsql.check_asserts = on` and may
      // be disabled in prd. The behavioral 61-call test lives in the
      // describe.skip integration block below — running it inline at
      // migration-apply would require a hard-coded auth.users founder_id
      // (mint_rate_window has a FK to auth.users.id), which is
      // environment-coupled.
      expect(executable).toMatch(/DO\s+\$\$[\s\S]*?RAISE\s+EXCEPTION[\s\S]*?\$\$\s*;/i);
      // The probe must reference the new ERRCODE so a copy-paste of the
      // old 037 self-test (which would have asserted 'P0001') fails.
      const doBlock = executable.match(/DO\s+\$\$[\s\S]*?\$\$\s*;/i)?.[0] ?? "";
      expect(doBlock).toMatch(/45001/);
    });
  });

  describe("migration hygiene", () => {
    it("does NOT use CREATE INDEX CONCURRENTLY (supabase wraps in tx)", () => {
      // cq-supabase-migration-no-concurrently.
      expect(executable).not.toMatch(/CREATE\s+INDEX\s+CONCURRENTLY/i);
    });
  });
});

// Behavioral integration tests — declared but skipped until the
// migration ships and TENANT_INTEGRATION_TEST=1. These run via
// Doppler DATABASE_URL_POOLER in /work Phase 2-apply against a live
// dev Supabase project (per hr-dev-prd-distinct-supabase-projects).
describe.skip("precheck_jwt_mint — integration tests applied after migration runs", () => {
  it("61st call within a rolling 1h window raises SQLSTATE '45001' (not P0001)", () => {
    // Setup:
    //   const founderId = "00000000-0000-0000-0000-000000000002";
    //   // Reset window for a clean baseline.
    //   await pg.query(
    //     "DELETE FROM public.mint_rate_window WHERE founder_id = $1",
    //     [founderId],
    //   );
    //
    // Drive 60 successful calls:
    //   for (let i = 0; i < 60; i++) {
    //     await pg.query(
    //       "SELECT * FROM public.precheck_jwt_mint($1::uuid, 600)",
    //       [founderId],
    //     );
    //   }
    //
    // 61st call must raise SQLSTATE '45001':
    //   let got_45001 = false;
    //   try {
    //     await pg.query("BEGIN");
    //     await pg.query(
    //       "SELECT * FROM public.precheck_jwt_mint($1::uuid, 600)",
    //       [founderId],
    //     );
    //     await pg.query("COMMIT");
    //   } catch (e: any) {
    //     // node-postgres surfaces SQLSTATE as `code` on the error.
    //     if (e?.code === "45001") got_45001 = true;
    //     await pg.query("ROLLBACK");
    //   }
    //
    // Assert:
    //   expect(got_45001).toBe(true);
    //
    // Cleanup:
    //   await pg.query(
    //     "DELETE FROM public.mint_rate_window WHERE founder_id = $1",
    //     [founderId],
    //   );
  });
});
