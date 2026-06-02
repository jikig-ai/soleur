import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 095 (disk-IO monitor signal RPC, 2026-06-02).
//
// 095_disk_io_pressure_signal.sql adds a read-only SECURITY DEFINER RPC that the
// cron-supabase-disk-io Inngest monitor calls via the service-role client. It
// exposes a deterministic write-pressure signal (cache-hit ratio + the two
// unbounded dedup tables' live-row counts + top write-churn) sourced from
// pg_catalog stat views — which PostgREST cannot expose directly, hence the RPC.
//
// The generic SECURITY DEFINER grant + search_path lint is enforced by
// migration-rpc-grants.test.ts; this file pins the signal's specific shape.
//
// Plan: knowledge-base/project/plans/2026-06-02-fix-supabase-disk-io-recurrence-and-sentry-monitor-plan.md Phase 3.

const MIG_DIR = path.join(__dirname, "../../supabase/migrations");
const stripComments = (sql: string) => sql.replace(/--[^\n]*/g, "");

const executable = stripComments(
  readFileSync(path.join(MIG_DIR, "095_disk_io_pressure_signal.sql"), "utf8"),
);
const down = stripComments(
  readFileSync(path.join(MIG_DIR, "095_disk_io_pressure_signal.down.sql"), "utf8"),
);

describe("migration 095_disk_io_pressure_signal", () => {
  it("creates the public.disk_io_pressure_signal() RPC", () => {
    expect(executable).toMatch(
      /create\s+or\s+replace\s+function\s+public\.disk_io_pressure_signal\s*\(\s*\)/i,
    );
  });

  it("is SECURITY DEFINER with a public-first search_path pin", () => {
    expect(executable).toMatch(/security\s+definer/i);
    expect(executable).toMatch(/set\s+search_path\s*=\s*public\s*,\s*pg_temp/i);
  });

  it("sources the cache-hit ratio from pg_stat_database", () => {
    expect(executable).toMatch(/pg_stat_database/i);
    expect(executable).toMatch(/cache_hit_pct/i);
  });

  it("reports the two unbounded dedup tables' live-row counts from pg_stat_user_tables", () => {
    expect(executable).toMatch(/pg_stat_user_tables/i);
    expect(executable).toMatch(/processed_github_events/);
    expect(executable).toMatch(/processed_stripe_events/);
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
    // A monitor probe must never mutate. Guard against an accidental write.
    expect(executable).not.toMatch(/\b(insert\s+into|update\s+public|delete\s+from)\b/i);
  });

  it("down migration drops the function", () => {
    expect(down).toMatch(
      /drop\s+function\s+if\s+exists\s+public\.disk_io_pressure_signal\s*\(\s*\)/i,
    );
  });
});
