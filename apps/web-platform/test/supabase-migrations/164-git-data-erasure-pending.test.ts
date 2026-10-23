import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 164_git_data_erasure_pending.sql (#8211, PR-B1). Offline text lint;
// the behavioural proofs (RLS/grant denial, upsert, SKIP LOCKED, resolve + counter in one
// statement, bucket boundaries, owner_gone) run in test/rls-fuzz/git-data-erasure-pending.integration.test.ts.
// Every pattern is anchored at BOTH ends (a prefix match would pass `k.count + 10`).

const DIR = path.join(__dirname, "../../supabase/migrations");
const UP = path.join(DIR, "164_git_data_erasure_pending.sql");
const DOWN = path.join(DIR, "164_git_data_erasure_pending.down.sql");
const VERIFY = path.join(__dirname, "../../supabase/verify/164_git_data_erasure_pending.sql");

const read = (p: string): string => (existsSync(p) ? readFileSync(p, "utf8") : "");
const exec = (s: string): string => s.replace(/--[^\n]*/g, "");
const up = exec(read(UP));
const down = exec(read(DOWN));
const verifyRaw = read(VERIFY);

/** Words of the migration CHECK (the TS parity test lives with the TS constant, in PR-B2). */
const MIGRATION_OUTCOME_WORDS = (() => {
  const m = up.match(/last_outcome\s+text\s+CHECK\s*\(\s*last_outcome\s+IN\s*\(([^)]*)\)\s*\)/i);
  return m ? [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]) : [];
})();

const FUNCS = [
  ["record_git_data_erasure_pending", "uuid, text, timestamptz"],
  ["claim_git_data_erasure_pending", "int, interval"],
  ["resolve_git_data_erasure_pending", "uuid"],
  ["oldest_git_data_erasure_pending_age", ""],
  ["git_data_erasure_owner_gone", "uuid"],
  ["git_data_erasure_pending_ages", ""],
] as const;

const fnBlock = (name: string): string =>
  up.match(new RegExp(`CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${name}\\b[\\s\\S]*?\\$\\$;`, "i"))?.[0] ?? "";
const tableBlock = (name: string): string =>
  up.match(new RegExp(`CREATE\\s+TABLE\\s+IF\\s+NOT\\s+EXISTS\\s+public\\.${name}\\s*\\([\\s\\S]*?\\n\\);`, "i"))?.[0] ?? "";
const squash = (s: string): string => s.replace(/\s+/g, " ").trim();

