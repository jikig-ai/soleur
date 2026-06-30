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

import { beforeEach, describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE the ES-module import below — sets NEXT_PHASE so the
// inngest client's startup-key check short-circuits. Mirrors
// cron-community-monitor.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

// Service-role RPC mock: the handler reads the signal via
// `service.rpc("disk_io_pressure_signal")`. SIGNAL/SIGNAL_ERROR are set per test.
let SIGNAL: unknown = null;
let SIGNAL_ERROR: { message: string } | null = null;
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    rpc: async () => ({
      data: SIGNAL_ERROR ? null : SIGNAL,
      error: SIGNAL_ERROR,
    }),
  }),
}));

// Spies are referenced inside the vi.mock factories, which vitest hoists ABOVE
// the static cron-module import below — so they must be created via vi.hoisted
// (a plain `const` would be in the TDZ when the factory runs at import time).
const { reportSilentFallbackSpy, postSentryHeartbeatSpy } = vi.hoisted(() => ({
  // Observability spy — the WAL-concentration capture goes through reportSilentFallback.
  reportSilentFallbackSpy: vi.fn(),
  // _cron-shared Sentry heartbeat stub (no live IO).
  postSentryHeartbeatSpy: vi.fn(async () => {}),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: vi.fn(),
}));

// _cron-shared: stub the GitHub-token mint + Sentry heartbeat (no live IO), keep
// REPO_OWNER/REPO_NAME real so the issue-handling step's request shape is intact.
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("@/server/inngest/functions/_cron-shared")>();
  return {
    ...actual,
    mintInstallationToken: vi.fn(async () => "gh-token-test"),
    postSentryHeartbeat: postSentryHeartbeatSpy,
  };
});

// Octokit: the issue-handling step searches for an existing [disk-io] issue.
// Return zero items so a healthy (non-tripped) signal no-ops there, isolating
// the WAL-concentration emit under test.
vi.mock("@octokit/core", () => ({
  Octokit: class {
    request = vi.fn(async () => ({ data: { items: [] } }));
  },
}));

import {
  cronSupabaseDiskIo,
  cronSupabaseDiskIoHandler,
  evaluateDiskIoSignal,
  evaluateWalConcentration,
  CACHE_HIT_FLOOR_PCT,
  DEDUP_TABLE_ROW_CEIL,
  WAL_CONCENTRATION_PCT_CEIL,
  SENTRY_MONITOR_SLUG,
  type DiskIoSignal,
  type WalStatement,
} from "@/server/inngest/functions/cron-supabase-disk-io";

// Eager mock `step`: runs each step.run callback inline (no Inngest runtime).
function makeStep() {
  const calls: { name: string }[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      const result = await cb();
      calls.push({ name });
      return result;
    },
  };
}
const logger = { warn: vi.fn(), info: vi.fn(), error: vi.fn() };

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

// ── WAL-concentration lens (#5736) ──────────────────────────────────────────
const TOP_WAL: WalStatement[] = [
  {
    query: "INSERT INTO processed_github_events (delivery_id) VALUES ($1)",
    calls: 1_000_000,
    wal_bytes: 6_300_000_000,
    pct_of_wal: 63,
  },
];

