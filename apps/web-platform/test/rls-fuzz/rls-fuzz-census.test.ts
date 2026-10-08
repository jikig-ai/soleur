import { describe, test, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

// Standing guard for the plan's AC6 census (#9779): every bare `sql`-handle
// statement in this directory must ride withTransientRetry — parallel vitest
// workers share ONE disposable Postgres, so an unwrapped statement on the raw
// handle is an unretried deadlock victim that only ever surfaces as an
// intermittent CI flake (every spec here is describe.skipIf(!RLS_FUZZ_LOCAL),
// so nothing local reddens it). This file pins the two census greps so a new
// bare `sql` call fails deterministically instead. Anchored on call forms a
// comment cannot produce once comments are stripped, and each check carries a
// seeded-offender self-test so the guard cannot pass vacuously. Scope: single-
// line call shapes on a handle literally named `sql` — a multi-line `await`/
// `sql` split or a renamed handle would evade the regex; the suite's style keeps
// every call on one line and every handle named `sql`.

const DIR = __dirname;

// Unit-test files stub the sql handle and this file contains the patterns
// themselves — neither is a statement that reaches Postgres.
const EXEMPT_FILES = new Set([
  "harness-fixture.test.ts",
  "local-dsn-guard.test.ts",
  "verdict.test.ts",
  "rls-fuzz-census.test.ts",
]);

// Census B allowlist (from the plan): helpers that (a) self-wrap internally,
// (b) take the raw `sql` handle before any transaction exists, or
// (c) are catalog fns that wrap internally.
const ALLOWED_BARE_SQL_CALLS = new Set([
  "asTenant",
  "attackAs",
  "attackAsAnon",
  "rolledBackRaw",
  "seedTwoTenant",
  "seedRpcCtx",
  "connect",
  "assertLocalDsn",
  "isolationSet",
  "workspaceTenancyTables",
  "userIsolationTables",
  "rowHijackTables",
  "jtiDenySet",
  "securityDefinerAuthenticatedFns",
  "allSecurityDefinerFns",
  "securityDefinerAnonFns",
]);

// `sql.end` is teardown, not a statement — exempt. A bare `await sql.begin` or
// `return sql.begin` is NOT exempt: the retryable form puts `sql.begin` on a
// line of its own inside `withTransientRetry(() => …)` (or shares a line that
// then carries the `withTransientRetry` token), so a line matching
// `<await|return> sql.begin` is by construction the unwrapped shape.
const UNWRAPPED_SQL_OK = /\b(?:await|return)\s+sql\.end\b/;
const BARE_SQL_STMT = /\b(?:await|return)\s+sql\b/;
const BARE_SQL_ARG = /\b(\w+)\(sql[),]/;

type Line = { file: string; line: string; n: number };

function stripComments(src: string): string {
  return src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'`])\/\/.*$/gm, "$1");
}

function scannedLines(): Line[] {
  const out: Line[] = [];
  for (const f of readdirSync(DIR)) {
    if (!f.endsWith(".ts") || EXEMPT_FILES.has(f)) continue;
    const src = stripComments(readFileSync(path.join(DIR, f), "utf8"));
    src.split("\n").forEach((line, i) => out.push({ file: f, line, n: i + 1 }));
  }
  return out;
}

function censusAOffenders(ls: Line[]): Line[] {
  return ls.filter(
    ({ line }) =>
      BARE_SQL_STMT.test(line) && !UNWRAPPED_SQL_OK.test(line) && !line.includes("withTransientRetry"),
  );
}

function censusBOffenders(ls: Line[]): Line[] {
  return ls.filter(({ line }) => {
    if (line.includes("withTransientRetry")) return false;
    // EVERY callee on the line is checked — an allowlisted first call must not
    // hide a non-allowlisted second (`foo(allowlisted(sql), bar(sql))`).
    return [...line.matchAll(new RegExp(BARE_SQL_ARG, "g"))].some(
      (m) => !ALLOWED_BARE_SQL_CALLS.has(m[1]),
    );
  });
}

describe("rls-fuzz bare-sql census (#9779)", () => {
  const ls = scannedLines();
  const fmt = (o: Line[]) => o.map((l) => `${l.file}:${l.n}: ${l.line.trim()}`);

  test("guard sanity: scanned population is non-trivial", () => {
    // Totality pin: an empty scan set would satisfy both assertions vacuously.
    expect(ls.length).toBeGreaterThan(200);
    expect(new Set(ls.map((l) => l.file)).size).toBeGreaterThanOrEqual(10);
  });

  test("no bare `await sql`/`return sql` statement outside withTransientRetry", () => {
    expect(
      fmt(censusAOffenders(ls)),
      "bare sql-handle statements — wrap in withTransientRetry or justify an allowlist entry",
    ).toEqual([]);
  });

  test("census A self-test: seeded offenders are detected", () => {
    const seeded: Line[] = [
      { file: "x.ts", line: "    await sql`select 1`;", n: 1 },
      { file: "x.ts", line: "    await sql.begin(async (t) => {});", n: 2 },
      { file: "x.ts", line: "    return sql.begin((t) => seed(t));", n: 3 },
      { file: "x.ts", line: "    await sql.end({ timeout: 5 });", n: 4 }, // exempt teardown
      { file: "x.ts", line: "    await withTransientRetry(() => sql`select 1`);", n: 5 }, // wrapped
    ];
    expect(censusAOffenders(seeded).map((l) => l.n)).toEqual([1, 2, 3]);
  });

  test("no bare `sql` handle passed to retry-relevant helpers outside withTransientRetry", () => {
    expect(
      fmt(censusBOffenders(ls)),
      "bare `sql` helper call sites — wrap in withTransientRetry or justify an allowlist entry",
    ).toEqual([]);
  });

  test("census B self-test: seeded offenders are detected", () => {
    const seeded: Line[] = [
      { file: "x.ts", line: "    await someHelper(sql, ctx);", n: 1 },
      { file: "x.ts", line: "    return seedTwoTenant(sql);", n: 2 }, // allowlisted
      { file: "x.ts", line: "    await withTransientRetry(() => countRows(sql, t, loc));", n: 3 }, // wrapped
    ];
    expect(censusBOffenders(seeded).map((l) => l.n)).toEqual([1]);
  });
});
