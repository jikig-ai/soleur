import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 136_workflow_cost_rollup.sql.
//
// File-parse only, mirroring 032-workflow-state.test.ts. It asserts the SQL's
// SHAPE; it deliberately asserts no OUTPUT VALUES (tasks.md 1.2.1 / AC15b) --
// behaviour is covered by the live-dev ACs and by the loader suite.
//
// Anchoring note: every assertion below anchors on a syntactic construct, never
// on a bare token. `search_path`, `__unrouted__` and `date_trunc` all appear in
// this migration's own header comments, so a bare-token grep would pass
// vacuously against prose while the real statement drifted.
//
// Plan: 2026-09-07-feat-per-workflow-agent-cost-observability-plan.md Phase 1.

const MIGRATIONS_DIR = path.join(__dirname, "../../supabase/migrations");
const MIGRATION_PATH = path.join(
  MIGRATIONS_DIR,
  "136_workflow_cost_rollup.sql",
);
const DOWN_PATH = path.join(
  MIGRATIONS_DIR,
  "136_workflow_cost_rollup.down.sql",
);
const ROUTING_PATH = path.join(__dirname, "../../server/conversation-routing.ts");

const NEW_FN = "sum_user_mtd_cost_by_workflow";

const sql = readFileSync(MIGRATION_PATH, "utf8");

/**
 * Slice the body of one `CREATE OR REPLACE FUNCTION public.<name>` up to its
 * `$$;` terminator.
 *
 * The explicit -1 guards are load-bearing: `String.prototype.slice` with a -1
 * start silently returns the last character, so a failed anchor match would
 * yield a one-char "body" against which every `.not.toMatch()` passes. A body
 * that cannot be located is a test defect and must throw, not degrade.
 */