describe("evaluateWalConcentration — pure WAL-concentration verdict", () => {
  it("a statement above the ceiling concentrates and names the top statement", () => {
    const v = evaluateWalConcentration({
      cache_hit_pct: 100,
      dedup_table_rows: {},
      top_write_churn: [],
      top_wal_statements: TOP_WAL,
      max_wal_pct: 63,
      sampled_at: "2026-06-30T00:00:00Z",
    });
    expect(v.concentrated).toBe(true);
    expect(v.maxPct).toBe(63);
    expect(v.topStatement?.query).toMatch(/processed_github_events/);
    expect(v.detail).toMatch(/dominates/);
  });

  it("max_wal_pct at the ceiling does NOT concentrate (strict >)", () => {
    const v = evaluateWalConcentration({
      cache_hit_pct: 100,
      dedup_table_rows: {},
      top_write_churn: [],
      top_wal_statements: null,
      max_wal_pct: WAL_CONCENTRATION_PCT_CEIL,
      sampled_at: "2026-06-30T00:00:00Z",
    });
    expect(v.concentrated).toBe(false);
  });

  it("a healthy spread (max_wal_pct under the ceiling) does NOT concentrate", () => {
    const v = evaluateWalConcentration({
      cache_hit_pct: 100,
      dedup_table_rows: {},
      top_write_churn: [],
      top_wal_statements: null,
      max_wal_pct: 12,
      sampled_at: "2026-06-30T00:00:00Z",
    });
    expect(v.concentrated).toBe(false);
  });

  it("a missing/undefined max_wal_pct (pre-114 RPC) is NOT concentration and does not throw", () => {
    const v = evaluateWalConcentration({
      cache_hit_pct: 100,
      dedup_table_rows: {},
      top_write_churn: [],
      sampled_at: "2026-06-30T00:00:00Z",
    });
    expect(v.concentrated).toBe(false);
    expect(v.maxPct).toBeNull();
    expect(v.detail).toBeTruthy();
  });
});

// Drives the handler with an eager mock step + mocked service RPC. A WAL-
// concentration signal must fire the reportSilentFallback capture
// (op=wal-concentration); a healthy one must not — and the budget heartbeat is
// untouched either way (WAL concentration is a write-cost signal, not a breach).
function healthySignal(
  maxWalPct: number | null | undefined,
  top: WalStatement[] | null = null,
): DiskIoSignal {
  return {
    cache_hit_pct: 100, // no read regression
    dedup_table_rows: { processed_github_events: 100, processed_stripe_events: 1 }, // under ceil
    top_write_churn: [],
    top_wal_statements: top,
    max_wal_pct: maxWalPct,
    sampled_at: "2026-06-30T00:00:00Z",
  };
}

describe("cronSupabaseDiskIoHandler — WAL-concentration emit", () => {
  beforeEach(() => {
    SIGNAL = null;
    SIGNAL_ERROR = null;
    reportSilentFallbackSpy.mockReset();
    postSentryHeartbeatSpy.mockClear();
    logger.warn.mockClear();
  });

  it("fires the op=wal-concentration capture when max_wal_pct exceeds the ceiling", async () => {
    SIGNAL = healthySignal(WAL_CONCENTRATION_PCT_CEIL + 23, TOP_WAL); // 63%, the #5736 value
    const result = await cronSupabaseDiskIoHandler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "cron-supabase-disk-io",
        op: "wal-concentration",
        extra: expect.objectContaining({ maxWalPct: WAL_CONCENTRATION_PCT_CEIL + 23 }),
      }),
    );
    // WAL concentration is NOT a budget breach — the healthy verdict stands.
    expect(result.tripped).toBe(false);
    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
  });

  it("does NOT fire when max_wal_pct is at or below the ceiling", async () => {
    SIGNAL = healthySignal(WAL_CONCENTRATION_PCT_CEIL); // exactly at ceil → no fire
    const result = await cronSupabaseDiskIoHandler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
    expect(result.tripped).toBe(false);
    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
  });

  it("does NOT fire (and does not throw) when the RPC omits max_wal_pct (pre-114 RPC)", async () => {
    SIGNAL = healthySignal(undefined);
    await cronSupabaseDiskIoHandler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("does NOT fire on a failed signal read (no signal to evaluate)", async () => {
    SIGNAL_ERROR = { message: "rpc unavailable" };
    const result = await cronSupabaseDiskIoHandler({ step: makeStep(), logger });

    // The read-failure path reports op=read-signal (fail-loud), never wal-concentration.
    expect(reportSilentFallbackSpy).not.toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "wal-concentration" }),
    );
    expect(result.tripped).toBe(true); // failed read is fail-loud
  });
});
