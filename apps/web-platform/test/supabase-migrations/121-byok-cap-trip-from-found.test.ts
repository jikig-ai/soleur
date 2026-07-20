import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 121_byok_cap_trip_from_found.sql (#5917).
//
// File-parse contract test (mirrors the 046/061 precedent), pinning the
// authoritative trip-signal invariant: after the guarded UPDATE on
// public.users, the kill-switch trip is derived from `FOUND` (the UPDATE's
// actual row-change) rather than from the pre-read `v_paused_at` snapshot.
//
// ROOT CAUSE this migration fixes: a dev-only drifted RPC body reported
// kill_tripped=true on EVERY already-paused call, producing a double-trip
// under concurrency that the atomicity integration test's Invariant C
// (byok-kill-switch.atomicity.tenant-isolation.test.ts) correctly rejected,
// turning `tenant-integration-required` red on main.
//
// This test is RED against migration 061's body (`v_tripped := true`) and
// GREEN once migration 121 lands (`v_tripped := FOUND`).

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/121_byok_cap_trip_from_found.sql",
);
const MIGRATION_061_PATH = path.join(
  __dirname,
  "../../supabase/migrations/061_byok_audit_workspace_id_rpcs.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/121_byok_cap_trip_from_found.down.sql",
);

describe("migration 121_byok_cap_trip_from_found", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  // Strip line comments before pattern checks (mirrors 037/046).
  const executable = sql.replace(/--[^\n]*/g, "");

  describe("authoritative trip signal (#5917)", () => {
    it("derives the trip from FOUND after the guarded UPDATE (not the pre-read snapshot)", () => {
      // The load-bearing change: `v_tripped := FOUND;` immediately after the
      // guarded UPDATE. FOUND is true iff THIS statement changed the row, so
      // exactly one concurrent caller trips.
      expect(executable).toMatch(
        /UPDATE\s+public\.users[\s\S]*?SET\s+runtime_paused_at\s*=\s*now\(\)[\s\S]*?WHERE[\s\S]*?id\s*=\s*p_founder_id[\s\S]*?runtime_paused_at\s+IS\s+NULL[\s\S]*?v_tripped\s*:=\s*FOUND/i,
      );
    });

    it("does NOT report a trip from a bare `v_paused_at IS NOT NULL` branch (the dev-drift bug)", () => {
      // The rogue dev body reported kill_tripped=true whenever the founder
      // was already paused. This migration must NOT contain that branch.
      expect(executable).not.toMatch(
        /v_paused_at\s+IS\s+NOT\s+NULL\s+THEN[\s\S]*?v_tripped\s*:=\s*true/i,
      );
    });

    it("guards the trip on a strict cap breach (`v_total > v_cap`)", () => {
      expect(executable).toMatch(/IF\s+v_total\s*>\s*v_cap\s+THEN/i);
    });
  });

  describe("retained atomicity + security invariants", () => {
    it("retains the FOR UPDATE lock on public.users before the SUM (TOCTOU fix)", () => {
      const lockIdx = executable.search(
        /FROM\s+public\.users[\s\S]*?WHERE\s+id\s*=\s*p_founder_id[\s\S]*?FOR\s+UPDATE/i,
      );
      const sumIdx = executable.search(
        /SUM\s*\(\s*token_count\s*\*\s*unit_cost_cents\s*\)/i,
      );
      expect(lockIdx, "expected FOR UPDATE lock present").toBeGreaterThan(-1);
      expect(sumIdx, "expected SUM present").toBeGreaterThan(-1);
      expect(
        lockIdx,
        "FOR UPDATE must appear before the SUM to prevent the TOCTOU race",
      ).toBeLessThan(sumIdx);
    });

    it("INSERTs the audit row before computing the SUM (accounting-is-sacred)", () => {
      const insertIdx = executable.search(
        /INSERT\s+INTO\s+public\.audit_byok_use[\s\S]*?VALUES/i,
      );
      const sumIdx = executable.search(
        /SUM\s*\(\s*token_count\s*\*\s*unit_cost_cents\s*\)/i,
      );
      expect(insertIdx, "expected audit INSERT present").toBeGreaterThan(-1);
      expect(insertIdx).toBeLessThan(sumIdx);
    });

    it("declares LANGUAGE plpgsql + SECURITY DEFINER", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.record_byok_use_and_check_cap[\s\S]*?LANGUAGE\s+plpgsql/i,
      );
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.record_byok_use_and_check_cap[\s\S]*?SECURITY\s+DEFINER/i,
      );
    });

    it("pins search_path = public, pg_temp (cq-pg-security-definer-search-path-pin-pg-temp)", () => {
      expect(executable).toMatch(
        /SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });

    it("re-issues the REVOKE from PUBLIC/anon/authenticated + GRANT EXECUTE to service_role", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.record_byok_use_and_check_cap\s*\([\s\S]*?\)[\s\S]*?FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.record_byok_use_and_check_cap\s*\([\s\S]*?\)[\s\S]*?TO\s+service_role/i,
      );
    });

    it("does NOT use CREATE INDEX CONCURRENTLY (cq-supabase-migration-no-concurrently)", () => {
      expect(executable).not.toMatch(/CREATE\s+INDEX\s+CONCURRENTLY/i);
    });
  });

  describe("down migration", () => {
    const downSql = readFileSync(DOWN_PATH, "utf8");
    const down = downSql.replace(/--[^\n]*/g, "");
    const mig061 = readFileSync(MIGRATION_061_PATH, "utf8").replace(
      /--[^\n]*/g,
      "",
    );

    it("restores the migration-061 pre-read-guard trip block", () => {
      expect(down).toMatch(
        /IF\s+v_paused_at\s+IS\s+NULL\s+AND\s+v_total\s*>\s*v_cap\s+THEN[\s\S]*?v_tripped\s*:=\s*true/i,
      );
      // Sanity: mig 061 source really did carry that guard (the state we
      // restore to).
      expect(mig061).toMatch(
        /IF\s+v_paused_at\s+IS\s+NULL\s+AND\s+v_total\s*>\s*v_cap\s+THEN/i,
      );
    });

    it("does not reintroduce the FOUND-based body in the down direction", () => {
      expect(down).not.toMatch(/v_tripped\s*:=\s*FOUND/i);
    });
  });
});
