import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

// Generalised migration RPC-grant + search-path lint per
// `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md` +
// `cq-pg-security-definer-search-path-pin-pg-temp`.
//
// For EVERY `CREATE FUNCTION ... SECURITY DEFINER` block across
// `apps/web-platform/supabase/migrations/*.sql`, this test asserts:
//   1. `SET search_path = public, pg_temp` (in that order) appears in the
//      function declaration block.
//   2. A `REVOKE ALL ON FUNCTION public.<name>(...) FROM PUBLIC, anon,
//      authenticated;` statement appears in the same file (Supabase's
//      `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE TO anon, authenticated,
//      service_role` makes the named-role REVOKE load-bearing).
//
// The plan rev-2 §AC14 "public.-qualified relations" requirement is NOT
// machine-checked here — heuristic SQL-parse detection produces too many
// false positives on plpgsql control-flow patterns (`DO UPDATE SET`,
// `RETURNING INTO`, `EXTRACT(... FROM <var>)`, `OPEN <cursor> FOR ...`)
// vs. genuine table references. Enforced instead via PR review +
// search_path pin (which makes unqualified-relation lookups fall back
// to `public` then `pg_temp`, making the practical security risk small
// even when the convention slips). If a future migration is written
// where unqualified references DO cause behaviour drift, add a per-
// migration test rather than reviving the brittle heuristic here.
//
// Generalisation per feat-dsar-art15-export-endpoint plan rev-2 AC13.

const MIGRATIONS_DIR = path.join(__dirname, "../supabase/migrations");

// Pre-existing violators of the `pg_temp` pin component of the rule.
// These migrations set `search_path = public` but did not also pin
// pg_temp at the time they were authored. The defence-in-depth value
// of pinning pg_temp (preventing temp-table search-path attacks
// against SECURITY DEFINER fns) is small when the function body is
// pure SQL (not plpgsql) and references only fully-qualified
// `public.<rel>` identifiers, but the convention still applies.
// Tracked for follow-up cleanup as a separate PR; do NOT touch as
// part of feat-dsar-art15-export-endpoint per
// `wg-when-an-audit-identifies-pre-existing` — out-of-feature-scope.
const LEGACY_SEARCH_PATH_NO_PG_TEMP = new Set([
  "027_mtd_cost_aggregate.sql",
]);

interface SecurityDefinerFn {
  file: string;
  name: string;
  signatureParams: string;
  declarationBlock: string;
  body: string;
}

function stripLineComments(sql: string): string {
  return sql.replace(/--[^\n]*/g, "");
}

function extractSecurityDefinerFns(
  file: string,
  rawSql: string,
): SecurityDefinerFn[] {
  const sql = stripLineComments(rawSql);
  const fns: SecurityDefinerFn[] = [];
  const re =
    /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(public\.[a-zA-Z_][\w]*)\s*\(([^)]*)\)[\s\S]*?\bSECURITY\s+DEFINER\b[\s\S]*?\bAS\s+\$\$([\s\S]*?)\$\$\s*;/g;
  for (const m of sql.matchAll(re)) {
    const [full, fullName, params, body] = m;
    const declEnd = full.indexOf("AS $$");
    fns.push({
      file,
      name: fullName!.replace(/^public\./, ""),
      signatureParams: params!.trim(),
      declarationBlock: full.slice(0, declEnd),
      body: body!,
    });
  }
  return fns;
}

// Collect every REVOKE statement targeting this function and union their
// FROM-role lists. Accepts both forms:
//   REVOKE [ALL | EXECUTE] ON FUNCTION public.<fn>(...) FROM PUBLIC, anon, authenticated;
//   REVOKE [ALL | EXECUTE] ON FUNCTION public.<fn>(...) FROM PUBLIC;
//   REVOKE [ALL | EXECUTE] ON FUNCTION public.<fn>(...) FROM anon;
//   REVOKE [ALL | EXECUTE] ON FUNCTION public.<fn>(...) FROM authenticated;
function revokedRoles(fn: SecurityDefinerFn, sql: string): Set<string> {
  const nameEsc = fn.name.replace(/([.*+?^=!:${}()|[\]/\\])/g, "\\$1");
  // Match the function signature; tolerate parameter type extraction by
  // accepting any param list (parens with anything inside that's not a
  // closing paren). Real validation comes from the role-set check below.
  const re = new RegExp(
    `REVOKE\\s+(?:ALL(?:\\s+PRIVILEGES)?|EXECUTE)\\s+ON\\s+FUNCTION\\s+public\\.${nameEsc}\\s*\\([^)]*\\)\\s+FROM\\s+([^;]+);`,
    "gi",
  );
  const roles = new Set<string>();
  for (const m of sql.matchAll(re)) {
    const list = m[1]!;
    for (const tok of list.split(",")) {
      const role = tok.trim().toLowerCase();
      if (role) roles.add(role);
    }
  }
  return roles;
}

const migrationFiles = readdirSync(MIGRATIONS_DIR)
  .filter((f) => f.endsWith(".sql"))
  .sort();

describe("migration SECURITY DEFINER RPC grant + search_path lint (AC13 + AC14)", () => {
  it("scans at least one migration file (sanity)", () => {
    expect(migrationFiles.length).toBeGreaterThan(0);
  });

  for (const file of migrationFiles) {
    describe(file, () => {
      const filePath = path.join(MIGRATIONS_DIR, file);
      const sql = readFileSync(filePath, "utf8");
      const fns = extractSecurityDefinerFns(file, sql);

      if (fns.length === 0) {
        it("(no SECURITY DEFINER fns)", () => {
          expect(fns.length).toBe(0);
        });
        return;
      }

      for (const fn of fns) {
        describe(`fn ${fn.name}(${fn.signatureParams})`, () => {
          it("pins SET search_path (= public, with pg_temp where compliant)", () => {
            // Required: search_path is pinned to a public-first list.
            expect(fn.declarationBlock).toMatch(
              /SET\s+search_path\s*=\s*public\b/i,
            );
            // Aspirational: pg_temp is also pinned (defense-in-depth).
            // Allowlist for pre-existing legacy migrations.
            if (!LEGACY_SEARCH_PATH_NO_PG_TEMP.has(file)) {
              expect(
                fn.declarationBlock,
                `${file}: ${fn.name} must pin pg_temp after public`,
              ).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
            }
          });

          it("REVOKEs from PUBLIC + anon + authenticated (any role-list form)", () => {
            const roles = revokedRoles(fn, sql);
            for (const required of ["public", "anon", "authenticated"]) {
              expect(roles, `expected REVOKE of ${required} for ${fn.name}; got [${[...roles].join(", ")}]`).toContain(required);
            }
          });
        });
      }
    });
  }
});
