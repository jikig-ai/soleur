import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 162_action_sends_message_id_cascade_null_carveout.sql
// (#10254). Offline lint — runs without a live DB.
//
// Pins the load-bearing invariants of the Art-17 SET NULL cascade carve-out
// added to action_sends_no_mutate (mirroring 161's
// audit_github_token_use gate, adapted for the shared-statement-trigger
// anatomy of action_sends):
//   1. The carve-out admits ONLY the exact transition the ON DELETE SET
//      NULL FK performs: OLD.message_id IS NOT NULL, NEW.message_id IS
//      NULL, and every other column structurally unchanged (drift-proof
//      to_jsonb compare — the per-column IS NOT DISTINCT chain is the
//      antipattern that lets a future ADD COLUMN silently widen the gate).
//   2. The NOT EXISTS initiator check — the parent public.messages row
//      must already be gone. Without it any role holding UPDATE
//      (service_role bypasses the table's zero-policy RLS) could de-link
//      a LIVE message's send row, indistinguishable from legitimate
//      erasure residue.
//   3. TG_LEVEL='ROW' gate on the carve-out branch — action_sends_no_mutate
//      also serves the statement-level triggers (064, 051), where OLD/NEW
//      are unassigned records; an ungated branch raises
//      `record "old" is not assigned yet` instead of clean P0001.
//   4. DELETE branch RAISEs P0001 unconditionally; non-carve-out UPDATEs
//      also RAISE — the WORM guarantee is otherwise untouched.
//   5. The 087-era app.worm_bypass fast-path is preserved (the anonymise
//      RPC sets it to scrub user_id + recipient_id_hash + message_id).
//   6. SECURITY DEFINER + search_path pin; REVOKE quartet.
//   7. Statement trigger's column list excludes message_id (keeps the
//      other 11); a NEW row-level BEFORE UPDATE OF message_id trigger
//      exists — the SET NULL cascade fires row-level, and a statement
//      guard on message_id would reject it.
//   8. anonymise_action_sends gains message_id = NULL (eager de-link
//      hardening inside the established GUC window).
//   9. NULL semantics documented on the column and the function.
//  10. .down.sql restores the 087 body (no carve-out, no NOT EXISTS) and
//      the 064 12-column statement trigger.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/162_action_sends_message_id_cascade_null_carveout.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/162_action_sends_message_id_cascade_null_carveout.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

const FN_RE =
  /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.action_sends_no_mutate[\s\S]*?\$fn\$;/i;
const RPC_RE =
  /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_action_sends[\s\S]*?\$fn\$;/i;

