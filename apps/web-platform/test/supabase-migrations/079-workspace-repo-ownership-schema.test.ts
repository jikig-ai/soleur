import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 079_workspace_repo_ownership_schema.sql.
//
// File-parse contract test (mirrors the 047 precedent), pinning the SQL
// invariants required by ADR-044 (relocate repo state user→workspace;
// amends ADR-038), plan §Phase 079:
//   1. Five repo columns added to public.workspaces, mirroring the 011
//      shapes (repo_url / repo_provider / github_installation_id /
//      repo_status CHECK / repo_last_synced_at).
//   2. Non-unique indexes (github_installation_id, repo_url) + repo_url.
//      NO global UNIQUE on repo_url (two users may connect the same
//      fork to their own workspaces; webhook determinism = fan-out).
//   3. Column-level credential protection: the github_installation_id
//      column is removed from `authenticated`'s SELECT grant. Supabase
//      grants TABLE-level SELECT to authenticated by default and
//      Postgres column-level REVOKE is a no-op while a table grant
//      exists — so the correct shape is REVOKE SELECT ON workspaces
//      FROM authenticated + GRANT SELECT (non-credential cols). (The
//      plan's literal `REVOKE SELECT (col)` form is insufficient; see
//      the migration header.)
//   4. resolve_workspace_installation_id(p_workspace_id) definer RPC:
//      is_workspace_member check (deny → RETURN NULL), reads the
//      credential; 4-role REVOKE + GRANT authenticated; search_path pin.
//   5. current_workspace_id added to user_session_state (FK ON DELETE
//      SET NULL) + idempotent solo-workspace backfill.
//   6. runtime_jwt_mint_hook extended to inject current_workspace_id
//      while preserving the org-injection + OTP precheck blocks; hook
//      grant stays supabase_auth_admin (NOT authenticated).
//   7. set_current_workspace_id(p_workspace_id) RPC: 28000 + 22004 +
//      42501 guards, FK-race guard (raise if org_id NULL), sets BOTH
//      claims, 4-role REVOKE + GRANT authenticated.
//
// Behavioral integration tests live in the gated describe.skip block at
// the bottom; they activate when TENANT_INTEGRATION_TEST=1 and a live
// Doppler DATABASE_URL_POOLER is available (applied during /work Phase 2
// against a dedicated dev Supabase project per
// hr-dev-prd-distinct-supabase-projects — never the shared dev pre-merge).
//
// Plan: knowledge-base/project/plans/2026-05-28-feat-workspace-repo-ownership-plan.md §Phase 079
// ADR: knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md

const MIGRATION_PATH = path.resolve(
  __dirname,
  "../../supabase/migrations/079_workspace_repo_ownership_schema.sql",
);
const DOWN_PATH = path.resolve(
  __dirname,
  "../../supabase/migrations/079_workspace_repo_ownership_schema.down.sql",
);

