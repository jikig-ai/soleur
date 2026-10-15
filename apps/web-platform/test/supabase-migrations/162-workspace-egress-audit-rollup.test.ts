import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 162_workspace_egress_audit_rollup.sql (#9545, PR1).
// Offline text lint — runs without a live DB. Everything that needs an auth
// boundary (member reads denied, cascade, sweep, GREATEST/LEAST, toggle join)
// runs in the live-database harness: test/rls-fuzz/egress-audit-rollup.integration.test.ts.
//
// Pins:
//   1. Table shape: composite key incl. source_host, FK ON DELETE CASCADE, RLS on,
//      no member policy in PR1, all table privileges revoked from anon/authenticated.
//   2. Every SECURITY DEFINER function pins search_path incl. pg_temp and is
//      EXECUTE-able by service_role only (REVOKE from PUBLIC/anon/authenticated).
//   3. GDPR annotations: LAWFUL_BASIS and a table comment stating the retention
//      and the sweep function.
//   4. The retention sweep is scheduled through pg_cron inside a DO block catching
//      duplicate_object, and refuses a retention shorter than a day.
//   5. The .down.sql unschedules the job and drops all three functions and the table.

const DIR = path.join(__dirname, "../../supabase/migrations");
const UP = path.join(DIR, "162_workspace_egress_audit_rollup.sql");
const DOWN = path.join(DIR, "162_workspace_egress_audit_rollup.down.sql");
const VERIFY = path.join(__dirname, "../../supabase/verify/162_workspace_egress_audit_rollup.sql");

const read = (p: string): string => (existsSync(p) ? readFileSync(p, "utf8") : "");
const up = read(UP);
const down = read(DOWN);
const verify = read(VERIFY);
const exec = (s: string): string => s.replace(/--[^\n]*/g, "");
const upExec = exec(up);
const downExec = exec(down);

const FUNCS = [
  "ingest_egress_audit_rollup",
  "purge_egress_audit_rollup",
  "erase_egress_audit_rollup",
  "erase_egress_audit_rollup_for_requester",
] as const;

function fnBlock(name: string): string {
  const m = upExec.match(
    new RegExp(`CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${name}\\b[\\s\\S]*?\\$\\$;`, "i"),
  );
  return m ? m[0] : "";
}

describe("migration 162_workspace_egress_audit_rollup", () => {
  it("exists with a paired down migration and a verify sentinel", () => {
    expect(existsSync(UP), "162 up migration").toBe(true);
    expect(existsSync(DOWN), "162 down migration").toBe(true);
    expect(existsSync(VERIFY), "verify/162 sentinel").toBe(true);
  });

  describe("table", () => {
    it("has the composite key including source_host and the cascade FK", () => {
      expect(upExec).toMatch(/CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.workspace_egress_audit_rollup/i);
      expect(upExec).toMatch(
        /PRIMARY\s+KEY\s*\(\s*workspace_id\s*,\s*bucket_start\s*,\s*requested_host\s*,\s*decision\s*,\s*source_host\s*\)/i,
      );
      expect(upExec).toMatch(
        /workspace_id\s+uuid\s+NOT\s+NULL\s+REFERENCES\s+public\.workspaces\s*\(\s*id\s*\)\s+ON\s+DELETE\s+CASCADE/i,
      );
    });

    it("stores no resolved_ip, client, duration or per-user column (DPIA trigger t7)", () => {
      const tbl = upExec.match(/CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.workspace_egress_audit_rollup[\s\S]*?\);/i);
      expect(tbl, "table block").not.toBeNull();
      for (const forbidden of ["resolved_ip", "client", "duration", "user_id", "session", "ip_address", "path"]) {
        expect(tbl![0], `column ${forbidden}`).not.toMatch(new RegExp(`\\b${forbidden}\\b`, "i"));
      }
    });

    it("enables RLS, defines NO policy, and revokes every table privilege from anon/authenticated", () => {
      expect(upExec).toMatch(
        /ALTER\s+TABLE\s+public\.workspace_egress_audit_rollup\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i,
      );
      expect(upExec).not.toMatch(/CREATE\s+POLICY/i);
      expect(upExec).toMatch(
        /REVOKE\s+ALL\s+ON\s+(TABLE\s+)?public\.workspace_egress_audit_rollup\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated/i,
      );
    });

    it("closes the columns the writer controls: decision enum, host charset, aligned bucket, ordered window", () => {
      const tbl = upExec.match(/CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.workspace_egress_audit_rollup[\s\S]*?\n\);/i)![0];
      expect(tbl).toMatch(/decision\s+text\s+NOT\s+NULL\s+CHECK\s*\(\s*decision\s+IN\s*\(\s*'allowed'\s*,\s*'denied'\s*,\s*'other'\s*\)\s*\)/i);
      expect(tbl).toMatch(/requested_host\s+~\s+'\^\(\[a-z0-9\._:\\\[\\\]-\]\+\|\\\(other\\\)\)\$'/i);
      expect(tbl).toMatch(/extract\s*\(\s*epoch\s+FROM\s+bucket_start\s*\)::numeric\s*%\s*900\s*=\s*0/i);
      expect(tbl).toMatch(/first_seen\s*<=\s*last_seen/i);
      expect(tbl).toMatch(/first_seen\s*>=\s*bucket_start/i);
      expect(tbl).toMatch(/last_seen\s*<\s*bucket_start\s*\+\s*interval\s+'15\s+minutes'/i);
    });

    it("annotates the lawful basis and the retention on the table", () => {
      expect(up).toMatch(/--\s*LAWFUL_BASIS:\s*legitimate-interest\s*\(Art\.\s*6\(1\)\(f\)\)/);
      const comment = upExec.match(/COMMENT\s+ON\s+TABLE\s+public\.workspace_egress_audit_rollup\s+IS[\s\S]*?'\s*;/i);
      expect(comment, "COMMENT ON TABLE").not.toBeNull();
      expect(comment![0]).toMatch(/30\s*days/i);
      expect(comment![0]).toMatch(/purge_egress_audit_rollup/);
    });
  });

  describe("functions", () => {
    for (const name of FUNCS) {
      it(`${name} is SECURITY DEFINER, pins search_path incl. pg_temp, and is service_role only`, () => {
        const block = fnBlock(name);
        expect(block, `${name} block`).not.toBe("");
        expect(block).toMatch(/SECURITY\s+DEFINER/i);
        expect(block).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
        expect(upExec).toMatch(
          new RegExp(
            `REVOKE\\s+ALL\\s+ON\\s+FUNCTION\\s+public\\.${name}\\s*\\([^)]*\\)\\s+FROM\\s+PUBLIC\\s*,\\s*anon\\s*,\\s*authenticated`,
            "i",
          ),
        );
        expect(upExec).toMatch(
          new RegExp(`GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${name}\\s*\\([^)]*\\)\\s+TO\\s+service_role`, "i"),
        );
        expect(upExec).not.toMatch(
          new RegExp(`GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${name}\\s*\\([^)]*\\)\\s+TO\\s+(authenticated|anon|PUBLIC)`, "i"),
        );
      });
    }

    it("ingest merges per column with GREATEST and LEAST, never SUM", () => {
      const block = fnBlock("ingest_egress_audit_rollup");
      expect(block).toMatch(/GREATEST\s*\(\s*(public\.)?workspace_egress_audit_rollup\.request_count/i);
      expect(block).toMatch(/GREATEST\s*\(\s*(public\.)?workspace_egress_audit_rollup\.bytes_out/i);
      expect(block).toMatch(/GREATEST\s*\(\s*(public\.)?workspace_egress_audit_rollup\.last_seen/i);
      expect(block).toMatch(/LEAST\s*\(\s*(public\.)?workspace_egress_audit_rollup\.first_seen/i);
      expect(block).not.toMatch(/request_count\s*\+\s*EXCLUDED\.request_count/i);
      expect(block).not.toMatch(/SUM\s*\(/i);
    });

    it("ingest joins the workspace toggle and folds host overflow into (other)", () => {
      const block = fnBlock("ingest_egress_audit_rollup");
      expect(block).toMatch(/web_egress/i);
      expect(block).toMatch(/\(other\)/);
    });

    it("ingest skips an orphaned workspace (no member row found under a FOR SHARE lock)", () => {
      expect(fnBlock("ingest_egress_audit_rollup")).toMatch(/NOT\s+FOUND[\s\S]*?v_unknown\s*:=\s*v_unknown\s*\+\s*1/i);
    });

    it("ingest catches only content errors (data_exception, integrity_constraint_violation), never WHEN OTHERS", () => {
      const block = fnBlock("ingest_egress_audit_rollup");
      expect(block).toMatch(/EXCEPTION\s+WHEN\s+data_exception\s+OR\s+integrity_constraint_violation\s+THEN/i);
      expect(block).not.toMatch(/WHEN\s+OTHERS/i);
    });

    it("ingest does not rewrite a tuple when a replay changes nothing", () => {
      const block = fnBlock("ingest_egress_audit_rollup");
      expect(block).toMatch(/DO\s+UPDATE\s+SET[\s\S]*?\bWHERE\b[\s\S]*?request_count\s*<\s*EXCLUDED\.request_count/i);
    });

    it("ingest locks the member rows (FOR SHARE) so a concurrent erasure cannot interleave with the insert", () => {
      expect(fnBlock("ingest_egress_audit_rollup")).toMatch(
        /PERFORM\s+1\s+FROM\s+public\.workspace_members\s+m\s+WHERE\s+m\.workspace_id\s*=\s*v_ws\s+FOR\s+SHARE/i,
      );
    });

    it("the requester erase deletes only when the requester is the sole member, under a member-row lock", () => {
      const block = fnBlock("erase_egress_audit_rollup_for_requester");
      expect(block).toMatch(/FOR\s+SHARE/i);
      expect(block).toMatch(/count\(\*\)[\s\S]*?<>\s*1/i);
      expect(block).toMatch(/m\.user_id\s*=\s*p_requester/i);
    });

    it("erase deletes only a workspace that has no member row left", () => {
      const block = fnBlock("erase_egress_audit_rollup");
      expect(block).toMatch(/IF\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.workspace_members[\s\S]*?RETURN\s+0/i);
    });

    it("purge refuses a retention shorter than one day", () => {
      const block = fnBlock("purge_egress_audit_rollup");
      expect(block).toMatch(/interval\s+'1\s+day'/i);
      expect(block).toMatch(/RAISE\s+EXCEPTION/i);
    });
  });

  describe("retention sweep", () => {
    it("is scheduled with pg_cron inside a DO block catching duplicate_object", () => {
      const doBlock = upExec.match(/DO\s+\$\$[\s\S]*?cron\.schedule[\s\S]*?END\s+\$\$;/i);
      expect(doBlock, "DO block with cron.schedule").not.toBeNull();
      expect(doBlock![0]).toMatch(/duplicate_object/i);
      expect(doBlock![0]).toMatch(/cron\.unschedule\('egress-audit-rollup-retention'\)/i);
      expect(doBlock![0]).toMatch(/purge_egress_audit_rollup/);
      expect(doBlock![0]).toMatch(/interval\s+'30\s+days'/i);
    });
  });

  describe("down migration", () => {
    it("unschedules the job and drops the functions and the table", () => {
      expect(downExec).toMatch(/cron\.unschedule/i);
      for (const name of FUNCS) {
        expect(downExec, name).toMatch(new RegExp(`DROP\\s+FUNCTION\\s+IF\\s+EXISTS\\s+public\\.${name}`, "i"));
      }
      expect(downExec).toMatch(/DROP\s+TABLE\s+IF\s+EXISTS\s+public\.workspace_egress_audit_rollup/i);
    });
  });

  describe("verify sentinel", () => {
    it("uses the bad=1 row format and covers grants, comment, RLS and the scheduled job", () => {
      expect(verify).toMatch(/AS\s+bad/i);
      expect(verify).toMatch(/has_function_privilege\(\s*'anon'/i);
      expect(verify).toMatch(/has_function_privilege\(\s*'authenticated'/i);
      expect(verify).toMatch(/has_function_privilege\(\s*'service_role'/i);
      expect(verify).toMatch(/obj_description/i);
      expect(verify).toMatch(/relrowsecurity/i);
      expect(verify).toMatch(/cron\.job/i);
      expect(verify).toMatch(/prosecdef/i);
      expect(verify).toMatch(/proconfig/i);
      expect(verify).toMatch(/INSERT,UPDATE,DELETE/i);
      expect(verify).toMatch(/AND\s+active/i);
    });
  });
});
