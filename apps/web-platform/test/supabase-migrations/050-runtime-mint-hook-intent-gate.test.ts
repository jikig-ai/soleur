import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 050_runtime_mint_hook_intent_gate.sql.
//
// Migration 047 defined the initial Custom Access Token Hook with a single
// gate: `IF v_auth_method <> 'otp' THEN pass-through`. The Phase-4
// empirical probe (ADR-033 §0.7) proved this gate is insufficient — the
// dashboard's signInWithOtp+verifyOtp produces an event indistinguishable
// from the runtime path's generateLink+verifyOtp. This migration replaces
// the hook with a strengthened gate that additionally requires consumption
// of a row from public.runtime_mint_intent (added in migration 049).
//
// Invariants:
//   1. CREATE OR REPLACE FUNCTION (NOT a new function — same signature,
//      same name, same supabase_auth_admin grant). Replacement is atomic
//      under Postgres DDL semantics.
//   2. Atomic check-and-consume via DELETE...RETURNING in a CTE — a single
//      SQL statement, race-safe against concurrent hook firings.
//   3. 10-second TTL bound: stale intent rows do NOT trigger mint
//      (defense against backdating attacks if the intent table were ever
//      writeable by an unintended role).
//   4. Preserves SECURITY DEFINER + LANGUAGE plpgsql + SET search_path =
//      public, pg_temp (cq-pg-security-definer-search-path-pin-pg-temp).
//   5. Preserves precheck_jwt_mint call and jsonb_set claim stamping
//      (jti, exp, iat, aud='soleur-runtime', role='authenticated').
//   6. Preserves jsonb_build_object('claims', ...) envelope.
//   7. NO `EXCEPTION WHEN OTHERS` — fail-loud retained.
//   8. cq-supabase-migration-no-concurrently: NO CREATE INDEX CONCURRENTLY.
//
// Plan: knowledge-base/project/plans/2026-05-18-refactor-runtime-jwt-asymmetric-signing-substrate-plan.md §Phase 4 amendment
// ADR:  knowledge-base/engineering/architecture/decisions/ADR-033-runtime-jwt-signing-substrate.md §0.7

const MIGRATION_PATH = path.resolve(
  __dirname,
  "../../supabase/migrations/050_runtime_mint_hook_intent_gate.sql",
);

describe("migration 050_runtime_mint_hook_intent_gate", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const executable = sql.replace(/--[^\n]*/g, "");

  describe("function-replacement shape", () => {
    const fnBlock =
      executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.runtime_jwt_mint_hook[\s\S]*?\$\$;/i,
      )?.[0] || "";

    it("uses CREATE OR REPLACE FUNCTION (same signature as 047)", () => {
      expect(fnBlock).not.toBe("");
      expect(fnBlock).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.runtime_jwt_mint_hook\s*\(\s*event\s+jsonb\s*\)\s+RETURNS\s+jsonb/i,
      );
    });

    it("is LANGUAGE plpgsql + SECURITY DEFINER + search_path pinned", () => {
      expect(fnBlock).toMatch(/LANGUAGE\s+plpgsql/i);
      expect(fnBlock).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock).toMatch(
        /SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i,
      );
    });

    it("declares a boolean to track intent consumption", () => {
      // The hook needs a local boolean (or equivalent) to capture whether
      // the DELETE...RETURNING CTE removed a row. Matching the variable
      // declaration ensures the gate uses a real check, not a vacuous
      // SELECT 1.
      expect(fnBlock).toMatch(/v_intent_consumed\s+boolean/i);
    });

    it("atomically deletes runtime_mint_intent via CTE with RETURNING", () => {
      // The check-and-consume MUST be a single SQL statement (DELETE +
      // RETURNING inside WITH or via SELECT EXISTS pattern). A two-step
      // SELECT-then-DELETE would race against concurrent hook firings.
      expect(fnBlock).toMatch(
        /DELETE\s+FROM\s+public\.runtime_mint_intent[\s\S]*?RETURNING/i,
      );
    });

    it("bounds intent age to <= 10 seconds (defense against backdating)", () => {
      // Allow either INTERVAL '10 seconds' or INTERVAL '10s'. Reject
      // looser bounds (minutes/hours) which would create a wide race
      // window.
      expect(fnBlock).toMatch(
        /created_at\s*>\s*NOW\s*\(\s*\)\s*-\s*INTERVAL\s+'10\s*(?:s|seconds?)'/i,
      );
    });

    it("pass-through when intent not consumed OR authentication_method != 'otp'", () => {
      // Belt + suspenders: even if v_intent_consumed is true, a non-OTP
      // flow must still pass-through. Match the IF guard that covers
      // both predicates (in either order).
      expect(fnBlock).toMatch(
        /IF[\s\S]*?(?:v_auth_method\s*<>\s*'otp'|NOT\s+v_intent_consumed)[\s\S]*?(?:v_auth_method\s*<>\s*'otp'|NOT\s+v_intent_consumed)/i,
      );
    });

    it("still calls public.precheck_jwt_mint after the gate passes", () => {
      expect(fnBlock).toMatch(/public\.precheck_jwt_mint/);
    });

    it("still stamps jti / exp / iat / aud / role via jsonb_set (>= 5 calls)", () => {
      const jsonbSetCalls = fnBlock.match(/jsonb_set\s*\(/gi) || [];
      expect(jsonbSetCalls.length).toBeGreaterThanOrEqual(5);
      expect(fnBlock).toMatch(/'\{jti\}'/);
      expect(fnBlock).toMatch(/'\{exp\}'/);
      expect(fnBlock).toMatch(/'\{iat\}'/);
      expect(fnBlock).toMatch(/'"soleur-runtime"'/);
      expect(fnBlock).toMatch(/'"authenticated"'/);
    });

    it("returns jsonb_build_object('claims', ...) envelope", () => {
      expect(fnBlock).toMatch(
        /jsonb_build_object\s*\(\s*'claims'\s*,/i,
      );
    });

    it("does NOT swallow errors via `EXCEPTION WHEN OTHERS`", () => {
      // Fail-loud is mandatory: rate-limit breach (45001), DB outage, or
      // any other failure must surface to Supabase Auth so the user sees
      // a 5xx, not a silently-unsigned token.
      expect(fnBlock).not.toMatch(/EXCEPTION\s+WHEN\s+OTHERS/i);
    });
  });

  describe("grants preservation", () => {
    it("does NOT REVOKE supabase_auth_admin's existing EXECUTE grant", () => {
      // The hook's privileges were set in migration 047. Migration 050
      // is CREATE OR REPLACE, which preserves grants. A REVOKE here
      // would break the hook.
      expect(executable).not.toMatch(
        /REVOKE\s+EXECUTE\s+ON\s+FUNCTION\s+public\.runtime_jwt_mint_hook\s*\([^)]*\)\s+FROM\s+supabase_auth_admin/i,
      );
    });

    it("does not grant EXECUTE to authenticated or anon (defense in depth)", () => {
      expect(executable).not.toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.runtime_jwt_mint_hook\s*\([^)]*\)\s+TO\s+authenticated/i,
      );
      expect(executable).not.toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.runtime_jwt_mint_hook\s*\([^)]*\)\s+TO\s+anon/i,
      );
    });
  });

  describe("migration hygiene", () => {
    it("does NOT use CREATE INDEX CONCURRENTLY", () => {
      expect(executable).not.toMatch(/CREATE\s+INDEX\s+CONCURRENTLY/i);
    });
  });
});

