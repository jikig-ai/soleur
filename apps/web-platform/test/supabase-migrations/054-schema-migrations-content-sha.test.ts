import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 054_schema_migrations_content_sha.sql (#4241).
//
// Adds `content_sha text` column to `public._schema_migrations` so the
// drift probe at `.github/actions/dev-migration-drift-probe/action.yml`
// can detect same-filename / different-blob drift. Additive + nullable
// (no backfill, no NOT NULL) so existing rows stay valid.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/054_schema_migrations_content_sha.sql",
);

describe("migration 054_schema_migrations_content_sha", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const executable = sql.replace(/--[^\n]*/g, "");

  it("adds content_sha as nullable text via ADD COLUMN IF NOT EXISTS", () => {
    expect(executable).toMatch(
      /ALTER\s+TABLE\s+public\._schema_migrations[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+content_sha\s+text/i,
    );
  });

  it("does NOT add a NOT NULL constraint (existing rows would violate it)", () => {
    expect(executable).not.toMatch(/content_sha\s+text\s+NOT\s+NULL/i);
    expect(executable).not.toMatch(/ALTER\s+COLUMN\s+content_sha\s+SET\s+NOT\s+NULL/i);
  });

  it("does NOT backfill content_sha for existing rows", () => {
    // Backfill would require re-reading historical file content from git;
    // intentional design choice is to leave pre-054 rows NULL and only
    // populate going forward (drift probe skips NULL rows from comparison).
    expect(executable).not.toMatch(
      /UPDATE\s+public\._schema_migrations\s+SET\s+content_sha/i,
    );
  });

  it("includes a COMMENT explaining the apply-time-only contract", () => {
    expect(sql).toMatch(/COMMENT\s+ON\s+COLUMN\s+public\._schema_migrations\.content_sha/i);
    expect(sql).toMatch(/apply-time/i);
  });
});
