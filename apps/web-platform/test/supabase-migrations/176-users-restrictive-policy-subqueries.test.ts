import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 176_users_restrictive_policy_subqueries.sql (#10764).
//
// The three RESTRICTIVE FOR UPDATE policies on public.users (migrations 016, 017 x2)
// embed a correlated self-subquery `(SELECT <col> FROM public.users WHERE id =
// auth.uid())` that plans as an InitPlan Seq Scan over the whole table — 17.5s on
// dev's ~295k-row users table, past the ~8s API statement_timeout, so a denied
// cross-tenant UPDATE surfaces 57014 instead of 42501/[] once the table-level
// grant exists. The fix wraps each own-row lookup in a plpgsql STABLE SECURITY
// DEFINER function (plpgsql never inlines — LANGUAGE sql would; DEFINER bypasses
// the caller's SELECT-RLS entanglement that re-hung the INVOKER variant). These tests pin the load-bearing shapes: function language,
// search_path pin, EXECUTE privilege surface, policy-name preservation, and the
// absence of a bare self-subquery in the recreated policy expressions.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/176_users_restrictive_policy_subqueries.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/176_users_restrictive_policy_subqueries.down.sql",
);
const VERIFY_PATH = path.join(
  __dirname,
  "../../supabase/verify/176_users_restrictive_policy_subqueries.sql",
);

const FUNCTIONS: Array<{ name: string; col: string; ret: string }> = [
  { name: "users_own_github_username", col: "github_username", ret: "text" },
  { name: "users_own_kb_sync_history", col: "kb_sync_history", ret: "jsonb" },
  { name: "users_own_health_snapshot", col: "health_snapshot", ret: "jsonb" },
];

const POLICIES = [
  "Users cannot update github_username directly",
  "Users cannot update kb_sync_history directly",
  "Prevent client health_snapshot update",
];

