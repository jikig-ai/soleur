/**
 * Drift guard — tenant-isolation teardown ⊇ account-delete anonymise cascade.
 *
 * Pure source/migration grep (no dev Supabase) — runs in the default ci.yml
 * test-webplat shard, NOT behind TENANT_INTEGRATION_TEST. It makes the
 * "8-vs-23 anonymise RPC" reopening (#5582) a RED test:
 *
 *   - `test/helpers/tenant-isolation-teardown.ts` runs an FK-reverse
 *     anonymise sequence before `auth.admin.deleteUser`.
 *   - `server/account-delete.ts` is the production cascade it mirrors.
 *
 * If a future PR adds a new `anonymise_*` RPC to account-delete (behind a new
 * RESTRICT FK to `users`) without adding it to the teardown, the synthetic
 * tenant-isolation users will FK-block on `deleteUser` and the dev-Supabase
 * suites go red with an opaque GoTrue 500. This guard catches that drift here,
 * cheaply, in the always-on suite.
 *
 * Assertions:
 *   1. PARITY — every `anonymise_*` RPC account-delete invokes is present in
 *      the teardown sequence, with the SAME parameter name (a wrong arg name,
 *      e.g. `p_user_id` vs `p_founder_id`, yields PGRST202 at runtime, which
 *      `withGoTrueRetry` would mask as a transient deleteUser 500).
 *   2. FATALITY (AC8) — every RPC the teardown marks `set-null` (non-fatal,
 *      warn-and-continue) is GENUINELY non-RESTRICT per the FK-defining
 *      migration. Derived from `supabase/migrations/` (the `ON DELETE` clause
 *      of the table's FK to `users`), NOT from a hand-labeled list — so a
 *      mislabel cannot silently downgrade a real 500-cause to a warning.
 *   3. GRACEFUL SCOPE (AC7) — the missing-function graceful-degrade exception
 *      is scoped to exactly `anonymise_workspace_invitations`.
 */

import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";

const WEB_PLATFORM_ROOT = join(__dirname, "..", "..");
const ACCOUNT_DELETE = join(WEB_PLATFORM_ROOT, "server", "account-delete.ts");
const TEARDOWN = join(
  WEB_PLATFORM_ROOT,
  "test",
  "helpers",
  "tenant-isolation-teardown.ts",
);
const MIGRATIONS_DIR = join(WEB_PLATFORM_ROOT, "supabase", "migrations");

/**
 * Every `anonymise_*` RPC account-delete invokes, mapped to the parameter
 * name it passes. Matches the multiline `.rpc("anonymise_x", { p_y: ... })`
 * call shape; the first `p_<name>` after each rpc literal is its arg.
 */
