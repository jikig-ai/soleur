import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 110_workspace_repo_error_and_comember_reconcile.sql
// (ADR-044 PR-2 team write-cutover, #5462 — Phase 1).
//
// Offline lint — runs without a live database. The live-DB drift proof (SOLO
// drift COUNT=0 post-reconcile + idempotency) runs at apply time via the
// verify/110_*.sql `check_name`/`bad` contract in CI verify-migrations and was
// also verified in a rolled-back dev txn at /work time. This source-shape test
// guards the load-bearing invariants a regression could silently drop:
//   - `workspaces.repo_error` column added IF NOT EXISTS (idempotent).
//   - the full non-credential GRANT is RE-ISSUED with `repo_error` appended
//     after a REVOKE SELECT (mirror 079 — NOT a partial column GRANT), and
//     `github_installation_id` stays OUT of the grant set (credential).
//   - the SOLO backfill carries the mig-080 canary-owner-row + sole-member
//     COUNT(*)=1 guards + the `WHERE w.repo_error IS NULL` idempotency guard.
//   - the co-membered SKIP backlog is NOT auto-adopted (no blind copy onto a
//     COUNT(*)>1 workspace) — CLO/PA-17(c) lawful-basis block.
//   - NO CONCURRENTLY (Supabase wraps each migration file in one txn).
//   - the down migration drops the column reversibly.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/110_workspace_repo_error_and_comember_reconcile.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/110_workspace_repo_error_and_comember_reconcile.down.sql",
);
const VERIFY_PATH = path.join(
  __dirname,
  "../../supabase/verify/110_workspace_repo_error_and_comember_reconcile.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const verifySql = readFileSync(VERIFY_PATH, "utf8");
// Strip line-comments so prose `--` lines don't false-match the patterns.
const executable = sql.replace(/--[^\n]*/g, "");
const verifyExecutable = verifySql.replace(/--[^\n]*/g, "");

describe("migration 110_workspace_repo_error_and_comember_reconcile", () => {
  it("adds workspaces.repo_error idempotently (ADD COLUMN IF NOT EXISTS)", () => {
    expect(executable).toMatch(
      /ALTER\s+TABLE\s+public\.workspaces\s+ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+repo_error\s+text/i,
    );
  });

  it("re-issues the FULL non-credential GRANT with repo_error after a REVOKE (not a partial column grant)", () => {
    expect(executable).toMatch(
      /REVOKE\s+SELECT\s+ON\s+public\.workspaces\s+FROM\s+authenticated/i,
    );
    // The full column list mirrors mig 079:89 + repo_error appended.
    const grant = executable.match(
      /GRANT\s+SELECT\s*\(([^)]*)\)\s+ON\s+public\.workspaces\s+TO\s+authenticated/i,
    );
    expect(grant).not.toBeNull();
    const cols = grant![1].replace(/\s+/g, " ");
    for (const c of [
      "id",
      "organization_id",
      "name",
      "created_at",
      "repo_url",
      "repo_provider",
      "repo_status",
      "repo_last_synced_at",
      "repo_error",
    ]) {
      expect(cols).toMatch(new RegExp(`\\b${c}\\b`));
    }
  });

  it("keeps github_installation_id OUT of the authenticated GRANT (credential)", () => {
    const grant = executable.match(
      /GRANT\s+SELECT\s*\(([^)]*)\)\s+ON\s+public\.workspaces\s+TO\s+authenticated/i,
    );
    expect(grant![1]).not.toMatch(/github_installation_id/);
  });

  it("backfills repo_error for SOLO rows with the canary-owner + sole-member + idempotency guards", () => {
    // Idempotency: re-runs touch 0 rows.
    expect(executable).toMatch(/w\.repo_error\s+IS\s+NULL/i);
    // Canary owner-row (the workspace is the user's own solo workspace).
    expect(executable).toMatch(/m\.user_id\s*=\s*w\.id/i);
    expect(executable).toMatch(/m\.role\s*=\s*'owner'/i);
    // Sole-member guard COUNT(*) = 1 — never adopt onto a co-membered workspace.
    expect(executable).toMatch(/COUNT\(\*\)[\s\S]*?\)\s*=\s*1/i);
  });

  it("does NOT auto-adopt the co-membered SKIP backlog (every repo-col UPDATE carries the sole-member = 1 guard)", () => {
    // Every UPDATE ... SET repo_url/repo_error/github_installation_id on
    // workspaces must be SOLO-guarded (COUNT(*) ... = 1). A COUNT(*) > 1 paired
    // with a repo-col copy would be the unlawful co-member auto-adoption. The
    // `> 1` audit block (step 5) is a read-only SELECT COUNT INTO, never an
    // UPDATE, so it is allowed.
    const updateBlocks = executable.match(
      /UPDATE\s+public\.workspaces[\s\S]*?(?=DO\s+\$\$|$)/gi,
    );
    expect(updateBlocks).not.toBeNull();
    for (const block of updateBlocks!) {
      if (/SET\s+repo_(url|error)|github_installation_id\s*=/i.test(block)) {
        expect(block).toMatch(/=\s*1/);
        expect(block).not.toMatch(/COUNT\(\*\)[\s\S]{0,40}>\s*1/i);
      }
    }
  });

  it("uses GET DIAGNOSTICS + RAISE NOTICE for the backfill row-count audit", () => {
    expect(executable).toMatch(/GET\s+DIAGNOSTICS\s+\w+\s*=\s*ROW_COUNT/i);
    expect(executable).toMatch(/RAISE\s+NOTICE/i);
  });

  it("uses no CONCURRENTLY (Supabase wraps the file in one txn)", () => {
    expect(executable).not.toMatch(/CONCURRENTLY/i);
  });

  it("documents the lawful basis (Art. 6) in the migration header", () => {
    expect(sql).toMatch(/LAWFUL_BASIS|Art\.\s*6/i);
  });

  it("down migration drops repo_error reversibly", () => {
    expect(downSql).toMatch(
      /ALTER\s+TABLE\s+public\.workspaces\s+DROP\s+COLUMN\s+IF\s+EXISTS\s+repo_error/i,
    );
  });
});

describe("verify 110 contract", () => {
  it("emits check_name + bad rows (CI verify-migrations contract)", () => {
    expect(verifyExecutable).toMatch(/AS\s+check_name/i);
    expect(verifyExecutable).toMatch(/AS\s+bad/i);
  });

  it("asserts the SOLO drift-gate COUNT scoped to sole-member workspaces", () => {
    expect(verifyExecutable).toMatch(/repo_drift_count/i);
    // The drift query mirrors ADR-044's PR-2b gate (users JOIN workspaces).
    expect(verifyExecutable).toMatch(/u\.repo_url\s+IS\s+NOT\s+NULL/i);
    expect(verifyExecutable).toMatch(
      /w\.repo_url\s+IS\s+DISTINCT\s+FROM\s+u\.repo_url/i,
    );
    expect(verifyExecutable).toMatch(
      /w\.github_installation_id\s+IS\s+DISTINCT\s+FROM\s+u\.github_installation_id/i,
    );
    // Scoped to SOLO rows (sole-member).
    expect(verifyExecutable).toMatch(/=\s*1/);
  });

  it("asserts 0 co-membered rows adopted WITHOUT an attestation (not 0 SKIP rows)", () => {
    expect(verifyExecutable).toMatch(/comember/i);
    expect(verifyExecutable).toMatch(/attestation/i);
  });
});
