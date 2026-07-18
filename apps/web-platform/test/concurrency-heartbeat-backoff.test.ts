import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import {
  SLOT_HEARTBEAT_INTERVAL_MS,
  SLOT_STALENESS_THRESHOLD_SECONDS,
} from "../server/concurrency";
import {
  HEARTBEAT_INTERVAL_MS,
  STUCK_THRESHOLD_MS,
  ORPHAN_IGNORE_MS,
} from "../server/inngest/routine-run-progress";
import {
  WORKTREE_LEASE_HEARTBEAT_MS,
  LEASE_LIVENESS_WINDOW_MS,
} from "../server/worktree-write-lease";

// Disk-IO write-reduction (2026-07-18): the three periodic heartbeat writers
// (concurrency slot, routine-run-progress, worktree lease) were backed off to
// halve their steady-state WAL, and every matching staleness/reaper threshold
// was raised in lockstep so the missed-beat tolerance is UNCHANGED. This test
// pins the invariant `threshold >= 3 × interval` on the LIVE symbols (AC7) — a
// future edit that lengthens an interval without raising its threshold (or
// vice-versa) would false-reap a live session, the single-user incident this
// PR's coupling exists to prevent.

describe("heartbeat/threshold invariant (AC7 — live symbols)", () => {
  it("routine-run-progress: STUCK_THRESHOLD_MS >= 3× HEARTBEAT_INTERVAL_MS and < ORPHAN_IGNORE_MS", () => {
    expect(HEARTBEAT_INTERVAL_MS).toBe(60_000);
    expect(STUCK_THRESHOLD_MS).toBe(180_000);
    expect(STUCK_THRESHOLD_MS).toBeGreaterThanOrEqual(3 * HEARTBEAT_INTERVAL_MS);
    expect(STUCK_THRESHOLD_MS).toBeLessThan(ORPHAN_IGNORE_MS);
  });

  it("worktree-lease: LEASE_LIVENESS_WINDOW_MS >= 3× WORKTREE_LEASE_HEARTBEAT_MS", () => {
    expect(WORKTREE_LEASE_HEARTBEAT_MS).toBe(50_000);
    expect(LEASE_LIVENESS_WINDOW_MS).toBe(240_000);
    expect(LEASE_LIVENESS_WINDOW_MS).toBeGreaterThanOrEqual(
      3 * WORKTREE_LEASE_HEARTBEAT_MS,
    );
  });

  it("concurrency-slot: staleness window == 4× SLOT_HEARTBEAT_INTERVAL_MS (exact pre-change tolerance)", () => {
    expect(SLOT_HEARTBEAT_INTERVAL_MS).toBe(60_000);
    expect(SLOT_STALENESS_THRESHOLD_SECONDS).toBe(240);
    const stalenessMs = SLOT_STALENESS_THRESHOLD_SECONDS * 1_000;
    expect(stalenessMs).toBe(4 * SLOT_HEARTBEAT_INTERVAL_MS);
    expect(stalenessMs).toBeGreaterThanOrEqual(3 * SLOT_HEARTBEAT_INTERVAL_MS);
  });
});

// AC8 — grep-based drift-guard (NOT an enumerated allowlist; the enumerated
// approach is what let sites slip past the first pass). Anchored on the
// syntactic liveness-literal shape keyed on last_heartbeat_at/heartbeat_at, so a
// residual 120s window anywhere in the coupled TS + SQL-133 surface reds this.
describe("120s→240s liveness-literal drift-guard (AC8)", () => {
  const read = (rel: string) =>
    readFileSync(path.join(__dirname, "..", rel), "utf8");

  const WS = read("server/ws-handler.ts");
  const AR = read("server/agent-runner.ts");
  const MIG = read("supabase/migrations/133_heartbeat_threshold_backoff.sql");

  it("no residual 120_000 ms literal in the coupled TS files", () => {
    // Any `120_000` in ws-handler/agent-runner would be a slot-liveness window
    // left un-widened. Comments were swept to 240s too, so 0 matches total.
    expect(WS.match(/120_000/g) ?? []).toHaveLength(0);
    expect(AR.match(/120_000/g) ?? []).toHaveLength(0);
  });

  it("no residual `interval '120 seconds'` in migration 133 (up)", () => {
    expect(MIG.match(/interval '120 seconds'/g) ?? []).toHaveLength(0);
  });

  it("migration 133 raises exactly 3 SQL interval sites to 240s + finder default 240", () => {
    // acquire_conversation_slot lazy sweep + user_concurrency_slots_sweep
    // pg_cron body + acquire_worktree_lease takeover = 3 interval literals;
    // find_stuck_active_conversations moves via its `default 240` instead.
    expect(MIG.match(/interval '240 seconds'/g) ?? []).toHaveLength(3);
    expect(MIG).toMatch(/p_threshold_seconds\s+integer\s+default\s+240/);
  });

  it("the two slot-threshold consumers import the shared symbol (structural de-dup)", () => {
    expect(WS).toMatch(/\bSLOT_STALENESS_THRESHOLD_SECONDS\b/);
    expect(AR).toMatch(/\bSLOT_STALENESS_THRESHOLD_SECONDS\b/);
    // No re-declared local threshold literal survives.
    expect(WS).not.toMatch(/STALE_HEARTBEAT_THRESHOLD_SECONDS\s*=\s*120/);
    expect(AR).not.toMatch(/STUCK_ACTIVE_THRESHOLD_SECONDS\s*=\s*120/);
  });
});
