import { describe, it, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import path from "node:path";

// Migration 044 trigger-function-specific lint. SECURITY DEFINER RPCs in
// this migration (`accept_terms`, `anonymise_tc_acceptances`) are
// covered by the generalised `migration-rpc-grants.test.ts`. This file
// adds the assertions unique to the WORM trigger function:
//
//   1. `tc_acceptances_no_mutate()` REVOKEs from PUBLIC + anon +
//      authenticated + service_role (four-role pattern). The trigger
//      fn has no legitimate direct caller — the WORM property holds
//      only if every role is denied EXECUTE.
//   2. The trigger fn is INVOKER (NOT SECURITY DEFINER). DEFINER would
//      evaluate `current_user` to the function owner (`postgres`),
//      making the `current_user = 'service_role'` Art. 17 bypass gate
//      always false and breaking the legitimate anonymise flow. See
//      043's reasoning at lines 127-134.
//   3. BEFORE UPDATE + BEFORE DELETE triggers wire the function to the
//      `tc_acceptances` table.
//
// Migration 044 is part of feat-oauth-tc-consent-3205 (PR #3853).

const MIGRATIONS_DIR = path.join(__dirname, "../supabase/migrations");
const MIGRATION_FILE = "044_add_tc_acceptances_ledger.sql";

describe("migration 044 (tc_acceptances) — WORM trigger lint", () => {
  const filePath = path.join(MIGRATIONS_DIR, MIGRATION_FILE);

  it("migration file exists", () => {
    expect(existsSync(filePath), `${MIGRATION_FILE} not found`).toBe(true);
  });

  if (!existsSync(filePath)) return;

  const sql = readFileSync(filePath, "utf8");

  it("declares the WORM trigger function tc_acceptances_no_mutate", () => {
    expect(sql).toMatch(
      /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.tc_acceptances_no_mutate\s*\(\s*\)/i,
    );
  });

  it("trigger function is INVOKER (no SECURITY DEFINER on the trigger fn block)", () => {
    // Extract just the trigger fn's declaration-through-end-of-body so
    // we don't accidentally match SECURITY DEFINER on a sibling RPC.
    const match = sql.match(
      /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.tc_acceptances_no_mutate\s*\(\s*\)[\s\S]*?\$\$[\s\S]*?\$\$\s*;/i,
    );
    expect(match, "trigger fn block not found").not.toBeNull();
    expect(match![0]).not.toMatch(/\bSECURITY\s+DEFINER\b/i);
  });

  it("trigger function REVOKEs ALL from PUBLIC + anon + authenticated + service_role", () => {
    // Collect every REVOKE targeting tc_acceptances_no_mutate; union the role list.
    const revokeRe =
      /REVOKE\s+(?:ALL(?:\s+PRIVILEGES)?|EXECUTE)\s+ON\s+FUNCTION\s+public\.tc_acceptances_no_mutate\s*\(\s*\)\s+FROM\s+([^;]+);/gi;
    const roles = new Set<string>();
    for (const m of sql.matchAll(revokeRe)) {
      for (const tok of m[1]!.split(",")) {
        const role = tok.trim().toLowerCase();
        if (role) roles.add(role);
      }
    }
    for (const required of ["public", "anon", "authenticated", "service_role"]) {
      expect(
        roles,
        `trigger fn must REVOKE from ${required}; got [${[...roles].join(", ")}]`,
      ).toContain(required);
    }
  });

  it("wires BEFORE UPDATE and BEFORE DELETE triggers on public.tc_acceptances", () => {
    expect(sql).toMatch(
      /CREATE\s+TRIGGER\s+\w+\s+BEFORE\s+UPDATE\s+ON\s+public\.tc_acceptances[\s\S]*?EXECUTE\s+FUNCTION\s+public\.tc_acceptances_no_mutate\s*\(\s*\)/i,
    );
    expect(sql).toMatch(
      /CREATE\s+TRIGGER\s+\w+\s+BEFORE\s+DELETE\s+ON\s+public\.tc_acceptances[\s\S]*?EXECUTE\s+FUNCTION\s+public\.tc_acceptances_no_mutate\s*\(\s*\)/i,
    );
  });

  it("declares UNIQUE(user_id, version) for accept_terms idempotency", () => {
    // RPC-side idempotency (`ON CONFLICT (user_id, version) DO NOTHING`)
    // requires either a unique constraint or a unique index on
    // (user_id, version). Accept either form.
    const tableConstraint =
      /CREATE\s+TABLE[\s\S]*?public\.tc_acceptances[\s\S]*?UNIQUE\s*\(\s*user_id\s*,\s*version\s*\)/i;
    const uniqueIndex =
      /CREATE\s+UNIQUE\s+INDEX[^;]*ON\s+public\.tc_acceptances\s*\(\s*user_id\s*,\s*version\s*\)/i;
    expect(
      tableConstraint.test(sql) || uniqueIndex.test(sql),
      "expected UNIQUE(user_id, version) constraint or unique index",
    ).toBe(true);
  });
});
