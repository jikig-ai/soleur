import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 114 (disk-IO monitor WAL-concentration lens, #5736).
//
// 114_disk_io_top_wal_statements.sql CREATE OR REPLACEs disk_io_pressure_signal()
// (first created by 095) to ALSO return top_wal_statements (top-5 by
// pg_stat_statements.wal_bytes) + max_wal_pct, while PRESERVING every 095 field.
// The cron-supabase-disk-io monitor reads max_wal_pct and emits a Sentry
// op=wal-concentration capture when one statement dominates prod WAL — the class
// PR #5736 missed (a webhook dedup INSERT was 63% of WAL).
//
// The generic SECURITY DEFINER grant + search_path lint is enforced by
// migration-rpc-grants.test.ts (which also scans the .down.sql); this file pins
// the 114 signal's specific shape + the 095 preservation.

const MIG_DIR = path.join(__dirname, "../../supabase/migrations");
const stripComments = (sql: string) => sql.replace(/--[^\n]*/g, "");

const executable = stripComments(
  readFileSync(path.join(MIG_DIR, "114_disk_io_top_wal_statements.sql"), "utf8"),
);
const down = stripComments(
  readFileSync(
    path.join(MIG_DIR, "114_disk_io_top_wal_statements.down.sql"),
    "utf8",
  ),
);

describe("migration 114_disk_io_top_wal_statements", () => {
  it("CREATE OR REPLACEs the public.disk_io_pressure_signal() RPC", () => {
    expect(executable).toMatch(
      /create\s+or\s+replace\s+function\s+public\.disk_io_pressure_signal\s*\(\s*\)/i,
    );
  });

  it("is SECURITY DEFINER with a public-first, pg_temp-pinned search_path", () => {
    expect(executable).toMatch(/security\s+definer/i);
    expect(executable).toMatch(/set\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
  });

  it("adds top_wal_statements + max_wal_pct sourced from pg_stat_statements.wal_bytes", () => {
    expect(executable).toMatch(/top_wal_statements/);
    expect(executable).toMatch(/max_wal_pct/);
    expect(executable).toMatch(/wal_bytes/);
  });

  it("schema-qualifies pg_stat_statements as extensions.pg_stat_statements", () => {
    // search_path is pinned `public, pg_temp` (no `extensions`), so an
    // unqualified reference would not resolve — the schema qualifier is
    // load-bearing for the function to plan at CREATE time.
    expect(executable).toMatch(/extensions\.pg_stat_statements/);
    // Guard against an UNqualified `FROM pg_stat_statements` slipping in.
    expect(executable).not.toMatch(/from\s+pg_stat_statements\b/i);
  });

  it("PRESERVES the 095 fields (cache_hit_pct, dedup_table_rows, top_write_churn)", () => {
    expect(executable).toMatch(/cache_hit_pct/);
    expect(executable).toMatch(/dedup_table_rows/);
    expect(executable).toMatch(/top_write_churn/);
    expect(executable).toMatch(/processed_github_events/);
  });

  it("REVOKEs broadly and GRANTs EXECUTE to service_role only", () => {
    expect(executable).toMatch(
      /revoke\s+all\s+on\s+function\s+public\.disk_io_pressure_signal\s*\(\s*\)\s+from\s+public\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role/i,
    );
    expect(executable).toMatch(
      /grant\s+execute\s+on\s+function\s+public\.disk_io_pressure_signal\s*\(\s*\)\s+to\s+service_role/i,
    );
  });

  it("is read-only (no INSERT/UPDATE/DELETE in the function body)", () => {
    expect(executable).not.toMatch(/\b(insert\s+into|update\s+public|delete\s+from)\b/i);
  });

  it("down migration restores the prior (095) body WITHOUT the WAL fields", () => {
    // Reversal is a CREATE OR REPLACE back to the 095 shape, not a DROP (a DROP
    // would remove the function the cron depends on).
    expect(down).toMatch(
      /create\s+or\s+replace\s+function\s+public\.disk_io_pressure_signal\s*\(\s*\)/i,
    );
    expect(down).toMatch(/cache_hit_pct/);
    expect(down).not.toMatch(/top_wal_statements/);
    expect(down).not.toMatch(/max_wal_pct/);
    // The down file re-creates a SECURITY DEFINER fn, so it must itself carry the
    // search_path pin + the REVOKE (the rpc-grant lint scans .down.sql too).
    expect(down).toMatch(/set\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
    expect(down).toMatch(
      /revoke\s+all\s+on\s+function\s+public\.disk_io_pressure_signal/i,
    );
  });
});
