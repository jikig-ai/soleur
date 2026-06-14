import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 103 (disk-IO recurrence remediation, 2026-06-14).
//
// 103_github_events_retention_7day.sql shortens the processed_github_events
// retention window from 90 days (set by 094) to 7 days. The 90-day window was
// copied from the processed_stripe_events sibling (where 90d = Stripe's replay
// horizon), but GitHub's webhook redelivery horizon is 3 days on github.com
// (delivery logs are deleted after 3 days; no redelivery is possible past
// then). So the 094 sweep ran nightly yet always reported DELETE 0 (the table's
// oldest row never reached 90 days) and the table bloated to a ~450k-row steady
// state, driving the WRITE-side Disk-IO burn that depleted the budget and fired
// the monitor (issue #5225, 123,416 rows on 2026-06-12). 7 days clears the
// 3-day github.com ceiling with >2x margin; a second layer (Inngest 24h
// event.id dedup) backs it. The same file also runs a one-time purge of the
// already-stale rows so relief lands at deploy.
//
// File-parse test, not a live-DB test — pins the SQL contract. Mirrors
// 094-dedup-retention.test.ts.
//
// Plan: knowledge-base/project/plans/2026-06-14-fix-supabase-disk-io-github-events-retention-window-plan.md

const MIG_DIR = path.join(__dirname, "../../supabase/migrations");
const stripComments = (sql: string) => sql.replace(/--[^\n]*/g, "");

const executable = stripComments(
  readFileSync(
    path.join(MIG_DIR, "103_github_events_retention_7day.sql"),
    "utf8",
  ),
);
const down = stripComments(
  readFileSync(
    path.join(MIG_DIR, "103_github_events_retention_7day.down.sql"),
    "utf8",
  ),
);

describe("migration 103_github_events_retention_7day — re-schedule", () => {
  it("unschedules the existing job by name (idempotent guard)", () => {
    expect(executable).toMatch(
      /cron\.unschedule\s*\(\s*'processed_github_events_retention'\s*\)/i,
    );
  });

  it("re-schedules the sweep daily at 04:00 UTC", () => {
    expect(executable).toMatch(
      /cron\.schedule\s*\(\s*'processed_github_events_retention'\s*,\s*'0\s+4\s+\*\s+\*\s+\*'/i,
    );
  });

  it("scheduled sweep DELETEs rows older than the 7-day window using received_at", () => {
    expect(executable).toMatch(
      /delete\s+from\s+public\.processed_github_events\s+where\s+received_at\s*<\s*now\(\)\s*-\s*interval\s+'7\s+days'/i,
    );
  });

  it("does NOT retain the old 90-day window", () => {
    expect(executable).not.toMatch(/interval\s+'90\s+days'/i);
  });

  it("does NOT use a non-existent created_at column", () => {
    expect(executable).not.toMatch(/processed_github_events[\s\S]*?created_at/i);
  });

  it("guards idempotency with EXCEPTION WHEN duplicate_object", () => {
    // The re-schedule's idempotency rests on both the cron.unschedule guard
    // (asserted above) AND this exception handler; pin both so a regression
    // dropping the handler is visible.
    expect(executable).toMatch(/exception\s+when\s+duplicate_object/i);
  });
});

describe("migration 103_github_events_retention_7day — one-time purge", () => {
  // Strip the cron.schedule($$...$$) body so only top-level statements remain.
  // The one-time purge must survive as a bare top-level DELETE — a position-
  // aware check, NOT a position-blind count (a duplicated cron body must not
  // satisfy it; dropping the at-deploy purge must fail).
  const topLevel = executable.replace(/\$\$[\s\S]*?\$\$/g, "");

  it("runs exactly one one-time top-level DELETE of rows older than 7 days at deploy", () => {
    const matches = topLevel.match(
      /delete\s+from\s+public\.processed_github_events\s+where\s+received_at\s*<\s*now\(\)\s*-\s*interval\s+'7\s+days'/gi,
    );
    expect(matches).not.toBeNull();
    expect(matches!.length).toBe(1);
  });
});

describe("migration 103_github_events_retention_7day — stale-comment correction", () => {
  it("corrects the COMMENT ON TABLE, states the new window, and drops the false 'partition rotation' claim", () => {
    expect(executable).toMatch(
      /comment\s+on\s+table\s+public\.processed_github_events\s+is/i,
    );
    // Pin the corrected mechanism is present (not just that the false claim is gone).
    expect(executable).toMatch(/comment\s+on\s+table[\s\S]*?7 days/i);
    expect(executable).not.toMatch(/partition\s+rotation/i);
  });
});

describe("migration 103_github_events_retention_7day — down", () => {
  it("restores the 90-day schedule (framework reversibility only)", () => {
    expect(down).toMatch(
      /cron\.schedule\s*\(\s*'processed_github_events_retention'\s*,\s*'0\s+4\s+\*\s+\*\s+\*'/i,
    );
    expect(down).toMatch(
      /delete\s+from\s+public\.processed_github_events\s+where\s+received_at\s*<\s*now\(\)\s*-\s*interval\s+'90\s+days'/i,
    );
  });
});
