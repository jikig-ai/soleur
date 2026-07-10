import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 128_revoke_definer_rpc_residual_grants.sql (#6306).
//
// File-parse test, not a live-DB test. It pins the SQL contract that closes
// the cross-tenant disclosure / write-IDOR surface: five service-role-only
// SECURITY DEFINER functions still carried the CREATE-time default EXECUTE
// grants to `anon` + `authenticated` (migrations 029/036/037/093 ran only
// `revoke … from public`, which does NOT remove the explicit anon/authenticated
// grants). The runtime deny state is proven by the deploy-time verify sentinel
// (verify/128_*.sql, run by verify-migrations); this test guards the migration
// *content* in CI without needing a live stack.
//
// Plan: 2026-07-11-fix-revoke-definer-rpc-residual-grants-plan.md.

const MIGRATIONS_DIR = path.join(__dirname, "../../supabase/migrations");
const VERIFY_DIR = path.join(__dirname, "../../supabase/verify");

const UP_PATH = path.join(MIGRATIONS_DIR, "128_revoke_definer_rpc_residual_grants.sql");
const DOWN_PATH = path.join(MIGRATIONS_DIR, "128_revoke_definer_rpc_residual_grants.down.sql");
const VERIFY_PATH = path.join(VERIFY_DIR, "128_definer_rpc_residual_grants_revoked.sql");

// The five audited functions. `serviceRolePositive` is false only for the
// trigger function (release_slot_on_archive) — PostgREST never exposes it and
// it needs no service_role grant, so verify/128 must NOT assert one for it
// (plan Sharp Edge). `acquire_conversation_slot` MUST be the 4-arg overload
// from 093:124 — the 3-arg form was dropped at 093:42 (data-integrity P1).
const TARGETS = [
  { fn: "find_stuck_active_conversations", args: "integer", serviceRolePositive: true },
  { fn: "acquire_conversation_slot", args: "uuid, uuid, integer, uuid", serviceRolePositive: true },
  { fn: "release_conversation_slot", args: "uuid, uuid", serviceRolePositive: true },
  { fn: "touch_conversation_slot", args: "uuid, uuid", serviceRolePositive: true },
  { fn: "release_slot_on_archive", args: "", serviceRolePositive: false },
] as const;

// Escape a raw SQL signature fragment (parens, commas, dots) for use inside a
// RegExp source. Whitespace in the arg list is normalised to `\s*` so
// `(uuid, uuid)` and `(uuid,uuid)` both match.
function sigPattern(fn: string, args: string): string {
  const escFn = fn.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const escArgs = args
    .replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    .replace(/\s*,\s*/g, "\\s*,\\s*")
    .replace(/\s+/g, "\\s*");
  return `public\\.${escFn}\\s*\\(\\s*${escArgs}\\s*\\)`;
}

describe("migration 128_revoke_definer_rpc_residual_grants", () => {
  const up = readFileSync(UP_PATH, "utf8");
  // Strip line-comments before pattern checks so header prose can mention the
  // same tokens without tripping the regex (mirrors 036 pattern).
  const upExec = up.replace(/--[^\n]*/g, "");

  for (const { fn, args } of TARGETS) {
    it(`AC1: revokes EXECUTE from anon, authenticated on ${fn}(${args})`, () => {
      const re = new RegExp(
        `revoke\\s+execute\\s+on\\s+function\\s+${sigPattern(fn, args)}\\s+from\\s+anon\\s*,\\s*authenticated`,
        "i",
      );
      expect(upExec).toMatch(re);
    });

    it(`AC2: revokes EXECUTE from public (defense-in-depth) on ${fn}(${args})`, () => {
      const re = new RegExp(
        `revoke\\s+execute\\s+on\\s+function\\s+${sigPattern(fn, args)}\\s+from\\s+public`,
        "i",
      );
      expect(upExec).toMatch(re);
    });
  }

  it("AC9: documents service-role-only intent for find_stuck_active_conversations via COMMENT ON FUNCTION + Ref #6306", () => {
    const re = new RegExp(
      `comment\\s+on\\s+function\\s+${sigPattern("find_stuck_active_conversations", "integer")}\\s+is`,
      "i",
    );
    expect(upExec).toMatch(re);
    // The #6306 reference lives in the (unstripped) source so the intent is
    // traceable from the migration itself.
    expect(up).toMatch(/#6306/);
  });

  it("pins the 4-arg acquire_conversation_slot overload, never the dropped 3-arg form", () => {
    // The 3-arg (uuid, uuid, integer) signature was dropped at 093:42; revoking
    // against it would raise `function does not exist` under ON_ERROR_STOP=1.
    expect(upExec).not.toMatch(
      /revoke\s+execute\s+on\s+function\s+public\.acquire_conversation_slot\s*\(\s*uuid\s*,\s*uuid\s*,\s*integer\s*\)/i,
    );
  });
});

describe("migration 128 down", () => {
  const down = readFileSync(DOWN_PATH, "utf8");
  const downExec = down.replace(/--[^\n]*/g, "");

  it("AC3: restores the pre-fix anon/authenticated grants (rollback machinery)", () => {
    for (const { fn, args } of TARGETS) {
      const re = new RegExp(
        `grant\\s+execute\\s+on\\s+function\\s+${sigPattern(fn, args)}\\s+to\\s+anon\\s*,\\s*authenticated`,
        "i",
      );
      expect(downExec, `down must re-grant ${fn}(${args})`).toMatch(re);
    }
  });

  it("AC3: carries a 093.down-style prod caveat that it knowingly re-opens the #6306 IDOR", () => {
    expect(down).toMatch(/#6306/);
    expect(down).toMatch(/do NOT run (this )?in production|rollback[- ]machinery only/i);
  });
});

describe("verify 128_definer_rpc_residual_grants_revoked", () => {
  const verify = readFileSync(VERIFY_PATH, "utf8");
  const verifyExec = verify.replace(/--[^\n]*/g, "");

  it("AC5: conforms to the (check_name, bad) two-column contract", () => {
    // run-verify.sh parses tab-separated (check_name TEXT, bad INT) rows.
    expect(verifyExec).toMatch(/as\s+check_name/i);
    // Every check coerces `bad` to ::int (069 convention).
    expect(verifyExec).toMatch(/::int/i);
  });

  for (const { fn, args, serviceRolePositive } of TARGETS) {
    for (const role of ["anon", "authenticated", "public"] as const) {
      it(`AC4: ${role} deny check for ${fn}(${args})`, () => {
        const re = new RegExp(
          `has_function_privilege\\(\\s*'${role}'\\s*,\\s*'${sigPattern(fn, args)}'\\s*,\\s*'EXECUTE'\\s*\\)`,
          "i",
        );
        expect(verifyExec).toMatch(re);
      });
    }

    if (serviceRolePositive) {
      it(`AC4: service_role grant-present check for ${fn}(${args})`, () => {
        const re = new RegExp(
          `has_function_privilege\\(\\s*'service_role'\\s*,\\s*'${sigPattern(fn, args)}'\\s*,\\s*'EXECUTE'\\s*\\)`,
          "i",
        );
        expect(verifyExec).toMatch(re);
      });
    } else {
      it(`does NOT assert a service_role grant on the trigger fn ${fn}()`, () => {
        const re = new RegExp(
          `has_function_privilege\\(\\s*'service_role'\\s*,\\s*'${sigPattern(fn, args)}'`,
          "i",
        );
        expect(verifyExec).not.toMatch(re);
      });
    }
  }
});