describe("migration 079_workspace_repo_ownership_schema", () => {
  // readFileSync intentionally not wrapped: until the migration exists
  // this entire describe throws at module load (RED).
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const executable = sql.replace(/--[^\n]*/g, "");

  describe("lawful-basis header (GDPR-gate Art-6)", () => {
    it("carries a -- LAWFUL_BASIS: annotation", () => {
      expect(sql).toMatch(/--\s*LAWFUL_BASIS:/i);
      expect(sql).toMatch(/6\(1\)\(b\)/);
    });
  });

  describe("repo columns on workspaces (mirror 011)", () => {
    const alterBlock =
      executable.match(
        /ALTER\s+TABLE\s+public\.workspaces[\s\S]*?;/i,
      )?.[0] || "";

    it("adds all five repo columns", () => {
      expect(alterBlock).toMatch(/ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+repo_url\s+text/i);
      expect(alterBlock).toMatch(/ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+repo_provider\s+text\s+DEFAULT\s+'github'/i);
      expect(alterBlock).toMatch(/ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+github_installation_id\s+bigint/i);
      expect(alterBlock).toMatch(/ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+repo_status\s+text\s+DEFAULT\s+'not_connected'/i);
      expect(alterBlock).toMatch(/ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+repo_last_synced_at\s+timestamptz/i);
    });

    it("constrains repo_status to the 011 enum set", () => {
      expect(alterBlock).toMatch(
        /CHECK\s*\(\s*repo_status\s+IN\s*\(\s*'not_connected'\s*,\s*'cloning'\s*,\s*'ready'\s*,\s*'error'\s*\)\s*\)/i,
      );
    });
  });

  describe("indexes — non-unique, NO unique on repo_url", () => {
    it("creates a non-unique (github_installation_id, repo_url) index", () => {
      expect(executable).toMatch(
        /CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+\w+\s+ON\s+public\.workspaces\s*\(\s*github_installation_id\s*,\s*repo_url\s*\)/i,
      );
    });

    it("creates a non-unique repo_url index", () => {
      expect(executable).toMatch(
        /CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+\w+\s+ON\s+public\.workspaces\s*\(\s*repo_url\s*\)/i,
      );
    });

    it("does NOT create any UNIQUE index/constraint on workspaces.repo_url", () => {
      // Hard guard: a global UNIQUE on repo_url breaks two-users-same-fork.
      expect(executable).not.toMatch(/CREATE\s+UNIQUE\s+INDEX[\s\S]*?ON\s+public\.workspaces/i);
      expect(executable).not.toMatch(/ADD\s+CONSTRAINT[\s\S]*?UNIQUE\s*\([^)]*repo_url/i);
    });
  });

  describe("column-level credential protection (AC2)", () => {
    it("revokes table-level SELECT on workspaces from authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+SELECT\s+ON\s+public\.workspaces\s+FROM\s+authenticated/i,
      );
    });

    it("re-grants SELECT on non-credential columns (excluding github_installation_id) to authenticated", () => {
      const grant =
        executable.match(
          /GRANT\s+SELECT\s*\(([^)]*)\)\s+ON\s+public\.workspaces\s+TO\s+authenticated/i,
        )?.[1] || "";
      expect(grant).not.toBe("");
      // Members still see repo presence + status.
      expect(grant).toMatch(/\brepo_url\b/);
      expect(grant).toMatch(/\brepo_status\b/);
      // The credential column must NOT be in the re-grant list.
      expect(grant).not.toMatch(/github_installation_id/);
    });
  });

  describe("resolve_workspace_installation_id RPC", () => {
    const fnBlock =
      executable.match(
        /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.resolve_workspace_installation_id[\s\S]*?\$\$;/i,
      )?.[0] || "";

    it("declares (p_workspace_id uuid) RETURNS bigint, plpgsql, SECURITY DEFINER", () => {
      expect(fnBlock).toMatch(
        /FUNCTION\s+public\.resolve_workspace_installation_id\s*\(\s*p_workspace_id\s+uuid\s*\)\s+RETURNS\s+bigint/i,
      );
      expect(fnBlock).toMatch(/LANGUAGE\s+plpgsql/i);
      expect(fnBlock).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
    });

    it("membership-checks via is_workspace_member and denies by returning NULL (not raise)", () => {
      expect(fnBlock).toMatch(/is_workspace_member\s*\(\s*p_workspace_id\s*,\s*auth\.uid\(\)\s*\)/i);
      expect(fnBlock).toMatch(/RETURN\s+NULL/i);
      expect(fnBlock).not.toMatch(/RAISE\s+EXCEPTION/i);
    });

    it("4-role REVOKE + GRANT EXECUTE to authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.resolve_workspace_installation_id\s*\([^)]*\)\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.resolve_workspace_installation_id\s*\([^)]*\)\s+TO\s+authenticated/i,
      );
    });
  });

  describe("current_workspace_id on user_session_state", () => {
    it("adds current_workspace_id uuid NULL FK ON DELETE SET NULL", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.user_session_state[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+current_workspace_id\s+uuid[\s\S]*?REFERENCES\s+public\.workspaces\s*\(\s*id\s*\)\s+ON\s+DELETE\s+SET\s+NULL/i,
      );
    });

    it("backfills current_workspace_id idempotently (WHERE ... IS NULL)", () => {
      expect(executable).toMatch(/UPDATE\s+public\.user_session_state[\s\S]*?current_workspace_id[\s\S]*?WHERE[\s\S]*?current_workspace_id\s+IS\s+NULL/i);
      expect(executable).toMatch(/GET\s+DIAGNOSTICS/i);
    });

    it("ALTER ADD column precedes the hook CREATE OR REPLACE (hook reads the column)", () => {
      const addIdx = executable.search(/ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+current_workspace_id/i);
      const hookIdx = executable.search(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.runtime_jwt_mint_hook/i);
      expect(addIdx).toBeGreaterThan(-1);
      expect(hookIdx).toBeGreaterThan(-1);
      expect(addIdx).toBeLessThan(hookIdx);
    });
  });

  describe("runtime_jwt_mint_hook extension (AC10 — preserve org + OTP)", () => {
    const fnBlock =
      executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.runtime_jwt_mint_hook[\s\S]*?\$\$;/i,
      )?.[0] || "";

    it("still injects current_organization_id (org block preserved)", () => {
      expect(fnBlock).toMatch(/'\{current_organization_id\}'/);
    });

    it("newly injects current_workspace_id", () => {
      expect(fnBlock).toMatch(/'\{current_workspace_id\}'/);
    });

    it("preserves the OTP precheck block verbatim (precheck_jwt_mint + jti/exp/iat)", () => {
      expect(fnBlock).toMatch(/IF\s+v_auth_method\s*=\s*'otp'/i);
      expect(fnBlock).toMatch(/public\.precheck_jwt_mint/);
      expect(fnBlock).toMatch(/'\{jti\}'/);
      expect(fnBlock).toMatch(/'"soleur-runtime"'/);
    });

    it("does NOT swallow errors (no EXCEPTION WHEN OTHERS)", () => {
      expect(fnBlock).not.toMatch(/EXCEPTION\s+WHEN\s+OTHERS/i);
    });

    it("hook grant stays supabase_auth_admin (NOT authenticated)", () => {
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.runtime_jwt_mint_hook\s*\([^)]*\)\s+TO\s+supabase_auth_admin/i,
      );
      expect(executable).not.toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.runtime_jwt_mint_hook\s*\([^)]*\)\s+TO\s+authenticated/i,
      );
    });
  });

  describe("set_current_workspace_id RPC (AC8)", () => {
    const fnBlock =
      executable.match(
        /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.set_current_workspace_id[\s\S]*?\$\$;/i,
      )?.[0] || "";

    it("declares (p_workspace_id uuid), plpgsql, SECURITY DEFINER, search_path pin", () => {
      expect(fnBlock).toMatch(/FUNCTION\s+public\.set_current_workspace_id\s*\(\s*p_workspace_id\s+uuid\s*\)/i);
      expect(fnBlock).toMatch(/LANGUAGE\s+plpgsql/i);
      expect(fnBlock).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
    });

    it("guards null-auth (28000), null-arg (22004), non-member (42501)", () => {
      expect(fnBlock).toMatch(/ERRCODE\s*=\s*'28000'/);
      expect(fnBlock).toMatch(/ERRCODE\s*=\s*'22004'/);
      expect(fnBlock).toMatch(/ERRCODE\s*=\s*'42501'/);
      expect(fnBlock).toMatch(/is_workspace_member\s*\(/i);
    });

    it("FK-race guard: raises if organization_id lookup is NULL", () => {
      expect(fnBlock).toMatch(/SELECT\s+organization_id\s+INTO\s+v_org_id\s+FROM\s+public\.workspaces/i);
      expect(fnBlock).toMatch(/IF\s+v_org_id\s+IS\s+NULL\s+THEN[\s\S]*?RAISE\s+EXCEPTION/i);
    });

    it("upserts BOTH current_workspace_id AND current_organization_id", () => {
      expect(fnBlock).toMatch(/current_workspace_id/);
      expect(fnBlock).toMatch(/current_organization_id/);
      expect(fnBlock).toMatch(/ON\s+CONFLICT\s*\(\s*user_id\s*\)\s+DO\s+UPDATE/i);
    });

    it("4-role REVOKE + GRANT EXECUTE to authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.set_current_workspace_id\s*\([^)]*\)\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.set_current_workspace_id\s*\([^)]*\)\s+TO\s+authenticated/i,
      );
    });
  });

  describe("migration hygiene", () => {
    it("does NOT use CREATE INDEX CONCURRENTLY (supabase wraps in tx)", () => {
      expect(executable).not.toMatch(/CREATE\s+INDEX\s+CONCURRENTLY/i);
    });
  });

  describe("down migration", () => {
    const down = readFileSync(DOWN_PATH, "utf8");
    const downExec = down.replace(/--[^\n]*/g, "");

    it("drops both new RPCs", () => {
      expect(downExec).toMatch(/DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.set_current_workspace_id/i);
      expect(downExec).toMatch(/DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.resolve_workspace_installation_id/i);
    });

    it("reverts the hook (no current_workspace_id injection in the down body)", () => {
      const fnBlock =
        downExec.match(
          /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.runtime_jwt_mint_hook[\s\S]*?\$\$;/i,
        )?.[0] || "";
      expect(fnBlock).not.toBe("");
      expect(fnBlock).not.toMatch(/current_workspace_id/);
      // still preserves org injection.
      expect(fnBlock).toMatch(/'\{current_organization_id\}'/);
    });

    it("drops the current_workspace_id column, indexes, and repo columns; restores the table grant", () => {
      expect(downExec).toMatch(/DROP\s+COLUMN\s+IF\s+EXISTS\s+current_workspace_id/i);
      expect(downExec).toMatch(/DROP\s+INDEX\s+IF\s+EXISTS\s+public\.workspaces_installation_repo_idx/i);
      expect(downExec).toMatch(/DROP\s+COLUMN\s+IF\s+EXISTS\s+github_installation_id/i);
      expect(downExec).toMatch(/GRANT\s+SELECT\s+ON\s+public\.workspaces\s+TO\s+authenticated/i);
    });
  });
});