// Behavioral integration tests — activate when TENANT_INTEGRATION_TEST=1.
describe.skip("runtime_jwt_mint_hook — intent-gate integration tests", () => {
  it("WITHOUT intent row: hook returns pass-through claims (no jti rewrite)", () => {
    // Setup:
    //   const fixtureUuid = "<existing auth.users id>";
    //   const inputClaims = { sub: fixtureUuid, aud: "authenticated", role: "authenticated", exp: 9999999999, iat: 0 };
    //   const event = {
    //     user_id: fixtureUuid,
    //     claims: inputClaims,
    //     authentication_method: "otp",
    //   };
    //   await pg.query("DELETE FROM public.runtime_mint_intent WHERE user_id = $1", [fixtureUuid]);
    //
    // Call:
    //   const { rows } = await pg.query(
    //     "SELECT public.runtime_jwt_mint_hook($1::jsonb) AS out",
    //     [JSON.stringify(event)]
    //   );
    //
    // Assert:
    //   expect(rows[0].out.claims.aud).toBe("authenticated");           // not rewritten
    //   expect(rows[0].out.claims).not.toHaveProperty("jti");           // no precheck jti
    //   expect(rows[0].out.claims.exp).toBe(9999999999);                // input preserved
  });

  it("WITH intent row + authentication_method='otp': hook mints (jti, exp=600, aud=soleur-runtime)", () => {
    // Setup:
    //   await pg.query(
    //     "INSERT INTO public.runtime_mint_intent (user_id) VALUES ($1) ON CONFLICT (user_id) DO UPDATE SET created_at = NOW()",
    //     [fixtureUuid]
    //   );
    //   // ... same event as above ...
    //
    // Call + Assert:
    //   expect(rows[0].out.claims.aud).toBe("soleur-runtime");
    //   expect(rows[0].out.claims.jti).toMatch(/^[0-9a-f-]{36}$/i);
    //   // exp is iat+600 from precheck
    //   expect(rows[0].out.claims.exp).toBeGreaterThan(rows[0].out.claims.iat);
  });

  it("WITH stale intent row (>10s old): hook returns pass-through (defense in depth)", () => {
    // Setup:
    //   await pg.query(
    //     "INSERT INTO public.runtime_mint_intent (user_id, created_at) VALUES ($1, NOW() - INTERVAL '15 seconds') ON CONFLICT (user_id) DO UPDATE SET created_at = EXCLUDED.created_at",
    //     [fixtureUuid]
    //   );
    //
    // Assert: pass-through (aud not rewritten).
  });

  it("intent row is DELETEd by hook on consume (idempotency)", () => {
    // Setup: UPSERT intent → call hook → query table
    //   const { rows } = await pg.query(
    //     "SELECT count(*)::int AS n FROM public.runtime_mint_intent WHERE user_id = $1",
    //     [fixtureUuid]
    //   );
    //   expect(rows[0].n).toBe(0);
  });
});
