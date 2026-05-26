import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 066_audit_byok_use_art17_carveout.sql (#4356).
// Offline lint — runs without a live DB.
//
// Pins the load-bearing invariants of the WORM-trigger Art-17 carve-out:
//   1. Triggers are FOR EACH ROW (not statement-level — row access to
//      OLD/NEW is required by the carve-out body).
//   2. DELETE branch RAISEs unconditionally.
//   3. UPDATE branch uses a row-hash compare (`to_jsonb(NEW) - 'founder_id'
//      = to_jsonb(OLD) - 'founder_id'`) so a future ALTER TABLE ADD COLUMN
//      does NOT silently widen the carve-out (the per-column IS NOT
//      DISTINCT chain that drift-proof shape replaces was the antipattern
//      flagged in code review).
//   4. Both triggers reference the same function name.
//   5. REVOKE on the function from PUBLIC + anon + authenticated +
//      service_role (trigger function does NOT need EXECUTE — triggers
//      fire as table owner).
//   6. COMMENT ON COLUMN audit_byok_use.founder_id documents Art-17 NULL
//      semantics so analytics consumers don't silently drop anonymised
//      rows.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/066_audit_byok_use_art17_carveout.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/066_audit_byok_use_art17_carveout.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

describe("migration 066_audit_byok_use_art17_carveout", () => {
  describe("trigger function shape", () => {
    it("redeclares audit_byok_use_no_mutate as SECURITY DEFINER with search_path pin", () => {
      const fnBlock = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.audit_byok_use_no_mutate\s*\(\s*\)[\s\S]*?\$\$;/i,
      );
      expect(fnBlock, "expected audit_byok_use_no_mutate function block").not.toBeNull();
      expect(fnBlock![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock![0]).toMatch(
        /SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i,
      );
    });

    it("DELETE branch RAISEs P0001 unconditionally", () => {
      const fnBlock = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.audit_byok_use_no_mutate[\s\S]*?\$\$;/i,
      );
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(
        /IF\s+TG_OP\s*=\s*'DELETE'\s+THEN[\s\S]*?RAISE\s+EXCEPTION[\s\S]*?USING\s+ERRCODE\s*=\s*'P0001'/i,
      );
    });

    it("UPDATE branch allows the Art-17 anonymization transition (founder_id non-NULL → NULL)", () => {
      const fnBlock = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.audit_byok_use_no_mutate[\s\S]*?\$\$;/i,
      );
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(
        /OLD\.founder_id\s+IS\s+NOT\s+NULL[\s\S]*?NEW\.founder_id\s+IS\s+NULL/i,
      );
    });

    it("uses drift-proof row-hash compare (to_jsonb minus founder_id), NOT per-column IS NOT DISTINCT", () => {
      // The per-column chain that this row-hash replaces was flagged as a
      // forward-compat hazard: any future ALTER TABLE ADD COLUMN would
      // silently widen the carve-out. The to_jsonb shape covers any
      // future column automatically.
      const fnBlock = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.audit_byok_use_no_mutate[\s\S]*?\$\$;/i,
      );
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(
        /\(?\s*to_jsonb\s*\(\s*NEW\s*\)\s*-\s*'founder_id'\s*\)?\s*=\s*\(?\s*to_jsonb\s*\(\s*OLD\s*\)\s*-\s*'founder_id'\s*\)?/i,
      );
    });

    it("UPDATE branch RAISEs P0001 for any non-anonymization shape", () => {
      const fnBlock = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.audit_byok_use_no_mutate[\s\S]*?\$\$;/i,
      );
      expect(fnBlock).not.toBeNull();
      // Two RAISE EXCEPTION sites: one for DELETE, one for non-carve-out
      // UPDATE.
      const raises = fnBlock![0].match(/RAISE\s+EXCEPTION/gi);
      expect(raises).not.toBeNull();
      expect(raises!.length).toBeGreaterThanOrEqual(2);
    });
  });

  describe("trigger declarations", () => {
    it("audit_byok_use_no_update is FOR EACH ROW (not STATEMENT — row body needs OLD/NEW access)", () => {
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+audit_byok_use_no_update\s+BEFORE\s+UPDATE\s+ON\s+public\.audit_byok_use\s+FOR\s+EACH\s+ROW/i,
      );
      expect(executable).not.toMatch(
        /CREATE\s+TRIGGER\s+audit_byok_use_no_update\s+BEFORE\s+UPDATE\s+ON\s+public\.audit_byok_use\s+FOR\s+EACH\s+STATEMENT/i,
      );
    });

    it("audit_byok_use_no_delete is FOR EACH ROW", () => {
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+audit_byok_use_no_delete\s+BEFORE\s+DELETE\s+ON\s+public\.audit_byok_use\s+FOR\s+EACH\s+ROW/i,
      );
    });

    it("both triggers reference the same function", () => {
      const updExec = executable.match(
        /CREATE\s+TRIGGER\s+audit_byok_use_no_update[\s\S]*?EXECUTE\s+FUNCTION\s+([\w.]+)\s*\(\s*\)/i,
      );
      const delExec = executable.match(
        /CREATE\s+TRIGGER\s+audit_byok_use_no_delete[\s\S]*?EXECUTE\s+FUNCTION\s+([\w.]+)\s*\(\s*\)/i,
      );
      expect(updExec).not.toBeNull();
      expect(delExec).not.toBeNull();
      expect(updExec![1]).toBe(delExec![1]);
      expect(updExec![1]).toBe("public.audit_byok_use_no_mutate");
    });
  });

  describe("grants", () => {
    it("REVOKEs the trigger function from PUBLIC + anon + authenticated + service_role", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.audit_byok_use_no_mutate\(\s*\)\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role/i,
      );
    });
  });

  describe("Art-17 semantics documentation", () => {
    it("COMMENTs the founder_id column documenting NULL = Art-17 anonymised", () => {
      // Future analytics consumers must know that JOINing audit_byok_use
      // to users on founder_id silently drops anonymised rows; aggregate
      // queries should key on workspace_id.
      expect(executable).toMatch(
        /COMMENT\s+ON\s+COLUMN\s+public\.audit_byok_use\.founder_id\s+IS/i,
      );
      expect(executable).toMatch(/NULL\s+after\s+Art\.\s*17\s+anonymisation/i);
    });
  });

  describe("down migration", () => {
    it("restores the unconditional-RAISE shape (no UPDATE carve-out)", () => {
      const fnBlock = downExecutable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.audit_byok_use_no_mutate[\s\S]*?\$\$;/i,
      );
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(/RAISE\s+EXCEPTION/i);
      expect(fnBlock![0]).not.toMatch(/to_jsonb/i);
    });

    it("restores FOR EACH STATEMENT triggers", () => {
      expect(downExecutable).toMatch(
        /CREATE\s+TRIGGER\s+audit_byok_use_no_update\s+BEFORE\s+UPDATE\s+ON\s+public\.audit_byok_use\s+FOR\s+EACH\s+STATEMENT/i,
      );
      expect(downExecutable).toMatch(
        /CREATE\s+TRIGGER\s+audit_byok_use_no_delete\s+BEFORE\s+DELETE\s+ON\s+public\.audit_byok_use\s+FOR\s+EACH\s+STATEMENT/i,
      );
    });

    it("REVOKEs the function", () => {
      expect(downExecutable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.audit_byok_use_no_mutate\(\s*\)\s+FROM/i,
      );
    });
  });
});