function extractAccountDeleteAnonymise(src: string): Map<string, string> {
  const out = new Map<string, string>();
  // Anchor to the actual `.rpc("anonymise_x"` CALL shape — NOT any quoted
  // `anonymise_*` literal (error/log-message strings also contain RPC names
  // and would otherwise inflate the production set into a false parity demand).
  const rpcRe = /\.rpc\(\s*"(anonymise_[a-z_]+)"/g;
  let m: RegExpExecArray | null;
  while ((m = rpcRe.exec(src)) !== null) {
    const rpc = m[1]!;
    // The argument object follows within a short window of the rpc literal.
    const window = src.slice(m.index, m.index + 140);
    const argMatch = window.match(/\b(p_[a-z_]+)\s*:/);
    if (argMatch && !out.has(rpc)) out.set(rpc, argMatch[1]!);
  }
  return out;
}

type FatalityClass = "restrict" | "set-null" | "graceful";

/** Parse the teardown's ANONYMISE_SEQUENCE literal entries. */
function extractTeardownSequence(
  src: string,
): Array<{ rpc: string; arg: string; klass: FatalityClass }> {
  const entryRe =
    /\[\s*"(anonymise_[a-z_]+)"\s*,\s*"(p_[a-z_]+)"\s*,\s*"(restrict|set-null|graceful)"\s*\]/g;
  const out: Array<{ rpc: string; arg: string; klass: FatalityClass }> = [];
  let m: RegExpExecArray | null;
  while ((m = entryRe.exec(src)) !== null) {
    out.push({ rpc: m[1]!, arg: m[2]!, klass: m[3] as FatalityClass });
  }
  return out;
}

type OnDelete = "restrict" | "set null" | "cascade";

/**
 * Build a `table -> ON DELETE class of its FK to users` map across all
 * migrations (latest migration number wins). Matches FKs to BOTH
 * `public.users(id)` and `auth.users(id)` (some tables reference auth.users
 * directly, e.g. workspace_activity). Scans CREATE TABLE blocks and
 * ALTER TABLE … ADD CONSTRAINT … FOREIGN KEY redefinitions (mig 065 flips
 * organizations.owner_user_id + audit_byok_use.founder_id to SET NULL).
 */
function buildFkClassMap(): Map<string, OnDelete> {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql") && !f.endsWith(".down.sql"))
    .sort(); // numeric prefix → lexical sort is migration order for 3-digit ids
  const map = new Map<string, OnDelete>();

  for (const file of files) {
    const sql = readFileSync(join(MIGRATIONS_DIR, file), "utf8");

    // CREATE TABLE [IF NOT EXISTS] (public.)?<table> ( … );
    const createRe =
      /create table(?:\s+if not exists)?\s+(?:public\.)?([a-z_]+)\s*\(([\s\S]*?)\n\)/gi;
    let c: RegExpExecArray | null;
    while ((c = createRe.exec(sql)) !== null) {
      const table = c[1]!;
      const body = c[2]!;
      const fk = body.match(
        /references\s+(?:public|auth)\.users\s*\(id\)\s*on delete (restrict|set null|cascade)/i,
      );
      if (fk) map.set(table, fk[1]!.toLowerCase() as OnDelete);
    }

    // ALTER TABLE (public.)?<table> … FOREIGN KEY (…) REFERENCES …users(id) ON DELETE <X>
    const alterRe =
      /alter table\s+(?:public\.)?([a-z_]+)[\s\S]*?references\s+(?:public|auth)\.users\s*\(id\)\s*on delete (restrict|set null|cascade)/gi;
    let a: RegExpExecArray | null;
    while ((a = alterRe.exec(sql)) !== null) {
      map.set(a[1]!, a[2]!.toLowerCase() as OnDelete);
    }
  }
  return map;
}

/**
 * Extract the BODY of `CREATE [OR REPLACE] FUNCTION public.<rpc>` from its
 * latest defining migration — the dollar-quoted block (`AS $tag$ … $tag$`),
 * so table extraction is scoped to the function, not the whole migration file
 * (which may define unrelated tables/RPCs). Returns the latest definition's
 * body (a migration can `CREATE OR REPLACE` it more than once).
 */
function findFunctionBody(rpc: string): string | null {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql") && !f.endsWith(".down.sql"))
    .sort()
    .reverse(); // latest definition wins
  // Anchor to the DEFINITION (`CREATE [OR REPLACE] FUNCTION`) — a bare
  // `function public.<rpc>` also matches the REVOKE/GRANT/COMMENT ON FUNCTION
  // lines that follow it in the same migration; with last-match-wins those
  // later matches slice forward into the NEXT function's `$$…$$` body and
  // silently mis-resolve this RPC's tables (the inert-FATALITY bug #5582
  // review caught: anonymise_workspace_activity resolving to conversations).
  const sigRe = new RegExp(
    `create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.${rpc}\\b`,
    "gi",
  );
  for (const file of files) {
    const sql = readFileSync(join(MIGRATIONS_DIR, file), "utf8");
    let m: RegExpExecArray | null;
    let lastBody: string | null = null;
    while ((m = sigRe.exec(sql)) !== null) {
      // From the signature, find the opening dollar-quote tag and its match.
      const after = sql.slice(m.index);
      const tagMatch = after.match(/as\s+(\$[a-z_]*\$)/i);
      if (!tagMatch) continue;
      const tag = tagMatch[1]!;
      const openIdx = after.indexOf(tag, tagMatch.index!);
      const closeIdx = after.indexOf(tag, openIdx + tag.length);
      if (openIdx === -1 || closeIdx === -1) continue;
      lastBody = after.slice(openIdx + tag.length, closeIdx);
    }
    if (lastBody) return lastBody;
  }
  return null;
}

/**
 * Resolve the user-FK tables an anonymise RPC mutates, by reading the tables
 * it UPDATEs/DELETEs in its function body and intersecting with the FK-class
 * map (which drops keyword noise like `ON`/`SET`). Returns the set of ON
 * DELETE classes across those tables.
 */
function resolveRpcOnDeleteClasses(
  rpc: string,
  fkMap: Map<string, OnDelete>,
): Set<OnDelete> {
  const body = findFunctionBody(rpc);
  const classes = new Set<OnDelete>();
  if (!body) return classes;
  const targetRe = /(?:update|delete from)\s+(?:public\.)?([a-z_]+)/gi;
  let m: RegExpExecArray | null;
  while ((m = targetRe.exec(body)) !== null) {
    const cls = fkMap.get(m[1]!);
    if (cls) classes.add(cls);
  }
  return classes;
}

describe("teardown anonymise parity (drift guard)", () => {
  const accountDeleteSrc = readFileSync(ACCOUNT_DELETE, "utf8");
  const teardownSrc = readFileSync(TEARDOWN, "utf8");

  const production = extractAccountDeleteAnonymise(accountDeleteSrc);
  const sequence = extractTeardownSequence(teardownSrc);
  const teardownByRpc = new Map(sequence.map((e) => [e.rpc, e]));

  test("sanity: both source files parse non-empty sets", () => {
    expect(production.size).toBeGreaterThan(15);
    expect(sequence.length).toBeGreaterThan(15);
  });

  test("AC6/AC8 PARITY — teardown ⊇ account-delete anonymise set, with matching arg names", () => {
    const missing: string[] = [];
    const argMismatch: string[] = [];
    for (const [rpc, arg] of production) {
      const entry = teardownByRpc.get(rpc);
      if (!entry) {
        missing.push(rpc);
      } else if (entry.arg !== arg) {
        argMismatch.push(`${rpc}: teardown=${entry.arg} production=${arg}`);
      }
    }
    expect(
      missing,
      `teardown is missing anonymise RPC(s) account-delete calls — synthetic ` +
        `users will FK-block on deleteUser (the #5582 500 storm):\n  ${missing.join("\n  ")}`,
    ).toEqual([]);
    expect(
      argMismatch,
      `teardown arg name(s) diverge from production (PGRST202 → masked 500):\n  ${argMismatch.join("\n  ")}`,
    ).toEqual([]);
  });

  test("AC8 FATALITY — every `set-null`-labeled RPC is genuinely non-RESTRICT per its FK migration", () => {
    const fkMap = buildFkClassMap();
    const mislabeled: string[] = [];
    const unresolvable: string[] = [];
    for (const entry of sequence) {
      if (entry.klass !== "set-null") continue;
      const classes = resolveRpcOnDeleteClasses(entry.rpc, fkMap);
      if (classes.size === 0) {
        // FAIL LOUD, do not skip: an unresolvable `set-null` RPC means the
        // FATALITY check is INERT for it (the exact inertness the #5582 review
        // caught when findFunctionBody mis-resolved the body). The label claims
        // "safe to warn-and-continue" but nothing verifies it — treat as a
        // verification failure so the resolver/label is fixed, not trusted.
        unresolvable.push(entry.rpc);
        continue;
      }
      // Resolved ≥1 FK table — if ANY is RESTRICT the `set-null` label is
      // dangerous (it would warn-and-continue on a real 500 cause).
      if (classes.has("restrict")) {
        mislabeled.push(
          `${entry.rpc}: labeled set-null but FK migration says RESTRICT (${[...classes].join(",")})`,
        );
      }
    }
    expect(
      unresolvable,
      `set-null RPC(s) whose FK class could not be resolved from migrations — ` +
        `FATALITY verification is inert for them; fix the resolver or the label:\n  ${unresolvable.join("\n  ")}`,
    ).toEqual([]);
    expect(
      mislabeled,
      `set-null mislabel would re-bury a deterministic deleteUser 500:\n  ${mislabeled.join("\n  ")}`,
    ).toEqual([]);
  });

  test("AC7 GRACEFUL SCOPE — missing-function graceful-degrade is scoped to anonymise_workspace_invitations only", () => {
    const graceful = sequence.filter((e) => e.klass === "graceful").map((e) => e.rpc);
    expect(graceful).toEqual(["anonymise_workspace_invitations"]);
  });
});