function functionBody(source: string, fnName: string): string {
  const startRe = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${fnName}\\b`,
  );
  const m = startRe.exec(source);
  if (m === null) {
    throw new Error(`functionBody: no CREATE ... public.${fnName} found`);
  }
  const start = m.index;
  const end = source.indexOf("$$;", start);
  if (end === -1) {
    throw new Error(`functionBody: no $$; terminator after public.${fnName}`);
  }
  return source.slice(start, end + "$$;".length);
}

describe("migration 136_workflow_cost_rollup", () => {
  it("declares the new aggregate function", () => {
    expect(sql).toMatch(
      new RegExp(`CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${NEW_FN}\\s*\\(`),
    );
  });

  // --- 1.2.1 -- the CASE arms -----------------------------------------------

  it("maps exactly {legacy, unrouted} in the CASE THEN arms", () => {
    const body = functionBody(sql, NEW_FN);
    const thens = [...body.matchAll(/\bTHEN\s+'([^']*)'/gi)].map((m) => m[1]);
    // Exactly two mapped literals, no more: a third arm would be a bucket the
    // loader's copy map does not know about.
    expect(thens).toEqual(["legacy", "unrouted"]);
  });

  it("passes active_workflow through unmodified in the ELSE arm", () => {
    const body = functionBody(sql, NEW_FN);
    // ELSE must yield the bare column, not a wrapped/cast/coalesced form.
    expect(body).toMatch(/\bELSE\s+c\.active_workflow\s+END\b/i);
  });

  // --- 1.2.2 -- one statement, ROLLUP ---------------------------------------

  it("uses GROUP BY ROLLUP", () => {
    const body = functionBody(sql, NEW_FN);
    expect(body).toMatch(/GROUP\s+BY\s+ROLLUP\s*\(/i);
  });

  it("contains exactly one SELECT-list statement in the body (AC3)", () => {
    const body = functionBody(sql, NEW_FN);
    // Strip line comments so a `-- SELECT ...` explanation cannot inflate the
    // count (the comment-prose false-match class).
    const code = body.replace(/--[^\n]*/g, "");
    // Two SELECTs are expected by construction: the outer projection and the
    // derived table it reads from -- but only ONE statement, so exactly one
    // semicolon-terminated unit. Assert on statement count, not SELECT count.
    const statements = code
      .split(/;\s*$/m)
      .map((s) => s.trim())
      .filter((s) => /\bSELECT\b/i.test(s));
    expect(statements).toHaveLength(1);
  });

  // --- 1.2.3 -- no table DDL; pg_temp on BOTH functions ---------------------

  it("contains no table DDL", () => {
    const code = sql.replace(/--[^\n]*/g, "");
    expect(code).not.toMatch(/\bCREATE\s+TABLE\b/i);
    expect(code).not.toMatch(/\bALTER\s+TABLE\b/i);
    expect(code).not.toMatch(/\bDROP\s+TABLE\b/i);
  });

  it("pins search_path = public, pg_temp on BOTH functions", () => {
    for (const fn of [NEW_FN, "sum_user_mtd_cost"]) {
      const body = functionBody(sql, fn);
      expect(
        body,
        `${fn} must pin pg_temp (cq-pg-security-definer-search-path-pin-pg-temp)`,
      ).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp\b/i);
    }
  });

  it("repins the pre-existing sum_user_mtd_cost (027 shipped search_path=public only)", () => {
    expect(sql).toMatch(
      /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.sum_user_mtd_cost\s*\(/,
    );
  });

  // --- 1.2.4 -- the window is a parameter, not a literal --------------------

  it("does not compute date_trunc('month', now()) inside the function body", () => {
    // Scoped to the body on purpose: the header comment legitimately names the
    // expression when explaining why the caller owns the window (tasks 1.2.4).
    const body = functionBody(sql, NEW_FN);
    expect(body).not.toMatch(/date_trunc\s*\(\s*'month'/i);
  });

  // --- 1.2.5 -- the sentinel pin (Guard 1 / AC15) ---------------------------

  it("pins the '__unrouted__' literal to SENTINEL_UNROUTED in conversation-routing.ts", () => {
    const routing = readFileSync(ROUTING_PATH, "utf8");
    const declared = /const\s+SENTINEL_UNROUTED\s*=\s*"([^"]+)"/.exec(routing);
    expect(
      declared,
      "SENTINEL_UNROUTED declaration not found in conversation-routing.ts",
    ).not.toBeNull();
    const sentinel = declared![1];

    const body = functionBody(sql, NEW_FN);
    const code = body.replace(/--[^\n]*/g, "");
    const occurrences = [...code.matchAll(/'__unrouted__'/g)];
    // Exactly one: a second copy is a place for the two to drift apart.
    expect(occurrences).toHaveLength(1);
    expect(code).toContain(`'${sentinel}'`);
  });

  // --- grants ----------------------------------------------------------------

  it("revokes from PUBLIC, authenticated and anon, and grants only service_role", () => {
    for (const role of ["PUBLIC", "authenticated", "anon"]) {
      expect(sql).toMatch(
        new RegExp(
          `REVOKE\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${NEW_FN}[^;]*FROM\\s+${role}\\b`,
          "i",
        ),
      );
    }
    expect(sql).toMatch(
      new RegExp(
        `GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${NEW_FN}[^;]*TO\\s+service_role\\b`,
        "i",
      ),
    );
    // No broader grant may follow.
    expect(sql).not.toMatch(
      new RegExp(
        `GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${NEW_FN}[^;]*TO\\s+(authenticated|anon|PUBLIC)\\b`,
        "i",
      ),
    );
  });

  it("is SECURITY DEFINER and STABLE", () => {
    const body = functionBody(sql, NEW_FN);
    expect(body).toMatch(/SECURITY\s+DEFINER/i);
    expect(body).toMatch(/\bSTABLE\b/i);
  });

  // --- down migration --------------------------------------------------------

  describe("136_workflow_cost_rollup.down.sql", () => {
    const down = readFileSync(DOWN_PATH, "utf8");

    it("drops the new function", () => {
      expect(down).toMatch(
        new RegExp(`DROP\\s+FUNCTION\\s+IF\\s+EXISTS\\s+public\\.${NEW_FN}\\s*\\(`, "i"),
      );
    });

    it("does NOT restore sum_user_mtd_cost to its 027 shape", () => {
      // Task 1.4: restoring 027 would re-introduce the missing pg_temp that
      // this migration exists to fix. The down migration must leave it alone.
      const code = down.replace(/--[^\n]*/g, "");
      expect(code).not.toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.sum_user_mtd_cost\b/i,
      );
      expect(code).not.toMatch(/DROP\s+FUNCTION[^;]*\bsum_user_mtd_cost\s*\(/i);
    });
  });
});
