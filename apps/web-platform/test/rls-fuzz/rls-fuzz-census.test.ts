import { describe, test, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

// Standing guard for the plan's AC6 census (#9779): every bare `sql`-handle
// statement in this directory must ride withTransientRetry — parallel vitest
// workers share ONE disposable Postgres, so an unwrapped `await sql` is an
// unretried deadlock victim that only ever surfaces as an intermittent CI
// flake (every spec here is describe.skipIf(!RLS_FUZZ_LOCAL), so nothing local
// reddens it). This file pins the two census greps so a new bare `sql` call
// fails deterministically instead. Anchored on call forms a comment cannot
// produce once comments are stripped.

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
  "assertTwoTenant",
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
// `await sql.savepoint` is NOT exempt: the retryable form puts `sql.begin` on a
// line of its own inside `withTransientRetry(() => …)` (or shares a line that
// then carries the `withTransientRetry` token), so a line matching `await
// sql.begin` is by construction the unwrapped shape.
const UNWRAPPED_SQL_OK = /await sql\.end\b/;

function stripComments(src: string): string {
  return src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'`])\/\/.*$/gm, "$1");
}

function lines(): Array<{ file: string; line: string; n: number }> {
  const out: Array<{ file: string; line: string; n: number }> = [];
  for (const f of readdirSync(DIR)) {
    if (!f.endsWith(".ts") || EXEMPT_FILES.has(f)) continue;
    const src = stripComments(readFileSync(path.join(DIR, f), "utf8"));
    src.split("\n").forEach((line, i) => out.push({ file: f, line, n: i + 1 }));
  }
  return out;
}

describe("rls-fuzz bare-sql census (#9779)", () => {
  test("no bare `await sql` statement outside withTransientRetry", () => {
    const offenders = lines().filter(
      ({ line }) =>
        /await sql\b/.test(line) &&
        !UNWRAPPED_SQL_OK.test(line) &&
        !line.includes("withTransientRetry"),
    );
    expect(
      offenders.map((o) => `${o.file}:${o.n}: ${o.line.trim()}`),
      "bare `await sql` sites — wrap in withTransientRetry or justify an allowlist entry",
    ).toEqual([]);
  });

  test("no bare `sql` handle passed to retry-relevant helpers outside withTransientRetry", () => {
    const offenders = lines().filter(({ line }) => {
      const m = line.match(/\b(\w+)\(sql[),]/);
      return m != null && !ALLOWED_BARE_SQL_CALLS.has(m[1]) && !line.includes("withTransientRetry");
    });
    expect(
      offenders.map((o) => `${o.file}:${o.n}: ${o.line.trim()}`),
      "bare `sql` helper call sites — wrap in withTransientRetry or justify an allowlist entry",
    ).toEqual([]);
  });
});