describe("migration 176_users_restrictive_policy_subqueries", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const executable = sql.replace(/--[^\n]*/g, "");

  for (const fn of FUNCTIONS) {
    it(`creates public.${fn.name}() as plpgsql STABLE SECURITY DEFINER returning ${fn.ret}`, () => {
      const re = new RegExp(
        `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${fn.name}\\s*\\(\\s*\\)\\s*` +
          `RETURNS\\s+${fn.ret}[\\s\\S]*?LANGUAGE\\s+plpgsql[\\s\\S]*?STABLE[\\s\\S]*?SECURITY\\s+DEFINER`,
        "i",
      );
      expect(executable).toMatch(re);
    });

    it(`pins search_path on public.${fn.name}()`, () => {
      // The function block must carry an explicit search_path SET (pg_catalog
      // first) so the body's unqualified references cannot be hijacked.
      const fnBlock = new RegExp(
        `FUNCTION\\s+public\\.${fn.name}\\s*\\(\\s*\\)[\\s\\S]*?\\$\\$[\\s\\S]*?\\$\\$`,
        "i",
      );
      const m = executable.match(fnBlock);
      expect(m).not.toBeNull();
      expect(m![0]).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
    });

    it(`${fn.name} does a parameterized PK lookup of the caller's own row`, () => {
      expect(executable).toMatch(
        new RegExp(
          `SELECT\\s+${fn.col}\\s+INTO\\s+\\w+\\s+FROM\\s+public\\.users\\s+WHERE\\s+id\\s*=\\s*auth\\.uid\\s*\\(\\s*\\)`,
          "i",
        ),
      );
    });

    it(`${fn.name} is never LANGUAGE sql (inlinable back into the InitPlan)`, () => {
      const fnBlock = executable.match(
        new RegExp(
          `FUNCTION\\s+public\\.${fn.name}\\s*\\(\\s*\\)[\\s\\S]*?\\$\\$[\\s\\S]*?\\$\\$`,
          "i",
        ),
      );
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).not.toMatch(/LANGUAGE\s+sql\b/i);
    });

    it(`revokes PUBLIC and grants EXECUTE only to authenticated for ${fn.name}`, () => {
      // Supabase default privileges grant EXECUTE to anon/authenticated/
      // service_role explicitly, so the REVOKE must name them, not only PUBLIC.
      expect(executable).toMatch(
        new RegExp(
          `REVOKE\\s+ALL\\s+ON\\s+FUNCTION\\s+public\\.${fn.name}\\s*\\(\\s*\\)\\s+FROM\\s+PUBLIC\\s*,\\s*anon\\s*,\\s*authenticated\\s*,\\s*service_role`,
          "i",
        ),
      );
      expect(executable).toMatch(
        new RegExp(
          `GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${fn.name}\\s*\\(\\s*\\)\\s+TO\\s+authenticated`,
          "i",
        ),
      );
      expect(executable).not.toMatch(
        new RegExp(`GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${fn.name}[^;]*\\bTO\\s+anon\\b`, "i"),
      );
    });
  }

  for (const policy of POLICIES) {
    it(`drops and recreates policy "${policy}" by name`, () => {
      const esc = policy.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      expect(executable).toMatch(
        new RegExp(`DROP\\s+POLICY\\s+IF\\s+EXISTS\\s+"${esc}"\\s+ON\\s+public\\.users`, "i"),
      );
      expect(executable).toMatch(
        new RegExp(`CREATE\\s+POLICY\\s+"${esc}"`, "i"),
      );
    });
  }

  it("recreates each policy with the users_own_ function call, not a bare self-subquery", () => {
    // Every recreated policy expression must route through users_own_*; a bare
    // `(SELECT <col> FROM public.users WHERE id = auth.uid())` inside a policy
    // body is the pathology this migration removes.
    const policyBlocks = executable.match(/CREATE\s+POLICY[\s\S]*?;/gi) ?? [];
    expect(policyBlocks.length).toBeGreaterThanOrEqual(3);
    for (const block of policyBlocks) {
      expect(block).toMatch(/users_own_(github_username|kb_sync_history|health_snapshot)\s*\(/);
      expect(block).not.toMatch(
        /SELECT\s+\w+\s+FROM\s+public\.users\s+WHERE\s+id\s*=\s*auth\.uid/i,
      );
    }
  });

  it("keeps the health_snapshot policy USING-shaped and scoped TO authenticated", () => {
    const block = executable.match(
      /CREATE\s+POLICY\s+"Prevent client health_snapshot update"[\s\S]*?;/i,
    );
    expect(block).not.toBeNull();
    expect(block![0]).toMatch(/TO\s+authenticated/i);
    expect(block![0]).toMatch(/USING\s*\(\s*health_snapshot\s+IS\s+NOT\s+DISTINCT\s+FROM\s+public\.users_own_health_snapshot\s*\(\s*\)\s*\)/i);
    expect(block![0]).not.toMatch(/WITH\s+CHECK/i);
  });

  it("keeps the github/kb_sync policies USING (true) WITH CHECK-shaped", () => {
    for (const [policy, fn] of [
      ["Users cannot update github_username directly", "users_own_github_username"],
      ["Users cannot update kb_sync_history directly", "users_own_kb_sync_history"],
    ] as const) {
      const block = executable.match(
        new RegExp(`CREATE\\s+POLICY\\s+"${policy}"[\\s\\S]*?;`, "i"),
      );
      expect(block).not.toBeNull();
      expect(block![0]).toMatch(/AS\s+RESTRICTIVE\s+FOR\s+UPDATE/i);
      expect(block![0]).toMatch(/USING\s*\(\s*true\s*\)/i);
      expect(block![0]).toMatch(
        new RegExp(`WITH\\s+CHECK\\s*\\(\\s*\\w+\\s+IS\\s+NOT\\s+DISTINCT\\s+FROM\\s+public\\.${fn}\\s*\\(\\s*\\)\\s*\\)`, "i"),
      );
    }
  });

  it("ships a down migration restoring the subquery policies and dropping the functions", () => {
    const down = readFileSync(DOWN_PATH, "utf8");
    const downExec = down.replace(/--[^\n]*/g, "");
    for (const fn of FUNCTIONS) {
      expect(downExec).toMatch(
        new RegExp(`DROP\\s+FUNCTION\\s+IF\\s+EXISTS\\s+public\\.${fn.name}\\s*\\(`, "i"),
      );
    }
    for (const policy of POLICIES) {
      const esc = policy.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      expect(downExec).toMatch(new RegExp(`CREATE\\s+POLICY\\s+"${esc}"`, "i"));
    }
    // The down restores the ORIGINAL subquery shape — the pathology is
    // knowingly reinstated on rollback, matching every other down file.
    expect(downExec).toMatch(
      /SELECT\s+github_username\s+FROM\s+public\.users\s+WHERE\s+id\s*=\s*auth\.uid/i,
    );
  });

  it("ships a verify file asserting functions, policies-by-name, and users_own_ expressions", () => {
    const verify = readFileSync(VERIFY_PATH, "utf8");
    expect(verify).toMatch(/check_name/);
    expect(verify).toMatch(/bad/);
    for (const fn of FUNCTIONS) {
      expect(verify).toContain(fn.name);
    }
    for (const policy of POLICIES) {
      expect(verify).toContain(policy);
    }
    expect(verify).toMatch(/pg_get_expr|pg_get_ruledef|polqual|polwithcheck/i);
  });
});
