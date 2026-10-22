import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Shape test for 163_renormalize_repo_url.sql (#10633). A regression TRIPWIRE
// over the committed text, not proof of runtime behaviour: the runtime evidence
// is the one-time dev rehearsal, the Postgres-generated golden table in
// test/repo-url-sql-parity.test.ts, and the strict verify/163 sentinel that runs
// on every deploy.
//
// What it pins: the order of the lock, the precondition and the UPDATEs; the
// precondition's own filters (scoped to its BODY, since the same tokens appear
// in the UPDATEs); a count-only error text; and that every copy of the
// canonical expression (migration, verify, golden script) is the same text.

const ROOT = path.resolve(__dirname, "../..");
const MIGRATION = readFileSync(path.join(ROOT, "supabase/migrations/163_renormalize_repo_url.sql"), "utf8");
const DOWN = readFileSync(path.join(ROOT, "supabase/migrations/163_renormalize_repo_url.down.sql"), "utf8");
const VERIFY = readFileSync(path.join(ROOT, "supabase/verify/163_renormalize_repo_url.sql"), "utf8");
const GOLDEN = readFileSync(path.join(ROOT, "test/fixtures/sql/normalize-repo-url-163-golden.sql"), "utf8");

const stripComments = (sql: string) => sql.replace(/--[^\n]*/g, "");
const collapse = (s: string) => s.replace(/\s+/g, " ").trim();

// The markers are comments, so extract BEFORE stripping comments.
function canonBlocks(sql: string): string[] {
  return [...sql.matchAll(/-- canon-expr begin([\s\S]*?)-- canon-expr end/g)].map((m) => collapse(m[1]!));
}

const executable = stripComments(MIGRATION);

describe("migration 163_renormalize_repo_url", () => {
  it("has no transaction control and no CONCURRENTLY (the runner wraps the file)", () => {
    expect(executable).not.toMatch(/\bBEGIN\s*;/i);
    expect(executable).not.toMatch(/\bCOMMIT\b/i);
    expect(executable).not.toMatch(/\bCONCURRENTLY\b/i);
  });

  it("takes the lock under a lock_timeout before the precondition, which precedes every UPDATE", () => {
    const timeout = executable.search(/SET LOCAL lock_timeout = '5s';/);
    const lock = executable.search(/LOCK TABLE public\.conversations IN SHARE ROW EXCLUSIVE MODE;/);
    const doBlock = executable.search(/DO \$\$/);
    const firstUpdate = executable.search(/\bUPDATE\b/);
    expect(timeout).toBeGreaterThanOrEqual(0);
    expect(lock).toBeGreaterThan(timeout);
    expect(doBlock).toBeGreaterThan(lock);
    expect(firstUpdate).toBeGreaterThan(doBlock);
  });

  it("updates both live tables, guarded by eligibility and by inequality", () => {
    expect(executable).toMatch(/UPDATE public\.conversations t\s+SET repo_url = n\.canon_ok/);
    expect(executable).toMatch(/UPDATE public\.workspaces t\s+SET repo_url = n\.canon_ok/);
    expect(executable.match(/n\.canon_ok IS NOT NULL/g)?.length).toBe(2);
    expect(executable.match(/t\.repo_url <> n\.canon_ok/g)?.length).toBe(2);
  });

  it("does not touch the dropped users table", () => {
    expect(executable).not.toMatch(/public\.users/i);
  });

  describe("precondition DO block", () => {
    const body = executable.split("DO $$")[1]!.split("END $$")[0]!;

    it("filters on the unique index's own coverage inside its body", () => {
      expect(body).toMatch(/x\.repo_url IS NOT NULL/);
      expect(body).toMatch(/x\.context_path IS NOT NULL/);
      expect(body).toMatch(/x\.archived_at IS NULL/);
      expect(body).toMatch(/GROUP BY x\.user_id, COALESCE\(c\.canon_ok, x\.repo_url\), x\.context_path/);
      expect(body).toMatch(/HAVING count\(\*\) > 1/);
    });

    it("raises with a count only: one placeholder, one count variable, no row data", () => {
      const raises = [...body.matchAll(/RAISE EXCEPTION ('[^']*')\s*,([^;]*);/g)];
      expect(raises.length).toBe(1);
      expect(raises[0]![1]!.match(/%/g)?.length).toBe(1);
      expect(raises[0]![2]!.trim()).toBe("collisions");
      expect(body).toMatch(/SELECT count\(\*\) INTO collisions/);
    });
  });

  it("never prints a DETAIL or HINT", () => {
    expect(MIGRATION).not.toMatch(/USING\s+(DETAIL|HINT)/i);
  });

  it("down file is an explicit no-op", () => {
    const down = stripComments(DOWN);
    expect(down).not.toMatch(/\b(DROP|DELETE|UPDATE|INSERT|ALTER|TRUNCATE)\b/i);
    expect(down).toMatch(/SELECT 1;/);
  });
});

describe("canonical expression identity (migration, verify, golden script)", () => {
  it("every canon-expr copy is the same text", () => {
    const migration = canonBlocks(MIGRATION);
    const verify = canonBlocks(VERIFY);
    const golden = canonBlocks(GOLDEN);
    expect(migration.length).toBe(3); // precondition + two UPDATEs
    expect(verify.length).toBe(3); // two probes + the selftest
    expect(golden.length).toBe(1);
    expect(new Set([...migration, ...verify, ...golden]).size).toBe(1);
  });

  it("the expression carries the ASCII whitespace class in both trim and tail strip", () => {
    const [expr] = canonBlocks(MIGRATION);
    expect(expr).toContain("'^[ \\t\\n\\r\\f\\v]+|[ \\t\\n\\r\\f\\v]+$'");
    expect(expr).toContain("'(/|\\.git|[ \\t\\n\\r\\f\\v])+$'");
    expect(expr).not.toContain("[[:space:]]");
  });
});

describe("verify/163_renormalize_repo_url", () => {
  const code = stripComments(VERIFY);

  it("emits exactly the three named checks", () => {
    const names = new Set([...code.matchAll(/SELECT\s+'([a-z_]+)'/g)].map((m) => m[1]));
    expect(names).toEqual(new Set(["conversations_noncanonical", "workspaces_noncanonical", "canon_expr_selftest"]));
  });

  it("binds each probe to its table and to the non-canonical polarity", () => {
    const conv = code.split("UNION ALL")[0]!;
    const ws = code.split("UNION ALL")[1]!;
    const self = code.split("UNION ALL")[2]!;
    expect(conv).toMatch(/'conversations_noncanonical'[\s\S]*FROM public\.conversations x/);
    expect(ws).toMatch(/'workspaces_noncanonical'[\s\S]*FROM public\.workspaces x/);
    for (const probe of [conv, ws]) {
      expect(probe).toMatch(/c\.canon_ok IS NOT NULL/);
      expect(probe).toMatch(/x\.repo_url <> c\.canon_ok/);
    }
    expect(self).toMatch(/c\.canon_ok IS DISTINCT FROM x\.expected/);
  });

  it("selftest fixtures expect rewrites AND NULL for ineligible inputs", () => {
    const self = code.split("UNION ALL")[2]!;
    expect(self.match(/, NULL\)/g)?.length).toBeGreaterThanOrEqual(8);
    expect(self).toMatch(/'http:\/\/a\.aa '::text, 'http:\/\/a\.aa'::text/);
  });

  it("does not reference the dropped users table", () => {
    expect(code).not.toMatch(/public\.users/i);
  });
});