// ---------------------------------------------------------------------
// Behavioral integration tests — declared but skipped until the
// migration ships and TENANT_INTEGRATION_TEST=1 against a live dev
// Supabase project via process.env.DATABASE_URL_POOLER (per
// hr-dev-prd-distinct-supabase-projects; NEVER the shared dev pre-merge).
// Kept concrete enough that uncommenting + wiring a pg client suffices.
// ---------------------------------------------------------------------
describe.skip("079 — integration tests applied after migration runs", () => {
  it("AC2: a member cannot SELECT github_installation_id of their own workspace under the authenticated role", () => {
    // Setup (as the workspace owner's JWT / authenticated role):
    //   SET ROLE authenticated; SET request.jwt.claim.sub = '<member-uuid>';
    // Assert the column is not selectable:
    //   await expect(pg.query(
    //     "SELECT github_installation_id FROM public.workspaces WHERE id = $1",
    //     [workspaceId]
    //   )).rejects.toThrow(/permission denied for (column|table)/);
    // And the non-credential columns ARE selectable:
    //   const r = await pg.query(
    //     "SELECT repo_url, repo_status FROM public.workspaces WHERE id = $1",
    //     [workspaceId]);
    //   expect(r.rows[0]).toHaveProperty("repo_url");
  });

  it("AC2: the value is obtainable only via resolve_workspace_installation_id for a member", () => {
    //   const r = await pg.query("SELECT public.resolve_workspace_installation_id($1) AS id", [memberWsId]);
    //   expect(r.rows[0].id).toBe(expectedInstallationId);
    // non-member → NULL:
    //   const n = await pg.query("SELECT public.resolve_workspace_installation_id($1) AS id", [otherWsId]);
    //   expect(n.rows[0].id).toBeNull();
  });

  it("AC8: set_current_workspace_id rejects null-arg (22004), non-member (42501); sets both claims for a member", () => {
    //   await expect(pg.query("SELECT public.set_current_workspace_id(NULL)")).rejects.toMatchObject({ code: "22004" });
    //   await expect(pg.query("SELECT public.set_current_workspace_id($1)", [nonMemberWsId])).rejects.toMatchObject({ code: "42501" });
    //   await pg.query("SELECT public.set_current_workspace_id($1)", [memberWsId]);
    //   const s = await pg.query("SELECT current_workspace_id, current_organization_id FROM public.user_session_state WHERE user_id = $1", [memberUuid]);
    //   expect(s.rows[0].current_workspace_id).toBe(memberWsId);
    //   expect(s.rows[0].current_organization_id).not.toBeNull();
  });

  it("AC10: runtime_jwt_mint_hook injects BOTH current_organization_id and current_workspace_id on the OTP path", () => {
    //   const event = { user_id: memberUuid, claims: { app_metadata: {} }, authentication_method: "otp" };
    //   const r = await pg.query("SELECT public.runtime_jwt_mint_hook($1::jsonb) AS out", [JSON.stringify(event)]);
    //   expect(r.rows[0].out.claims.app_metadata.current_organization_id).toBeDefined();
    //   expect(r.rows[0].out.claims.app_metadata.current_workspace_id).toBeDefined();
    //   expect(r.rows[0].out.claims.jti).toBeDefined(); // OTP mint still fires
  });

  it("079 + 079.down round-trips cleanly (apply, down, re-apply)", () => {
    // Apply 079 → assert columns present → apply 079.down → assert columns
    // gone + hook body has no current_workspace_id → re-apply 079.
  });
});
