import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 080_backfill_workspace_repo_from_users.sql.
//
// Plan §Phase 080: copy users repo cols → workspaces joined on w.id=u.id
// (solo-only by construction), guarded by a canary owner-row + sole-member
// count so a repo is NEVER landed onto a co-membered workspace (Kieran
// P1-3 / CLO requirement). Idempotent (WHERE w.repo_url IS NULL). users
// columns stay authoritative (NOT dropped here). The .down.sql is
// scoped-forward-only (nulls only rows still equal to the source).
//
// Behavioral verification against a real dev DB lives in the gated
// describe.skip block (TENANT_INTEGRATION_TEST=1 + DATABASE_URL_POOLER,
// dedicated dev project per hr-dev-prd-distinct-supabase-projects).
//
// Plan: knowledge-base/project/plans/2026-05-28-feat-workspace-repo-ownership-plan.md §Phase 080
// ADR: knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md

const MIGRATION_PATH = path.resolve(
  __dirname,
  "../../supabase/migrations/080_backfill_workspace_repo_from_users.sql",
);
const DOWN_PATH = path.resolve(
  __dirname,
  "../../supabase/migrations/080_backfill_workspace_repo_from_users.down.sql",
);

describe("migration 080_backfill_workspace_repo_from_users", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const executable = sql.replace(/--[^\n]*/g, "");

  describe("backfill copy", () => {
    it("UPDATEs workspaces from users joined on w.id = u.id", () => {
      expect(executable).toMatch(/UPDATE\s+public\.workspaces\s+w/i);
      expect(executable).toMatch(/FROM\s+public\.users\s+u/i);
      expect(executable).toMatch(/WHERE[\s\S]*?w\.id\s*=\s*u\.id/i);
    });

    it("copies all five repo columns", () => {
      expect(executable).toMatch(/repo_url\s*=\s*u\.repo_url/i);
      expect(executable).toMatch(/repo_provider\s*=\s*u\.repo_provider/i);
      expect(executable).toMatch(/github_installation_id\s*=\s*u\.github_installation_id/i);
      expect(executable).toMatch(/repo_status\s*=\s*u\.repo_status/i);
      expect(executable).toMatch(/repo_last_synced_at\s*=\s*u\.repo_last_synced_at/i);
    });

    it("is idempotent: guards WHERE w.repo_url IS NULL", () => {
      expect(executable).toMatch(/w\.repo_url\s+IS\s+NULL/i);
    });

    it("only copies when the user actually has a repo (u.repo_url IS NOT NULL)", () => {
      expect(executable).toMatch(/u\.repo_url\s+IS\s+NOT\s+NULL/i);
    });
  });

  describe("co-member safety guard (Kieran P1-3 / CLO)", () => {
    it("requires a canary owner-row (workspace_members user_id = w.id, role 'owner')", () => {
      expect(executable).toMatch(
        /EXISTS\s*\([\s\S]*?workspace_members[\s\S]*?user_id\s*=\s*w\.id[\s\S]*?role\s*=\s*'owner'[\s\S]*?\)/i,
      );
    });

    it("requires sole membership (COUNT(*) = 1) before adopting the repo", () => {
      expect(executable).toMatch(
        /\(\s*SELECT\s+COUNT\(\*\)\s+FROM\s+public\.workspace_members[\s\S]*?\)\s*=\s*1/i,
      );
    });

    it("logs SKIPPED co-membered workspaces (COUNT > 1) for owner re-consent", () => {
      expect(executable).toMatch(/COUNT\(\*\)[\s\S]*?>\s*1/i);
      expect(executable).toMatch(/RAISE\s+NOTICE[\s\S]*?SKIP/i);
    });
  });

  describe("audit + hygiene", () => {
    it("emits a GET DIAGNOSTICS / RAISE NOTICE row-count audit", () => {
      expect(executable).toMatch(/GET\s+DIAGNOSTICS/i);
      expect(executable).toMatch(/RAISE\s+NOTICE/i);
    });

    it("does NOT drop the users repo columns (kept authoritative until decommission)", () => {
      expect(executable).not.toMatch(/ALTER\s+TABLE\s+public\.users[\s\S]*?DROP\s+COLUMN/i);
    });

    it("does NOT use CREATE INDEX CONCURRENTLY", () => {
      expect(executable).not.toMatch(/CREATE\s+INDEX\s+CONCURRENTLY/i);
    });
  });

  describe("down migration (scoped-forward-only)", () => {
    const down = readFileSync(DOWN_PATH, "utf8");
    const downExec = down.replace(/--[^\n]*/g, "");

    it("nulls only rows still equal to the users source (NOT a blanket SET NULL)", () => {
      // A blanket `UPDATE workspaces SET repo_url = NULL` would destroy
      // repos connected DIRECTLY to a workspace after 080. The down must
      // scope to rows still matching the source.
      expect(downExec).toMatch(/UPDATE\s+public\.workspaces\s+w/i);
      expect(downExec).toMatch(/FROM\s+public\.users\s+u/i);
      expect(downExec).toMatch(/w\.id\s*=\s*u\.id/i);
      expect(downExec).toMatch(/w\.repo_url\s+IS\s+NOT\s+DISTINCT\s+FROM\s+u\.repo_url/i);
      // Negative-space: no unscoped blanket null of repo_url.
      expect(downExec).not.toMatch(/SET\s+repo_url\s*=\s*NULL\s*;/i);
    });
  });
});

// ---------------------------------------------------------------------
// Behavioral integration tests — applied after migration runs against a
// dedicated dev Supabase project (TENANT_INTEGRATION_TEST=1 +
// DATABASE_URL_POOLER). NEVER the shared dev project pre-merge.
// ---------------------------------------------------------------------
describe.skip("080 — integration tests applied after migration runs", () => {
  it("AC3: second apply copies 0 rows (idempotent)", () => {
    // Apply 080 twice; capture the RAISE NOTICE row count on the 2nd run.
    // Assert the 2nd run logs "0 rows copied".
  });

  it("AC3: a solo workspace invited-into (canary present, member count > 1) is SKIPPED + NOTICE-logged", () => {
    // Seed: user U with repo on users; workspace W (id = U.id) with an
    // owner row for U AND a member row for a second user V.
    // Apply 080. Assert W.repo_url stays NULL and a SKIP NOTICE names W.id.
  });

  it("backfill copies the solo workspace's repo verbatim from users", () => {
    // Seed: solo user U with repo on users; W (id=U.id) sole-member owner.
    // Apply 080. Assert W.{repo_url, github_installation_id, ...} == U.{...}.
  });
});