describe("migration 164_git_data_erasure_pending", () => {
  it("ships with a paired down migration and a verify sentinel", () => {
    expect(existsSync(UP)).toBe(true);
    expect(existsSync(DOWN)).toBe(true);
    expect(existsSync(VERIFY)).toBe(true);
  });

  it("states the CLO's 2026-10-23 ruling and the 2026-10-24 final re-ruling in the header", () => {
    const raw = read(UP);
    expect(raw).toMatch(/Art\. 6\(1\)\(c\)/);
    expect(raw).toMatch(/2026-10-23/);
    expect(raw).toMatch(/FINAL CLO re-ruling is dated 2026-10-24/);
    expect(raw).toMatch(/record-after-resolve on the same id inserts a FRESH row and so restarts requested_at/);
  });

  describe("ledger table", () => {
    const block = tableBlock("git_data_erasure_pending");
    it("keys on workspace_id alone with the Art. 12(3) clock and attempt columns", () => {
      expect(block).not.toBe("");
      expect(block).toMatch(/workspace_id\s+uuid\s+PRIMARY\s+KEY,/i);
      expect(block).toMatch(/requested_at\s+timestamptz\s+NOT\s+NULL\s+DEFAULT\s+now\(\),/i);
      expect(block).toMatch(/attempts\s+int\s+NOT\s+NULL\s+DEFAULT\s+0\s+CHECK\s*\(\s*attempts\s*>=\s*0\s*\),/i);
      expect(block).toMatch(/last_attempt_at\s+timestamptz,/i);
    });
    it("has no foreign key and no email/name/user_id column", () => {
      expect(block).not.toMatch(/REFERENCES|FOREIGN\s+KEY/i);
      expect(block).not.toMatch(/\b(email|name|user_id)\b/i);
    });
    it("closes last_outcome to exactly the recorded words (no free text, no 'thrown')", () => {
      expect([...MIGRATION_OUTCOME_WORDS].sort()).toEqual(
        ["host_key_mismatch", "refused", "seeded", "threw", "unauthorized", "unconfigured", "unreachable"],
      );
    });
  });

  describe("counter table", () => {
    const block = tableBlock("git_data_erasure_counts");
    it("holds only month, bucket and count, keyed by (month, bucket)", () => {
      expect(block).toMatch(/PRIMARY\s+KEY\s*\(\s*month\s*,\s*bucket\s*\)\s*\n\);$/i);
      expect(block).not.toMatch(/workspace_id|user_id|REFERENCES|timestamptz|\bid\b/i);
    });
    it("closes bucket to exactly the five elapsed-time buckets", () => {
      const m = block.match(/bucket\s+text\s+NOT\s+NULL\s+CHECK\s*\(\s*bucket\s+IN\s*\(([^)]*)\)\s*\)/i);
      expect(m).not.toBeNull();
      expect([...m![1].matchAll(/'([a-z0-9_]+)'/g)].map((x) => x[1])).toEqual(["lt_1h", "lt_24h", "lt_7d", "lt_20d", "ge_20d"]);
    });
  });

  describe("RLS posture", () => {
    for (const t of ["git_data_erasure_pending", "git_data_erasure_counts"]) {
      it(`${t}: RLS on, no policy, every privilege revoked from all client roles`, () => {
        expect(up).toMatch(new RegExp(`ALTER\\s+TABLE\\s+public\\.${t}\\s+ENABLE\\s+ROW\\s+LEVEL\\s+SECURITY\\s*;`, "i"));
        expect(up).toMatch(
          new RegExp(`REVOKE\\s+ALL\\s+ON\\s+public\\.${t}\\s+FROM\\s+PUBLIC\\s*,\\s*anon\\s*,\\s*authenticated\\s*,\\s*service_role\\s*;`, "i"),
        );
      });
    }
    it("creates no policy, does not FORCE row level security, and never GRANTs on either table (before or after the REVOKE)", () => {
      expect(up).not.toMatch(/CREATE\s+POLICY/i);
      expect(up).not.toMatch(/FORCE\s+ROW\s+LEVEL\s+SECURITY/i);
      expect(up).not.toMatch(/GRANT\b[^;]*\bON\s+(TABLE\s+)?public\.git_data_erasure_(pending|counts)\b/i);
      expect(up).not.toMatch(/GRANT\s+(ALL|SELECT|INSERT|UPDATE|DELETE)\b[^;]*\bON\s+ALL\s+TABLES/i);
    });
  });

  describe("functions", () => {
    for (const [name, args] of FUNCS) {
      it(`${name} is SECURITY DEFINER, pins search_path incl. pg_temp, and is service_role only`, () => {
        const block = fnBlock(name);
        expect(block, `${name} block`).not.toBe("");
        expect(block).toMatch(/SECURITY\s+DEFINER/i);
        expect(block).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp\b/i);
        const sig = args.replace(/,\s*/g, "\\s*,\\s*");
        expect(up).toMatch(
          new RegExp(`REVOKE\\s+ALL\\s+ON\\s+FUNCTION\\s+public\\.${name}\\s*\\(\\s*${sig}\\s*\\)\\s+FROM\\s+PUBLIC\\s*,\\s*anon\\s*,\\s*authenticated\\s*;`, "i"),
        );
        expect(up).toMatch(
          new RegExp(`GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${name}\\s*\\(\\s*${sig}\\s*\\)\\s+TO\\s+service_role\\s*;`, "i"),
        );
        expect(up).not.toMatch(new RegExp(`GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${name}[^;]*\\bTO\\s+[^;]*\\b(authenticated|anon|PUBLIC)\\b`, "i"));
      });
    }

    it("record keeps the earlier requested_at, never touches attempts, refuses a NULL outcome and a future value", () => {
      const block = fnBlock("record_git_data_erasure_pending");
      expect(squash(block)).toMatch(
        /ON CONFLICT \(workspace_id\) DO UPDATE SET last_outcome = CASE WHEN EXCLUDED\.last_outcome = 'seeded' THEN g\.last_outcome ELSE EXCLUDED\.last_outcome END, requested_at = LEAST\(g\.requested_at, EXCLUDED\.requested_at\);/i,
      );
      expect(squash(block)).toMatch(/IF p_requested_at IS NOT NULL AND p_requested_at < timestamptz '2020-01-01 00:00:00\+00' THEN RAISE EXCEPTION/i);
      expect(block).not.toMatch(/attempts\s*=/i);
      expect(block).toMatch(/IF\s+p_outcome\s+IS\s+NULL\s+THEN\s+RAISE\s+EXCEPTION/i);
      expect(block).toMatch(/p_requested_at\s+IS\s+NOT\s+NULL\s+AND\s+p_requested_at\s*>\s*now\(\)\s+THEN\s+RAISE\s+EXCEPTION/i);
      expect(block).toMatch(/p_requested_at\s+timestamptz\s+DEFAULT\s+NULL\s*\)/i);
    });

    it("claim uses FOR UPDATE SKIP LOCKED, stamps last_attempt_at + attempts in the same statement, returns oldest first", () => {
      const block = squash(fnBlock("claim_git_data_erasure_pending"));
      expect(block).toMatch(/ORDER BY p\.requested_at, p\.workspace_id LIMIT p_limit FOR UPDATE SKIP LOCKED \)/i);
      expect(block).toMatch(/SET last_attempt_at = now\(\), attempts = g\.attempts \+ 1 FROM picked WHERE g\.workspace_id = picked\.workspace_id RETURNING/i);
      expect(block).toMatch(/p\.last_attempt_at < now\(\) - p_min_interval\b/i);
      expect(block).toMatch(/ORDER BY s\.requested_at, s\.workspace_id; END;/i);
    });

    it("claim bounds the limit to 1..100 and refuses an interval shorter than a minute (tail-anchored)", () => {
      const block = squash(fnBlock("claim_git_data_erasure_pending"));
      expect(block).toMatch(/IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN/i);
      expect(block).toMatch(/IF p_min_interval IS NULL OR p_min_interval < interval '1 minute' THEN/i);
    });

    it("resolve deletes the row and bumps the counter in ONE statement (UTC month), no tombstone", () => {
      const block = squash(fnBlock("resolve_git_data_erasure_pending"));
      expect(block).toMatch(/WITH d AS \( DELETE FROM public\.git_data_erasure_pending WHERE workspace_id = p_workspace_id RETURNING requested_at \)/i);
      expect(block).toMatch(/SELECT date_trunc\('month', now\(\) AT TIME ZONE 'UTC'\)::date, b\.bucket, 1 FROM b ON CONFLICT \(month, bucket\) DO UPDATE SET count = k\.count \+ 1 \)/i);
      expect(block).toMatch(/WHEN now\(\) - d\.requested_at < interval '1 hour' THEN 'lt_1h'/i);
      expect(block).toMatch(/WHEN now\(\) - d\.requested_at < interval '24 hours' THEN 'lt_24h'/i);
      expect(block).toMatch(/WHEN now\(\) - d\.requested_at < interval '7 days' THEN 'lt_7d'/i);
      expect(block).toMatch(/WHEN now\(\) - d\.requested_at < interval '20 days' THEN 'lt_20d'/i);
      expect(block).toMatch(/ELSE 'ge_20d' END/i);
      expect(block.match(/\bDELETE\b/gi)).toHaveLength(1);
    });

    it("oldest age never goes negative and is NULL when empty", () => {
      const block = squash(fnBlock("oldest_git_data_erasure_pending_age"));
      expect(block).toMatch(/CASE WHEN count\(\*\) = 0 THEN NULL ELSE GREATEST\(0, floor\(extract\(epoch FROM \(now\(\) - min\(requested_at\)\)\)\)\)::bigint END FROM public\.git_data_erasure_pending;/i);
    });

    it("owner_gone: exact text of every branch (the branches no live state can separate are pinned here)", () => {
      const block = squash(fnBlock("git_data_erasure_owner_gone"));
      // 1 and 2: auth.users OR public.users => false. The public.users branch is implied by the auth.users
      // branch through the users_id_fkey cascade, so no reachable state separates them live: exact-text pin.
      expect(block).toMatch(/IF EXISTS \(SELECT 1 FROM auth\.users u WHERE u\.id = p_workspace_id\) OR EXISTS \(SELECT 1 FROM public\.users pu WHERE pu\.id = p_workspace_id\) THEN RETURN false; END IF;/i);
      // 3: provenance. A non-seeded ledger row (account-delete) is trusted; anything else must have no members.
      expect(block).toMatch(/SELECT g\.last_outcome INTO v_outcome FROM public\.git_data_erasure_pending g WHERE g\.workspace_id = p_workspace_id; IF FOUND AND v_outcome <> 'seeded' THEN RETURN true;/i);
      expect(block).toMatch(/RETURN NOT EXISTS \(SELECT 1 FROM public\.workspace_members m WHERE m\.workspace_id = p_workspace_id\); END;/i);
      expect(block).toMatch(/IF p_workspace_id IS NULL THEN RAISE EXCEPTION/i);
      // never reads the orphans the saga keeps
      expect(block).not.toMatch(/(FROM|JOIN)\s+public\.(workspaces|organizations)\b/i);
      expect(block).not.toMatch(/workspace_members m WHERE m\.user_id/i);
    });

    it("drops the superseded 2-argument record function before creating the 3-argument form", () => {
      const drop = up.search(/DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.record_git_data_erasure_pending\s*\(\s*uuid\s*,\s*text\s*\)\s*;/i);
      const create = up.search(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.record_git_data_erasure_pending\s*\(\s*p_workspace_id\s+uuid\s*,\s*p_outcome\s+text\s*,\s*p_requested_at/i);
      expect(drop).toBeGreaterThan(-1);
      expect(create).toBeGreaterThan(drop);
    });

    it("pending_ages splits the oldest age by owner_gone, never negative, NULL when a side is empty, and reads only the ledger", () => {
      const block = squash(fnBlock("git_data_erasure_pending_ages"));
      expect(block).toMatch(/RETURNS TABLE \(oldest_gone_seconds bigint, oldest_live_seconds bigint\)/i);
      expect(block).toMatch(/SELECT max\(CASE WHEN public\.git_data_erasure_owner_gone\(g\.workspace_id\) THEN GREATEST\(0, floor\(extract\(epoch FROM \(now\(\) - g\.requested_at\)\)\)\)::bigint END\), max\(CASE WHEN NOT public\.git_data_erasure_owner_gone\(g\.workspace_id\) THEN GREATEST\(0, floor\(extract\(epoch FROM \(now\(\) - g\.requested_at\)\)\)\)::bigint END\) FROM public\.git_data_erasure_pending g;/i);
    });

    it("no function purges the ledger on a timer", () => {
      expect(up).not.toMatch(/cron\./i);
      expect(up).not.toMatch(/DELETE\s+FROM\s+public\.git_data_erasure_pending\s+WHERE\s+[^\n]*(now\(\)|interval)/i);
    });
  });

  it("the down migration drops all six functions and both tables, and refuses while the ledger holds rows", () => {
    for (const [name] of FUNCS) expect(down).toMatch(new RegExp(`DROP\\s+FUNCTION\\s+IF\\s+EXISTS\\s+public\\.${name}\\s*\\(`, "i"));
    expect(down).toMatch(/DROP\s+TABLE\s+IF\s+EXISTS\s+public\.git_data_erasure_pending\s*;/i);
    expect(down).toMatch(/DROP\s+TABLE\s+IF\s+EXISTS\s+public\.git_data_erasure_counts\s*;/i);
    const guard = squash(down.match(/DO\s+\$\$[\s\S]*?END\s+\$\$;/i)?.[0] ?? "");
    // exact, anchored: a NOT EXISTS / IS NULL / inverted variant must not pass
    expect(guard).toMatch(
      /^DO \$\$ BEGIN IF to_regclass\('public\.git_data_erasure_pending'\) IS NOT NULL AND EXISTS \(SELECT 1 FROM public\.git_data_erasure_pending\) THEN RAISE EXCEPTION 'Refusing to drop git_data_erasure_pending: it holds pending erasures\. Resolve or export them first\.'; END IF; END \$\$;$/,
    );
    expect(down.indexOf("RAISE EXCEPTION")).toBeLessThan(down.search(/DROP\s+FUNCTION/i));
  });

  describe("verify sentinel", () => {
    const verify = exec(verifyRaw);
    it("uses the bad=1 row format and covers every function, both tables, RLS, policies and privileges", () => {
      expect(verify).toMatch(/AS\s+bad/i);
      for (const [name] of FUNCS) expect(verify).toContain(name);
      expect(verify).toMatch(/relrowsecurity/);
      expect(verify).toMatch(/pg_policy/);
      expect(verify).toMatch(/search_path=public, pg_temp/);
    });
    it("compares every CHECK to its FULL definition text (no LIKE) and pins the exact column set of both tables", () => {
      expect(verify).not.toMatch(/\bLIKE\b/i);
      expect(verify).toContain("CHECK ((last_outcome = ANY (ARRAY[''refused''::text, ''unreachable''::text, ''unauthorized''::text, ''unconfigured''::text, ''host_key_mismatch''::text, ''threw''::text, ''seeded''::text])))");
      expect(verify).toContain("CHECK ((bucket = ANY (ARRAY[''lt_1h''::text, ''lt_24h''::text, ''lt_7d''::text, ''lt_20d''::text, ''ge_20d''::text])))");
      expect(verify).toContain("attempts:integer:NO,last_attempt_at:timestamp with time zone:YES,last_outcome:text:YES,requested_at:timestamp with time zone:NO,workspace_id:uuid:NO");
      expect(verify).toContain("bucket:text:NO,count:bigint:NO,month:date:NO");
      expect(verify).toMatch(/information_schema\.columns/);
    });
    it("the verify words equal the migration words (no hand-restated drift)", () => {
      const m = verify.match(/last_outcome = ANY \(ARRAY\[([^\]]*)\]/);
      const words = [...(m?.[1] ?? "").matchAll(/''([a-z_]+)''::text/g)].map((x) => x[1]);
      expect(words).toEqual(MIGRATION_OUTCOME_WORDS);
    });
  });
});
