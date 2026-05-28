import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Phase 5.1 — workspace RLS isolation contract (ADR-044, AC2/AC5).
//
// Locks the two-layer isolation guarantee the repo-ownership relocation
// depends on, split across the migration that owns each layer:
//
//   (a) ROW-level: `workspaces_select_for_members` (053:169) restricts
//       SELECT on public.workspaces to rows the caller is a member of
//       (`is_workspace_member(workspaces.id, auth.uid())`). A member
//       therefore cannot read another workspace's row at all. 079 must
//       NOT weaken this — moving repo credentials onto workspaces would
//       be moot if the row policy were dropped.
//
//   (b) COLUMN-level: Postgres RLS has no column scoping, so the row
//       policy alone would expose `github_installation_id` (a GitHub App
//       token grant) to every member of the row. 079 closes this with a
//       table-level `REVOKE SELECT ... FROM authenticated` + an explicit
//       non-credential re-GRANT, leaving the credential readable ONLY via
//       the membership-checked `resolve_workspace_installation_id` definer
//       RPC (deny → RETURN NULL, never raise).
//
// These are file-parse shape tests (mirror the 047/079 precedent):
// fast, run on every CI pass, and guard against a later migration
// silently re-granting the column or dropping the row policy. The
// behavioral proof (real role-switched SELECTs) lives in the gated
// describe.skip block at the bottom — it activates with
// TENANT_INTEGRATION_TEST=1 + a live Doppler DATABASE_URL_POOLER on a
// DEDICATED dev Supabase project at apply time, per
// hr-dev-prd-distinct-supabase-projects (NEVER the shared dev pre-merge).
//
// Plan: knowledge-base/project/plans/2026-05-28-feat-workspace-repo-ownership-plan.md §Phase 5
// ADR:  knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md

const ROW_POLICY_MIGRATION = path.resolve(
  __dirname,
  "../../supabase/migrations/053_organizations_and_workspace_members.sql",
);
const SCHEMA_MIGRATION = path.resolve(
  __dirname,
  "../../supabase/migrations/079_workspace_repo_ownership_schema.sql",
);

const stripComments = (sql: string) => sql.replace(/--[^\n]*/g, "");

describe("workspace RLS isolation (ADR-044 AC2/AC5)", () => {
  // Unwrapped on purpose: if either migration is missing this describe
  // throws at module load (RED), matching the 079 shape-test convention.
  const rowPolicySql = stripComments(readFileSync(ROW_POLICY_MIGRATION, "utf8"));
  const schemaSql = readFileSync(SCHEMA_MIGRATION, "utf8");
  const schemaExec = stripComments(schemaSql);

  describe("(a) row-level: members only see their own workspace rows", () => {
    it("053 defines workspaces_select_for_members gated by is_workspace_member(workspaces.id, auth.uid())", () => {
      const policy =
        rowPolicySql.match(
          /CREATE\s+POLICY\s+workspaces_select_for_members\s+ON\s+public\.workspaces[\s\S]*?;/i,
        )?.[0] || "";
      expect(policy).not.toBe("");
      expect(policy).toMatch(/FOR\s+SELECT\s+TO\s+authenticated/i);
      expect(policy).toMatch(
        /USING\s*\(\s*public\.is_workspace_member\s*\(\s*workspaces\.id\s*,\s*auth\.uid\(\)\s*\)\s*\)/i,
      );
    });

    it("079 does NOT drop or disable the row-level select policy (regression guard)", () => {
      // Relocating credentials onto workspaces is only safe while the row
      // policy stands. A future edit that drops it must fail here first.
      expect(schemaExec).not.toMatch(
        /DROP\s+POLICY[\s\S]*?workspaces_select_for_members/i,
      );
      expect(schemaExec).not.toMatch(
        /ALTER\s+TABLE\s+public\.workspaces\s+DISABLE\s+ROW\s+LEVEL\s+SECURITY/i,
      );
    });
  });

  describe("(b) column-level: github_installation_id is not readable by authenticated", () => {
    it("079 revokes the table-level SELECT grant on workspaces from authenticated", () => {
      // Column-level REVOKE is a no-op while a table grant exists, so the
      // credential can only be hidden by revoking the table grant first.
      expect(schemaExec).toMatch(
        /REVOKE\s+SELECT\s+ON\s+public\.workspaces\s+FROM\s+authenticated/i,
      );
    });

    it("079 re-grants SELECT on the non-credential columns only (github_installation_id excluded)", () => {
      const grant =
        schemaExec.match(
          /GRANT\s+SELECT\s*\(([^)]*)\)\s+ON\s+public\.workspaces\s+TO\s+authenticated/i,
        )?.[1] || "";
      expect(grant).not.toBe("");
      // Members still see repo presence + status (UI badge, J5/J6).
      expect(grant).toMatch(/\brepo_url\b/);
      expect(grant).toMatch(/\brepo_status\b/);
      // The credential column must NOT be re-granted.
      expect(grant).not.toMatch(/github_installation_id/);
    });

    it("the credential is readable ONLY via the membership-checked resolve RPC (deny → RETURN NULL)", () => {
      const fnBlock =
        schemaExec.match(
          /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.resolve_workspace_installation_id[\s\S]*?\$\$;/i,
        )?.[0] || "";
      expect(fnBlock).not.toBe("");
      expect(fnBlock).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
      // Membership gate; non-member returns NULL rather than raising
      // (deny must be indistinguishable from "not connected").
      expect(fnBlock).toMatch(
        /IF\s+NOT\s+public\.is_workspace_member\s*\(\s*p_workspace_id\s*,\s*auth\.uid\(\)\s*\)\s+THEN[\s\S]*?RETURN\s+NULL/i,
      );
      expect(fnBlock).not.toMatch(/RAISE\s+EXCEPTION/i);
      // It is the only function selecting the credential column.
      expect(fnBlock).toMatch(/SELECT\s+github_installation_id\s+INTO/i);
    });

    it("the resolve RPC is executable by authenticated and revoked from anon/PUBLIC", () => {
      expect(schemaExec).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.resolve_workspace_installation_id\s*\([^)]*\)\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role/i,
      );
      expect(schemaExec).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.resolve_workspace_installation_id\s*\([^)]*\)\s+TO\s+authenticated/i,
      );
    });
  });
});

