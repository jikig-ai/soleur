import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 160_dsar_export_audit_pii_cascade_null_carveout.sql
// (#9994). Offline lint — runs without a live DB.
//
// Pins the load-bearing invariants of the Art-17 SET NULL cascade carve-out
// added to dsar_export_audit_pii_no_mutate:
//   1. The carve-out admits ONLY the exact transition the ON DELETE SET
//      NULL FK performs: OLD.user_id IS NOT NULL, NEW.user_id IS NULL, and
//      every other column structurally unchanged (drift-proof to_jsonb
//      compare — the per-column IS NOT DISTINCT chain is the antipattern
//      that lets a future ADD COLUMN silently widen the gate).
//   2. The NOT EXISTS initiator check — the parent auth.users row must
//      already be gone. Without it any role holding UPDATE (service_role
//      bypasses the table's zero-policy RLS) could strip attribution on a
//      LIVE user's audit row, indistinguishable from legitimate erasure
//      residue. This is strictly stronger than the 066 precedent.
//   3. DELETE branch RAISEs P0001 unconditionally; non-carve-out UPDATEs
//      also RAISE — the WORM guarantee is otherwise untouched.
//   4. The 087-era app.worm_bypass fast-path is preserved (the anonymise
//      RPC sets it to scrub requester_ip/user_agent).
//   5. SECURITY DEFINER + search_path pin; REVOKE quartet.
//   6. Art-17 NULL semantics documented on the column and the function.
//   7. .down.sql restores the 087 body (no carve-out, no NOT EXISTS).

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/160_dsar_export_audit_pii_cascade_null_carveout.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/160_dsar_export_audit_pii_cascade_null_carveout.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

const FN_RE =
  /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.dsar_export_audit_pii_no_mutate[\s\S]*?\$fn\$;/i;

describe("migration 160_dsar_export_audit_pii_cascade_null_carveout", () => {
  describe("trigger function shape", () => {
    it("redeclares dsar_export_audit_pii_no_mutate as SECURITY DEFINER with search_path pin", () => {
      const fnBlock = executable.match(FN_RE);
      expect(
        fnBlock,
        "expected dsar_export_audit_pii_no_mutate function block",
      ).not.toBeNull();
      expect(fnBlock![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock![0]).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
    });

    it("preserves the app.worm_bypass fast-path BEFORE the WORM raises", () => {
      const fnBlock = executable.match(FN_RE);
      expect(fnBlock).not.toBeNull();
      const bypass = fnBlock![0].search(/app\.worm_bypass/i);
      const firstRaise = fnBlock![0].search(/RAISE\s+EXCEPTION/i);
      expect(bypass).toBeGreaterThanOrEqual(0);
      expect(firstRaise).toBeGreaterThan(bypass);
    });

    it("DELETE branch RAISEs P0001 unconditionally", () => {
      const fnBlock = executable.match(FN_RE);
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(
        /IF\s+TG_OP\s*=\s*'DELETE'\s+THEN[\s\S]*?RAISE\s+EXCEPTION[\s\S]*?USING\s+ERRCODE\s*=\s*'P0001'/i,
      );
    });

    it("UPDATE carve-out requires OLD.user_id NOT NULL and NEW.user_id NULL", () => {
      const fnBlock = executable.match(FN_RE);
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(
        /OLD\.user_id\s+IS\s+NOT\s+NULL[\s\S]*?NEW\.user_id\s+IS\s+NULL/i,
      );
      // The pair pins the one-way transition — dropping `NEW.user_id IS
      // NULL` alone would admit uuid-A -> uuid-B re-attribution forgery.
    });

    it("uses the drift-proof to_jsonb-minus-user_id compare", () => {
      const fnBlock = executable.match(FN_RE);
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(
        /\(?\s*to_jsonb\s*\(\s*NEW\s*\)\s*-\s*'user_id'\s*\)?\s*=\s*\(?\s*to_jsonb\s*\(\s*OLD\s*\)\s*-\s*'user_id'\s*\)?/i,
      );
      expect(fnBlock![0]).not.toMatch(/IS\s+NOT\s+DISTINCT\s+FROM/i);
    });

    it("binds the carve-out to a deleted parent via NOT EXISTS (initiator check)", () => {
      const fnBlock = executable.match(FN_RE);
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(
        /NOT\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+auth\.users\s+WHERE\s+id\s*=\s*OLD\.user_id\s*\)/i,
      );
    });

    it("UPDATE branch RAISEs P0001 for any non-carve-out shape", () => {
      const fnBlock = executable.match(FN_RE);
      expect(fnBlock).not.toBeNull();
      const raises = fnBlock![0].match(/RAISE\s+EXCEPTION/gi);
      expect(raises).not.toBeNull();
      expect(raises!.length).toBeGreaterThanOrEqual(2);
    });

    it("does not recreate triggers (041's FOR EACH ROW triggers stand)", () => {
      expect(executable).not.toMatch(/CREATE\s+TRIGGER/i);
    });
  });

  describe("grants", () => {
    it("REVOKEs the trigger function from PUBLIC + anon + authenticated + service_role", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.dsar_export_audit_pii_no_mutate\(\s*\)\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role/i,
      );
    });
  });

  describe("Art-17 semantics documentation", () => {
    it("COMMENTs the function's gate contract", () => {
      expect(executable).toMatch(
        /COMMENT\s+ON\s+FUNCTION\s+public\.dsar_export_audit_pii_no_mutate\(\s*\)\s+IS/i,
      );
    });

    it("COMMENTs the user_id column documenting NULL = Art-17 anonymised", () => {
      expect(executable).toMatch(
        /COMMENT\s+ON\s+COLUMN\s+public\.dsar_export_audit_pii\.user_id\s+IS/i,
      );
      expect(executable).toMatch(/NULL\s+after\s+Art-17\s+erasure/i);
    });
  });

  describe("down migration", () => {
    it("restores the 087 body — no carve-out, no NOT EXISTS, unconditional RAISE", () => {
      const fnBlock = downExecutable.match(FN_RE);
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(/RAISE\s+EXCEPTION/i);
      expect(fnBlock![0]).not.toMatch(/to_jsonb/i);
      expect(fnBlock![0]).not.toMatch(/NOT\s+EXISTS/i);
      expect(fnBlock![0]).toMatch(/app\.worm_bypass/i);
    });
  });
});
