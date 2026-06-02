// cron-supabase-disk-io — proactive prod Disk-IO early-warning monitor.
//
// Tests the deterministic verdict function with synthesized signal fixtures
// (no live DB, no live Sentry, no octokit) per the plan's Phase 3 test design.
// The verdict is the gate: a fixture below the cache-hit floor OR above the
// dedup-row ceiling must trip; an all-green baseline must not. The issue-handling
// + heartbeat plumbing mirrors cron-gh-pages-cert-state.ts verbatim and is not
// re-tested here.
//
// Plan: knowledge-base/project/plans/2026-06-02-fix-supabase-disk-io-recurrence-and-sentry-monitor-plan.md Phase 3.

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE the ES-module import below — sets NEXT_PHASE so the
// inngest client's startup-key check short-circuits. Mirrors
// cron-community-monitor.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronSupabaseDiskIo,
  evaluateDiskIoSignal,
  CACHE_HIT_FLOOR_PCT,
  DEDUP_TABLE_ROW_CEIL,
  SENTRY_MONITOR_SLUG,
  type DiskIoSignal,
} from "@/server/inngest/functions/cron-supabase-disk-io";

const baseline: DiskIoSignal = {
  cache_hit_pct: 100.0,
  dedup_table_rows: {
    processed_github_events: 65_240,
    processed_stripe_events: 1,
  },
  top_write_churn: [{ table: "messages", writes: 290 }],
  sampled_at: "2026-06-02T00:00:00Z",
};

describe("evaluateDiskIoSignal — verdict gate", () => {
  it("all-green baseline (cache full, dedup under ceil) does NOT trip", () => {
    const v = evaluateDiskIoSignal(baseline);
    expect(v.tripped).toBe(false);
    expect(v.reasons).toEqual([]);
  });

  it("cache hit below the floor trips with a read-pressure reason", () => {
    const v = evaluateDiskIoSignal({
      ...baseline,
      cache_hit_pct: CACHE_HIT_FLOOR_PCT - 1,
    });
    expect(v.tripped).toBe(true);
    expect(v.reasons.some((r) => /cache_hit/i.test(r))).toBe(true);
  });

  it("a dedup table above the row ceiling trips and names the table", () => {
    const v = evaluateDiskIoSignal({
      ...baseline,
      dedup_table_rows: {
        processed_github_events: DEDUP_TABLE_ROW_CEIL + 1,
        processed_stripe_events: 1,
      },
    });
    expect(v.tripped).toBe(true);
    expect(v.reasons.some((r) => /processed_github_events/.test(r))).toBe(true);
  });

  it("multiple breaches produce multiple independent reasons", () => {
    const v = evaluateDiskIoSignal({
      ...baseline,
      cache_hit_pct: 50,
      dedup_table_rows: { processed_github_events: DEDUP_TABLE_ROW_CEIL + 5 },
    });
    expect(v.tripped).toBe(true);
    expect(v.reasons.length).toBeGreaterThanOrEqual(2);
  });

  it("exactly-at-threshold values do NOT trip (strict comparison)", () => {
    const v = evaluateDiskIoSignal({
      ...baseline,
      cache_hit_pct: CACHE_HIT_FLOOR_PCT,
      dedup_table_rows: { processed_github_events: DEDUP_TABLE_ROW_CEIL },
    });
    expect(v.tripped).toBe(false);
  });

  it("tolerates a missing/partial signal without crashing or false-tripping", () => {
    // A null cache_hit_pct (no pg_stat_database rows) must not be treated as a
    // read regression, and absent dedup_table_rows must not throw.
    const v = evaluateDiskIoSignal({
      cache_hit_pct: null as unknown as number,
      dedup_table_rows: undefined as unknown as Record<string, number>,
      top_write_churn: [],
      sampled_at: "2026-06-02T00:00:00Z",
    });
    expect(v.tripped).toBe(false);
    expect(v.detail).toBeTruthy();
  });

  it("thresholds are calibrated with headroom over the 2026-06-02 baseline", () => {
    // Baseline: cache 100.000%, processed_github_events 65,240 rows. Floor must
    // sit below 100 (so a real regression is detectable) and the ceiling above
    // the observed outlier (so the healthy baseline is not a false positive).
    expect(CACHE_HIT_FLOOR_PCT).toBeGreaterThan(90);
    expect(CACHE_HIT_FLOOR_PCT).toBeLessThan(100);
    expect(DEDUP_TABLE_ROW_CEIL).toBeGreaterThan(65_240);
  });
});

describe("cronSupabaseDiskIo — registration shape", () => {
  it("loads without throwing and exposes the monitor slug", () => {
    expect(cronSupabaseDiskIo).toBeDefined();
    expect(SENTRY_MONITOR_SLUG).toBe("scheduled-supabase-disk-io");
  });
});
