import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 164_git_data_erasure_pending.sql (#8211, PR-B1). Offline text lint;
// the behavioural proofs (RLS/grant denial, upsert keeps requested_at, SKIP LOCKED, resolve +
// counter in one statement) run in test/rls-fuzz/git-data-erasure-pending.integration.test.ts.

const DIR = path.join(__dirname, "../../supabase/migrations");
const UP = path.join(DIR, "164_git_data_erasure_pending.sql");
const DOWN = path.join(DIR, "164_git_data_erasure_pending.down.sql");
const VERIFY = path.join(__dirname, "../../supabase/verify/164_git_data_erasure_pending.sql");

const read = (p: string): string => (existsSync(p) ? readFileSync(p, "utf8") : "");
const exec = (s: string): string => s.replace(/--[^\n]*/g, "");
const up = exec(read(UP));
const down = exec(read(DOWN));
const verify = read(VERIFY);

const FUNCS = [
  ["record_git_data_erasure_pending", "uuid, text"],
  ["claim_git_data_erasure_pending", "int, interval"],
  ["resolve_git_data_erasure_pending", "uuid"],
  ["oldest_git_data_erasure_pending_age", ""],
] as const;

const fnBlock = (name: string): string =>
  up.match(new RegExp(`CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${name}\\b[\\s\\S]*?\\$\\$;`, "i"))?.[0] ?? "";
const tableBlock = (name: string): string =>
  up.match(new RegExp(`CREATE\\s+TABLE\\s+IF\\s+NOT\\s+EXISTS\\s+public\\.${name}\\s*\\([\\s\\S]*?\\n\\);`, "i"))?.[0] ?? "";

describe("migration 164_git_data_erasure_pending", () => {
  it("ships with a paired down migration and a verify sentinel", () => {
    expect(existsSync(UP)).toBe(true);
    expect(existsSync(DOWN)).toBe(true);
    expect(existsSync(VERIFY)).toBe(true);
  });

  describe("ledger table", () => {
    const block = tableBlock("git_data_erasure_pending");
    it("keys on workspace_id alone with the Art. 12(3) clock and attempt columns", () => {
      expect(block).not.toBe("");
      expect(block).toMatch(/workspace_id\s+uuid\s+PRIMARY\s+KEY/i);
      expect(block).toMatch(/requested_at\s+timestamptz\s+NOT\s+NULL\s+DEFAULT\s+now\(\)/i);
      expect(block).toMatch(/attempts\s+int\s+NOT\s+NULL\s+DEFAULT\s+0/i);
      expect(block).toMatch(/last_attempt_at\s+timestamptz/i);
    });
    it("has no foreign key and no email/name/user_id column", () => {
      expect(block).not.toMatch(/REFERENCES|FOREIGN\s+KEY/i);
      expect(block).not.toMatch(/\b(email|name|user_id)\b/i);
    });
    it("closes last_outcome to the recorded outcome words (no free text)", () => {
      const m = block.match(/last_outcome\s+text\s+CHECK\s*\(\s*last_outcome\s+IN\s*\(([^)]*)\)/i);
      expect(m, "closed-enum CHECK").not.toBeNull();
      const words = [...m![1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).sort();
      expect(words).toEqual(["host_key_mismatch", "refused", "seeded", "thrown", "unauthorized", "unconfigured", "unreachable"]);
    });
  });

  describe("counter table", () => {
    const block = tableBlock("git_data_erasure_counts");
    it("holds only month, bucket and count, keyed by (month, bucket)", () => {
      expect(block).toMatch(/PRIMARY\s+KEY\s*\(\s*month\s*,\s*bucket\s*\)/i);
      expect(block).not.toMatch(/workspace_id|user_id|REFERENCES|timestamptz|\bid\b/i);
    });
    it("closes bucket to the five elapsed-time buckets", () => {
      for (const b of ["lt_1h", "lt_24h", "lt_7d", "lt_20d", "ge_20d"]) expect(block).toContain(`'${b}'`);
    });
  });

  describe("RLS posture", () => {
    for (const t of ["git_data_erasure_pending", "git_data_erasure_counts"]) {
      it(`${t}: RLS on, no policy, every privilege revoked from all client roles`, () => {
        expect(up).toMatch(new RegExp(`ALTER\\s+TABLE\\s+public\\.${t}\\s+ENABLE\\s+ROW\\s+LEVEL\\s+SECURITY`, "i"));
        expect(up).toMatch(
          new RegExp(`REVOKE\\s+ALL\\s+ON\\s+public\\.${t}\\s+FROM\\s+PUBLIC\\s*,\\s*anon\\s*,\\s*authenticated\\s*,\\s*service_role`, "i"),
        );
      });
    }
    it("creates no policy and does not FORCE row level security", () => {
      expect(up).not.toMatch(/CREATE\s+POLICY/i);
      expect(up).not.toMatch(/FORCE\s+ROW\s+LEVEL\s+SECURITY/i);
    });
  });

  describe("functions", () => {
    for (const [name, args] of FUNCS) {
      it(`${name} is SECURITY DEFINER, pins search_path incl. pg_temp, and is service_role only`, () => {
        const block = fnBlock(name);
        expect(block, `${name} block`).not.toBe("");
        expect(block).toMatch(/SECURITY\s+DEFINER/i);
        expect(block).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
        const sig = args.replace(/,\s*/g, "\\s*,\\s*");
        expect(up).toMatch(
          new RegExp(`REVOKE\\s+ALL\\s+ON\\s+FUNCTION\\s+public\\.${name}\\s*\\(\\s*${sig}\\s*\\)\\s+FROM\\s+PUBLIC\\s*,\\s*anon\\s*,\\s*authenticated`, "i"),
        );
        expect(up).toMatch(
          new RegExp(`GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${name}\\s*\\(\\s*${sig}\\s*\\)\\s+TO\\s+service_role`, "i"),
        );
        expect(up).not.toMatch(new RegExp(`GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${name}[^;]*\\bTO\\s+[^;]*\\b(authenticated|anon|PUBLIC)\\b`, "i"));
      });
    }

    it("record keeps the original requested_at (only last_outcome is updated on conflict)", () => {
      const block = fnBlock("record_git_data_erasure_pending");
      expect(block).toMatch(/ON\s+CONFLICT\s*\(\s*workspace_id\s*\)\s+DO\s+UPDATE\s+SET\s+last_outcome\s*=\s*EXCLUDED\.last_outcome\s*;/i);
      expect(block).not.toMatch(/requested_at\s*=/i);
      expect(block).not.toMatch(/attempts\s*=/i);
    });

    it("claim uses FOR UPDATE SKIP LOCKED and stamps last_attempt_at + attempts in the same statement", () => {
      const block = fnBlock("claim_git_data_erasure_pending");
      expect(block).toMatch(/FOR\s+UPDATE\s+SKIP\s+LOCKED/i);
      expect(block).toMatch(/UPDATE\s+public\.git_data_erasure_pending\s+g\s+SET\s+last_attempt_at\s*=\s*now\(\)\s*,\s*attempts\s*=\s*g\.attempts\s*\+\s*1/i);
      expect(block).toMatch(/last_attempt_at\s*<\s*now\(\)\s*-\s*p_min_interval/i);
    });

    it("claim bounds the limit and refuses an interval shorter than a minute", () => {
      const block = fnBlock("claim_git_data_erasure_pending");
      expect(block).toMatch(/p_limit\s*>\s*100/i);
      expect(block).toMatch(/p_min_interval\s*<\s*interval\s+'1\s+minute'/i);
    });

    it("resolve deletes the row and bumps the counter in ONE statement (data-modifying CTEs), no tombstone", () => {
      const block = fnBlock("resolve_git_data_erasure_pending");
      expect(block).toMatch(/WITH\s+d\s+AS\s*\(\s*DELETE\s+FROM\s+public\.git_data_erasure_pending/i);
      expect(block).toMatch(/INSERT\s+INTO\s+public\.git_data_erasure_counts/i);
      expect(block).toMatch(/ON\s+CONFLICT\s*\(\s*month\s*,\s*bucket\s*\)\s+DO\s+UPDATE\s+SET\s+count\s*=\s*k\.count\s*\+\s*1/i);
      for (const b of ["lt_1h", "lt_24h", "lt_7d", "lt_20d", "ge_20d"]) expect(block).toContain(`'${b}'`);
      expect(block.match(/\bDELETE\b/gi)).toHaveLength(1);
    });

    it("no function purges the ledger on a timer", () => {
      expect(up).not.toMatch(/cron\./i);
      expect(up).not.toMatch(/DELETE\s+FROM\s+public\.git_data_erasure_pending\s+WHERE\s+[^\n]*(now\(\)|interval)/i);
    });
  });

  it("the down migration drops all four functions and both tables", () => {
    for (const [name] of FUNCS) expect(down).toMatch(new RegExp(`DROP\\s+FUNCTION\\s+IF\\s+EXISTS\\s+public\\.${name}\\b`, "i"));
    expect(down).toMatch(/DROP\s+TABLE\s+IF\s+EXISTS\s+public\.git_data_erasure_pending/i);
    expect(down).toMatch(/DROP\s+TABLE\s+IF\s+EXISTS\s+public\.git_data_erasure_counts/i);
  });

  it("the verify sentinel covers grants, RLS, no-policy and the pinned search_path with the bad=1 row format", () => {
    expect(verify).toMatch(/AS\s+bad/i);
    for (const [name] of FUNCS) expect(verify).toContain(name);
    expect(verify).toMatch(/relrowsecurity/);
    expect(verify).toMatch(/pg_policy/);
    expect(verify).toMatch(/search_path=public, pg_temp/);
  });
});
