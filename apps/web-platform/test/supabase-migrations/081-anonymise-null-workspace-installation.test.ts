import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 081_anonymise_null_workspace_installation.sql.
//
// AC11 (GDPR Art-17): when a user is anonymised, the GitHub App
// installation grant (workspaces.github_installation_id) they connected
// must be erased from every workspace in the orgs they owned — the
// installation_id IS the departing user's GitHub authorization; retaining
// it would let the org keep using their grant. ADR-044 relocated the
// credential from users to workspaces, so the existing
// anonymise_organization_membership (mig 078) does not yet null it.
//
// 081 CREATE OR REPLACEs the function (preserving the 078 owner-transfer
// logic) and adds the workspace-credential erasure. .down.sql reverts to
// the exact 078 body (no workspace credential null).

const MIGRATION_PATH = path.resolve(
  __dirname,
  "../../supabase/migrations/081_anonymise_null_workspace_installation.sql",
);
const DOWN_PATH = path.resolve(
  __dirname,
  "../../supabase/migrations/081_anonymise_null_workspace_installation.down.sql",
);

describe("migration 081_anonymise_null_workspace_installation", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const executable = sql.replace(/--[^\n]*/g, "");

  const fnBlock =
    executable.match(
      /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_organization_membership[\s\S]*?\$\$;/i,
    )?.[0] || "";

  it("CREATE OR REPLACEs anonymise_organization_membership (SECURITY DEFINER, search_path pinned)", () => {
    expect(fnBlock).not.toBe("");
    expect(fnBlock).toMatch(/SECURITY\s+DEFINER/i);
    expect(fnBlock).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
  });

  it("nulls workspaces.github_installation_id for the departing user's orgs (Art-17)", () => {
    expect(fnBlock).toMatch(
      /UPDATE\s+public\.workspaces[\s\S]*?SET[\s\S]*?github_installation_id\s*=\s*NULL/i,
    );
  });

  it("scopes the credential erasure to the owned org's workspaces", () => {
    // The UPDATE must filter by organization_id (the loop's org), not blanket.
    expect(fnBlock).toMatch(
      /UPDATE\s+public\.workspaces[\s\S]*?WHERE[\s\S]*?organization_id\s*=\s*v_org_rec\.org_id/i,
    );
  });

  it("preserves the 078 owner-transfer logic (replacement promotion)", () => {
    expect(fnBlock).toMatch(/owner_user_id\s*=\s*v_replacement_user_id/i);
    expect(fnBlock).toMatch(/role\s*=\s*'owner'/i);
  });

  it("keeps the 078 grant shape (service_role only)", () => {
    expect(executable).toMatch(
      /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.anonymise_organization_membership\(uuid\)[\s\S]*?FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated/i,
    );
    expect(executable).toMatch(
      /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.anonymise_organization_membership\(uuid\)[\s\S]*?TO\s+service_role/i,
    );
  });

  describe("down migration", () => {
    const down = readFileSync(DOWN_PATH, "utf8");
    const downExec = down.replace(/--[^\n]*/g, "");
    const downFn =
      downExec.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_organization_membership[\s\S]*?\$\$;/i,
      )?.[0] || "";

    it("reverts to the 078 body (no workspace credential erasure)", () => {
      expect(downFn).not.toBe("");
      expect(downFn).not.toMatch(/github_installation_id\s*=\s*NULL/i);
    });
  });
});
