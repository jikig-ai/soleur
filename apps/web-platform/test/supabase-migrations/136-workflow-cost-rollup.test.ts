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
// Plan: 20260908-094911-2026-09-07-feat-per-workflow-agent-cost-observability-plan.md (archived under knowledge-base/project/plans/archive/) Phase 1.

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
/** Strip `--` line comments. Every assertion over SQL must run on this. */
function stripSqlComments(sqlText: string): string {
  return sqlText.replace(/--[^\n]*/g, "");
}

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
    // Comment-stripped. Collecting from the RAW body was a live false-match:
    // a mutant changing `THEN 'legacy'` to `THEN NULL` while adding a comment
    // line that merely QUOTES the original arm passed 20/20. That mutant is
    // fatal -- legacy rows would emit bucket = NULL, colliding with the ROLLUP
    // super-aggregate, and the loader's `typeof r.bucket === "string"` filter
    // then silently drops that money under a "Nothing is left out" promise.
    // The file header claimed this guard; only two of the three tests had it.
    const body = stripSqlComments(functionBody(sql, NEW_FN));
    const thens = [...body.matchAll(/\bTHEN\s+'([^']*)'/gi)].map((m) => m[1]);
    // The CASE must have no NULL-yielding arm at all: `bucket IS NULL` is the
    // ROLLUP super-aggregate's own signal and must stay unambiguous.
    expect(body).not.toMatch(/\bTHEN\s+NULL\b/i);
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

  it("the synthetic bucket keys cannot collide with a real workflow name", () => {
    // `legacy` and `unrouted` are minted into the SAME string space as raw
    // `active_workflow` values. Nothing in migration 032 forbids a future
    // enum entry literally named `legacy` -- if one landed, real spend would
    // merge silently into the unattributed bucket AND `WorkflowBucket` would
    // collapse the union with no type error, because the synthetic key is
    // already a member. This asserts the CHECK enum stays disjoint from them.
    const chk = readFileSync(
      path.join(MIGRATIONS_DIR, "032_conversation_workflow_state.sql"),
      "utf8",
    );
    const code = stripSqlComments(chk);
    for (const synthetic of ["legacy", "unrouted"]) {
      expect(
        code,
        `migration 032's CHECK enum must not contain '${synthetic}' — it is a synthetic bucket key minted by 136`,
      ).not.toMatch(new RegExp(`'${synthetic}'`, "i"));
    }
  });

  // --- the WHERE predicate: tenant scope and window ------------------------
  //
  // Neither of these was asserted, and both mutants passed 20/20:
  //   `WHERE c.user_id = uid` -> `WHERE TRUE`   (cross-tenant read from a
  //      SECURITY DEFINER function -- the grant tests cannot see it, because
  //      the grant chain stays intact and it is the BODY that leaks)
  //   delete `AND c.created_at >= since`        (MTD silently becomes all-time)
  // The window test below only asserted `date_trunc` was ABSENT, which a
  // deletion satisfies trivially.

  it("scopes rows to the requesting user (a cross-tenant read is a body defect, not a grant defect)", () => {
    const body = stripSqlComments(functionBody(sql, NEW_FN));
    expect(body).toMatch(/WHERE\s+c\.user_id\s*=\s*uid\b/i);
    expect(body).not.toMatch(/WHERE\s+TRUE\b/i);
  });

  it("bounds rows by the caller-supplied window", () => {
    const body = stripSqlComments(functionBody(sql, NEW_FN));
    expect(body).toMatch(/AND\s+c\.created_at\s*>=\s*since\b/i);
  });

  it("counts only costed conversations", () => {
    const body = stripSqlComments(functionBody(sql, NEW_FN));
    expect(body).toMatch(/AND\s+c\.total_cost_usd\s*>\s*0\b/i);
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

  // Loops BOTH functions, not just the new one. Migration 027's own header
  // states the rule: "on FIRST create Postgres grants EXECUTE to PUBLIC by
  // default. The REVOKE statements below MUST run on every apply -- treating
  // them as 'cleanup' after the CREATE is a real security gap." Because 136
  // re-creates `sum_user_mtd_cost` via CREATE OR REPLACE, it owns that rule
  // too: on any apply where the function is ABSENT (a `db reset` against a
  // squashed baseline postdating 027, a fresh project bootstrapped from
  // `db diff`, or a DROP during incident recovery followed by forward-only
  // replay) the REPLACE becomes a first CREATE and PUBLIC gets EXECUTE.
  //
  // This assertion previously ran over NEW_FN only, which is why the omission
  // shipped -- and a live `proacl` read could not catch it either, since dev
  // had 027 already applied, the one state in which it is invisible.
  it.each([NEW_FN, "sum_user_mtd_cost"])(
    "revokes %s from PUBLIC, authenticated and anon, and grants only service_role",
    (fn) => {
      for (const role of ["PUBLIC", "authenticated", "anon"]) {
        expect(
          sql,
          `${fn} must REVOKE EXECUTE FROM ${role} in this migration`,
        ).toMatch(
          new RegExp(
            `REVOKE\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${fn}\\s*\\([^)]*\\)[^;]*FROM\\s+${role}\\b`,
            "i",
          ),
        );
      }
      expect(sql).toMatch(
        new RegExp(
          `GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${fn}\\s*\\([^)]*\\)[^;]*TO\\s+service_role\\b`,
          "i",
        ),
      );
      // No broader grant may follow.
      expect(sql).not.toMatch(
        new RegExp(
          `GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${fn}\\s*\\([^)]*\\)[^;]*TO\\s+(authenticated|anon|PUBLIC)\\b`,
          "i",
        ),
      );
    },
  );

  // 046/052/054/064/066 all pin a COMMENT; this migration asserted none. The
  // gap matters for the SAME reason the REVOKE trio does: on a first CREATE
  // there is no prior comment to preserve, so 027's is lost exactly where the
  // REVOKE block is load-bearing.
  it.each([NEW_FN, "sum_user_mtd_cost"])(
    "issues COMMENT ON FUNCTION for %s",
    (fn) => {
      expect(sql).toMatch(
        new RegExp(
          `COMMENT\\s+ON\\s+FUNCTION\\s+public\\.${fn}\\s*\\([^)]*\\)\\s+IS`,
          "i",
        ),
      );
    },
  );

  it("contains no blanket schema-wide grant", () => {
    // The per-function negative grant regex anchors on `public.<fn>`, so a
    // trailing `GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO
    // authenticated;` slipped past it (and past migration-rpc-grants.test.ts,
    // which has no ALL FUNCTIONS rule either).
    const code = stripSqlComments(sql);
    expect(code).not.toMatch(/GRANT[^;]*ON\s+ALL\s+FUNCTIONS\s+IN\s+SCHEMA/i);
    expect(code).not.toMatch(/GRANT[^;]*ON\s+ALL\s+TABLES\s+IN\s+SCHEMA/i);
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
