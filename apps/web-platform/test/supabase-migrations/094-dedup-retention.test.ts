import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 094 (disk-IO recurrence remediation, 2026-06-02).
//
// 094_dedup_tables_retention.sql adds the daily pg_cron retention sweeps that
// migrations 052 (processed_github_events) and 030 (processed_stripe_events)
// both deferred "to a follow-up issue" but never landed. At 2026-06-02 the
// GitHub dedup table had 65,240 live rows / 0 deletes and was the #3 prod
// Disk-IO write consumer (unbounded INSERT growth). The Stripe sibling is the
// same prunable class (1 row today, but unbounded). Both replay windows are 90d
// (verified: processed_github_events via app/api/webhooks/github/route.ts:347
// "GitHub's redelivery limit"; processed_stripe_events via migration 030 "rows
// older than Stripe's replay window (90d)").
//
// File-parse test, not a live-DB test — pins the SQL contract. Mirrors
// 038-039-disk-io-fix.test.ts.
//
// Plan: knowledge-base/project/plans/2026-06-02-fix-supabase-disk-io-recurrence-and-sentry-monitor-plan.md Phase 2.

const MIG_DIR = path.join(__dirname, "../../supabase/migrations");
const stripComments = (sql: string) => sql.replace(/--[^\n]*/g, "");

const executable = stripComments(
  readFileSync(path.join(MIG_DIR, "094_dedup_tables_retention.sql"), "utf8"),
);
const down = stripComments(
  readFileSync(path.join(MIG_DIR, "094_dedup_tables_retention.down.sql"), "utf8"),
);

describe("migration 094_dedup_tables_retention — processed_github_events", () => {
  it("unschedules the existing job by name (idempotent guard)", () => {
    expect(executable).toMatch(
      /cron\.unschedule\s*\(\s*'processed_github_events_retention'\s*\)/i,
    );
  });

  it("schedules the sweep daily at 04:00 UTC", () => {
    expect(executable).toMatch(
      /cron\.schedule\s*\(\s*'processed_github_events_retention'\s*,\s*'0\s+4\s+\*\s+\*\s+\*'/i,
    );
  });

  it("DELETEs rows older than the 90-day replay window using received_at", () => {
    expect(executable).toMatch(
      /delete\s+from\s+public\.processed_github_events\s+where\s+received_at\s*<\s*now\(\)\s*-\s*interval\s+'90\s+days'/i,
    );
  });

  it("does NOT use a non-existent created_at column", () => {
    expect(executable).not.toMatch(/processed_github_events[\s\S]*?created_at/i);
  });
});

describe("migration 094_dedup_tables_retention — processed_stripe_events", () => {
  it("unschedules the existing job by name (idempotent guard)", () => {
    expect(executable).toMatch(
      /cron\.unschedule\s*\(\s*'processed_stripe_events_retention'\s*\)/i,
    );
  });

  it("schedules the sweep daily at 04:00 UTC", () => {
    expect(executable).toMatch(
      /cron\.schedule\s*\(\s*'processed_stripe_events_retention'\s*,\s*'0\s+4\s+\*\s+\*\s+\*'/i,
    );
  });

  it("DELETEs rows older than the 90-day replay window using processed_at", () => {
    expect(executable).toMatch(
      /delete\s+from\s+public\.processed_stripe_events\s+where\s+processed_at\s*<\s*now\(\)\s*-\s*interval\s+'90\s+days'/i,
    );
  });
});

describe("migration 094_dedup_tables_retention — down", () => {
  it("unschedules both retention jobs", () => {
    expect(down).toMatch(
      /cron\.unschedule\s*\(\s*'processed_github_events_retention'\s*\)/i,
    );
    expect(down).toMatch(
      /cron\.unschedule\s*\(\s*'processed_stripe_events_retention'\s*\)/i,
    );
  });
});