describe("migration 162_action_sends_message_id_cascade_null_carveout", () => {
  describe("trigger function shape", () => {
    it("redeclares action_sends_no_mutate as SECURITY DEFINER with search_path pin", () => {
      const fnBlock = executable.match(FN_RE);
      expect(
        fnBlock,
        "expected action_sends_no_mutate function block",
      ).not.toBeNull();
      expect(fnBlock![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock![0]).toMatch(
        /SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i,
      );
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

    it("gates the carve-out branch on TG_OP='UPDATE' AND TG_LEVEL='ROW'", () => {
      const fnBlock = executable.match(FN_RE);
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(
        /TG_OP\s*=\s*'UPDATE'\s+AND\s+TG_LEVEL\s*=\s*'ROW'/i,
      );
    });

    it("UPDATE carve-out requires OLD.message_id NOT NULL and NEW.message_id NULL", () => {
      const fnBlock = executable.match(FN_RE);
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(
        /OLD\.message_id\s+IS\s+NOT\s+NULL[\s\S]*?NEW\.message_id\s+IS\s+NULL/i,
      );
      // The pair pins the one-way transition — dropping `NEW.message_id IS
      // NULL` alone would admit uuid-A -> uuid-B re-linkage forgery.
    });

    it("uses the drift-proof to_jsonb-minus-message_id compare", () => {
      const fnBlock = executable.match(FN_RE);
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(
        /\(?\s*to_jsonb\s*\(\s*NEW\s*\)\s*-\s*'message_id'\s*\)?\s*=\s*\(?\s*to_jsonb\s*\(\s*OLD\s*\)\s*-\s*'message_id'\s*\)?/i,
      );
      expect(fnBlock![0]).not.toMatch(/IS\s+NOT\s+DISTINCT\s+FROM/i);
    });

    it("binds the carve-out to a deleted parent via NOT EXISTS (initiator check)", () => {
      const fnBlock = executable.match(FN_RE);
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(
        /NOT\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.messages\s+WHERE\s+id\s*=\s*OLD\.message_id\s*\)/i,
      );
    });

    it("UPDATE branch RAISEs P0001 for any non-carve-out shape", () => {
      const fnBlock = executable.match(FN_RE);
      expect(fnBlock).not.toBeNull();
      const raises = fnBlock![0].match(/RAISE\s+EXCEPTION/gi);
      expect(raises).not.toBeNull();
      expect(raises!.length).toBeGreaterThanOrEqual(2);
    });
  });

  describe("trigger reshape", () => {
    it("recreates action_sends_no_update FOR EACH STATEMENT minus message_id", () => {
      const trig = executable.match(
        /CREATE\s+TRIGGER\s+action_sends_no_update[\s\S]*?EXECUTE\s+FUNCTION/i,
      );
      expect(trig, "expected action_sends_no_update trigger").not.toBeNull();
      expect(trig![0]).toMatch(/FOR\s+EACH\s+STATEMENT/i);
      const cols = trig![0].match(/BEFORE\s+UPDATE\s+OF([\s\S]*?)ON\s+public/i);
      expect(cols).not.toBeNull();
      expect(cols![1]).not.toMatch(/message_id/i);
      for (const col of [
        "id",
        "user_id",
        "action_class",
        "tier_at_send",
        "template_hash",
        "per_send_body_sha256",
        "recipient_id_hash",
        "clicked_at",
        "confirmed_typed",
        "approval_signature_sha256",
        "grant_id",
      ]) {
        expect(cols![1], `statement trigger missing column ${col}`).toMatch(
          new RegExp(`\\b${col}\\b`, "i"),
        );
      }
    });

    it("adds a row-level BEFORE UPDATE OF message_id trigger through action_sends_no_mutate", () => {
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+action_sends_message_id_guard[\s\S]*?BEFORE\s+UPDATE\s+OF\s+message_id[\s\S]*?FOR\s+EACH\s+ROW[\s\S]*?EXECUTE\s+FUNCTION\s+public\.action_sends_no_mutate/i,
      );
    });
  });

  describe("FK reshape", () => {
    it("drops NOT NULL and re-adds the FK ON DELETE SET NULL (NOT VALID + VALIDATE)", () => {
      expect(executable).toMatch(
        /ALTER\s+COLUMN\s+message_id\s+DROP\s+NOT\s+NULL/i,
      );
      expect(executable).toMatch(
        /FOREIGN\s+KEY\s*\(\s*message_id\s*\)\s+REFERENCES\s+public\.messages\s*\(\s*id\s*\)\s+ON\s+DELETE\s+SET\s+NULL/i,
      );
      expect(executable).toMatch(
        /VALIDATE\s+CONSTRAINT\s+action_sends_message_id_fkey/i,
      );
    });
  });

  describe("anonymise hardening", () => {
    it("anonymise_action_sends sets message_id = NULL inside the bypass window", () => {
      const rpcBlock = executable.match(RPC_RE);
      expect(
        rpcBlock,
        "expected anonymise_action_sends function block",
      ).not.toBeNull();
      expect(rpcBlock![0]).toMatch(/message_id\s*=\s*NULL/i);
      expect(rpcBlock![0]).toMatch(/app\.worm_bypass/i);
    });
  });

  describe("grants", () => {
    it("REVOKEs the trigger function from PUBLIC + anon + authenticated + service_role", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.action_sends_no_mutate\(\s*\)\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role/i,
      );
    });
  });

  describe("Art-17 semantics documentation", () => {
    it("COMMENTs the function's gate contract", () => {
      expect(executable).toMatch(
        /COMMENT\s+ON\s+FUNCTION\s+public\.action_sends_no_mutate\(\s*\)\s+IS/i,
      );
    });

    it("COMMENTs the message_id column documenting NULL = de-linked", () => {
      expect(executable).toMatch(
        /COMMENT\s+ON\s+COLUMN\s+public\.action_sends\.message_id\s+IS/i,
      );
      expect(executable).toMatch(/NULL\s*=\s*de-linked/i);
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

    it("restores the 064 12-column statement trigger including message_id", () => {
      const trig = downExecutable.match(
        /CREATE\s+TRIGGER\s+action_sends_no_update[\s\S]*?EXECUTE\s+FUNCTION/i,
      );
      expect(trig, "expected action_sends_no_update trigger").not.toBeNull();
      const cols = trig![0].match(/BEFORE\s+UPDATE\s+OF([\s\S]*?)ON\s+public/i);
      expect(cols).not.toBeNull();
      expect(cols![1]).toMatch(/message_id/i);
      expect(cols![1]).toMatch(/user_id/i);
    });

    it("restores message_id NOT NULL and the NO ACTION FK", () => {
      expect(downExecutable).toMatch(
        /ALTER\s+COLUMN\s+message_id\s+SET\s+NOT\s+NULL/i,
      );
      expect(downExecutable).toMatch(
        /FOREIGN\s+KEY\s*\(\s*message_id\s*\)\s+REFERENCES\s+public\.messages\s*\(\s*id\s*\)\s*;/i,
      );
    });
  });
});
