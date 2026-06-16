import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 108_repo_clone_self_heal_rpc.sql
// (feat-one-shot-concierge-reconnect-self-heal-checkout — FIX 1a, AC1c).
//
// Offline lint — runs without a live database. The live-DB predicate proof
// (error→cloning AND stale-cloning→cloning but NOT fresh-cloning; membership
// gate) runs at apply time via the migration runner + the opt-in
// TENANT_INTEGRATION_TEST=1 suite. This source-shape test guards the
// load-bearing security + predicate invariants that a regression could silently
// drop:
//   - TWO SECURITY DEFINER fns: claim_repo_clone_lock + set_repo_status
//   - search_path pinned (public-first, pg_temp) per
//     cq-pg-security-definer-search-path-pin-pg-temp (matches the repo-wide
//     migration-rpc-grants.test.ts lint, which requires `public`).
//   - 4-role REVOKE (PUBLIC, anon, authenticated, service_role) THEN GRANT
//     EXECUTE TO authenticated (mirror migration 079/083).
//   - membership check (is_workspace_member) in BOTH fns.
//   - the dead-winner escape predicate:
//       repo_status='error' OR (repo_status='cloning' AND
//       repo_last_synced_at < now() - interval '5 minutes')
//     — never a `.neq('cloning')` terminal trap.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/108_repo_clone_self_heal_rpc.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/108_repo_clone_self_heal_rpc.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
// Strip line-comments so prose `--` lines don't false-match the patterns.
const executable = sql.replace(/--[^\n]*/g, "");

function extractFunctionBodies(src: string): Map<string, string> {
  const re =
    /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.(\w+)\s*\(([^)]*)\)[\s\S]*?\$\$([\s\S]*?)\$\$\s*;/gi;
  const out = new Map<string, string>();
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    out.set(m[1]!, m[3]!);
  }
  return out;
}

const fnBodies = extractFunctionBodies(executable);

describe("migration 108_repo_clone_self_heal_rpc", () => {
  it("wraps the migration in a transaction (BEGIN/COMMIT)", () => {
    expect(executable).toMatch(/\bBEGIN\b/);
    expect(executable).toMatch(/\bCOMMIT\b/);
  });

  it("defines exactly the two expected SECURITY DEFINER functions", () => {
    expect([...fnBodies.keys()].sort()).toEqual(
      ["claim_repo_clone_lock", "set_repo_status"].sort(),
    );
  });

  for (const fn of ["claim_repo_clone_lock", "set_repo_status"]) {
    describe(`fn ${fn}`, () => {
      it("is SECURITY DEFINER with a public-first, pg_temp-pinned search_path", () => {
        const decl = new RegExp(
          `CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${fn}[\\s\\S]*?\\bSECURITY\\s+DEFINER\\b[\\s\\S]*?AS\\s+\\$\\$`,
          "i",
        );
        expect(executable).toMatch(decl);
        const search = new RegExp(
          `CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${fn}[\\s\\S]*?SET\\s+search_path\\s*=\\s*public\\s*,\\s*pg_temp[\\s\\S]*?AS\\s+\\$\\$`,
          "i",
        );
        expect(executable).toMatch(search);
      });

      it("REVOKEs from PUBLIC, anon, authenticated, service_role then GRANTs EXECUTE to authenticated", () => {
        const revoke = new RegExp(
          `REVOKE\\s+(?:ALL|EXECUTE)[\\s\\S]*?ON\\s+FUNCTION\\s+public\\.${fn}\\s*\\([^)]*\\)\\s+FROM\\s+([^;]+);`,
          "i",
        );
        const m = executable.match(revoke);
        expect(m, `expected a REVOKE for ${fn}`).not.toBeNull();
        const roles = m![1]!.toLowerCase();
        for (const role of ["public", "anon", "authenticated", "service_role"]) {
          expect(roles).toContain(role);
        }
        const grant = new RegExp(
          `GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${fn}\\s*\\([^)]*\\)\\s+TO\\s+authenticated`,
          "i",
        );
        expect(executable).toMatch(grant);
      });

      it("performs an is_workspace_member membership check", () => {
        const body = fnBodies.get(fn)!;
        expect(body).toMatch(/is_workspace_member\s*\(/i);
      });
    });
  }

  describe("claim_repo_clone_lock predicate", () => {
    const body = () => fnBodies.get("claim_repo_clone_lock")!;

    it("flips repo_status to 'cloning' and stamps repo_last_synced_at", () => {
      expect(body()).toMatch(
        /UPDATE\s+public\.workspaces[\s\S]*?SET[\s\S]*?repo_status\s*=\s*'cloning'/i,
      );
      expect(body()).toMatch(/repo_last_synced_at\s*=\s*now\(\)/i);
    });

    it("acquires on error OR stale-cloning (>5 min OR NULL clock), never a `.neq('cloning')` trap", () => {
      const b = body();
      // error OR (cloning AND stale)
      expect(b).toMatch(/repo_status\s*=\s*'error'/i);
      expect(b).toMatch(
        /repo_status\s*=\s*'cloning'[\s\S]*?repo_last_synced_at\s*<\s*now\(\)\s*-\s*interval\s*'5 minutes'/i,
      );
      // NULL-clock arm: a 'cloning' row with no recorded sync time (legacy
      // pre-deploy strand, or any writer that forgot to stamp) MUST be
      // recoverable — `NULL < now()-interval` is NULL, so an explicit IS NULL
      // arm is required or the row is permanently stuck.
      expect(b).toMatch(
        /repo_status\s*=\s*'cloning'[\s\S]*?repo_last_synced_at\s+IS\s+NULL/i,
      );
      // The terminal trap must NOT appear.
      expect(b).not.toMatch(/!=\s*'cloning'|<>\s*'cloning'|neq/i);
    });

    it("returns FOUND (won/lost boolean)", () => {
      expect(body()).toMatch(/RETURN\s+FOUND/i);
    });
  });

  describe("set_repo_status dual-write", () => {
    const body = () => fnBodies.get("set_repo_status")!;

    it("writes workspaces.repo_status", () => {
      expect(body()).toMatch(
        /UPDATE\s+public\.workspaces[\s\S]*?SET[\s\S]*?repo_status\s*=/i,
      );
    });

    it("dual-writes users.repo_error (the reason the readiness gate reads)", () => {
      expect(body()).toMatch(
        /UPDATE\s+public\.users[\s\S]*?SET[\s\S]*?repo_error\s*=/i,
      );
    });
  });

  describe("down migration", () => {
    it("drops both functions", () => {
      expect(downSql).toMatch(/DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.claim_repo_clone_lock/i);
      expect(downSql).toMatch(/DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.set_repo_status/i);
    });
  });
});