// ---------------------------------------------------------------------
// Behavioral integration tests — declared but skipped until the
// migration is applied to a DEDICATED dev Supabase project with
// TENANT_INTEGRATION_TEST=1 and a live Doppler DATABASE_URL_POOLER (per
// hr-dev-prd-distinct-supabase-projects; NEVER the shared dev pre-merge).
// Kept concrete enough that uncommenting + wiring a pg client suffices.
//
// Fixtures (synthesized, two tenants):
//   ws_self  — workspace the member belongs to (role=owner|member)
//   ws_other — workspace the member is NOT a member of
//   Both rows carry a non-null github_installation_id.
// ---------------------------------------------------------------------
describe.skip("079 RLS isolation — integration (applied dev project)", () => {
  it("(a) a member cannot SELECT another workspace's row (row policy filters it out)", () => {
    // SET ROLE authenticated; SET request.jwt.claim.sub = '<member-uuid>';
    //   const r = await pg.query(
    //     "SELECT id FROM public.workspaces WHERE id = $1", [wsOther]);
    //   expect(r.rowCount).toBe(0); // filtered, not errored
    //   const own = await pg.query(
    //     "SELECT id FROM public.workspaces WHERE id = $1", [wsSelf]);
    //   expect(own.rowCount).toBe(1);
  });

  it("(b) a member cannot SELECT github_installation_id of their OWN workspace (column denied)", () => {
    // SET ROLE authenticated; SET request.jwt.claim.sub = '<member-uuid>';
    //   await expect(pg.query(
    //     "SELECT github_installation_id FROM public.workspaces WHERE id = $1",
    //     [wsSelf],
    //   )).rejects.toThrow(/permission denied for (column|table)/);
    //   // non-credential columns on the SAME row stay readable:
    //   const r = await pg.query(
    //     "SELECT repo_url, repo_status FROM public.workspaces WHERE id = $1",
    //     [wsSelf]);
    //   expect(r.rows[0]).toHaveProperty("repo_url");
  });

  it("(b) the credential is obtainable only via resolve_workspace_installation_id for a member; non-member → NULL", () => {
    // member resolving own workspace gets the value:
    //   const r = await pg.query(
    //     "SELECT public.resolve_workspace_installation_id($1) AS id", [wsSelf]);
    //   expect(r.rows[0].id).toBe(expectedInstallationId);
    // member resolving a workspace they don't belong to → NULL (no raise):
    //   const n = await pg.query(
    //     "SELECT public.resolve_workspace_installation_id($1) AS id", [wsOther]);
    //   expect(n.rows[0].id).toBeNull();
  });
});
