import { describe, it, expect, vi, beforeEach } from "vitest";

// Chainable, awaitable supabase-builder mock: every method returns the builder,
// and the builder is a thenable resolving to `result` — so any chain length
// (.delete().eq().neq().lt()) is awaitable. Calls are captured per-method.
function makeBuilder(result: { error: unknown } = { error: null }) {
  const calls: Record<string, unknown[][]> = {
    upsert: [],
    update: [],
    delete: [],
    eq: [],
    neq: [],
    lt: [],
  };
  const builder: { _calls: Record<string, unknown[][]>; [k: string]: unknown } = {
    then: (resolve: (r: { error: unknown }) => unknown) => resolve(result),
    _calls: calls,
  };
  for (const m of ["upsert", "update", "delete", "eq", "neq", "lt"]) {
    builder[m] = vi.fn((...args: unknown[]) => {
      calls[m].push(args);
      return builder;
    });
  }
  return builder;
}

let builder = makeBuilder();
const fromMock = vi.fn(() => builder);

vi.mock("@/lib/supabase/service", () => ({
  getServiceClient: () => ({ from: fromMock }),
}));

const captureException = vi.fn();
vi.mock("@sentry/nextjs", () => ({
  captureException: (...args: unknown[]) => captureException(...args),
}));

import {
  upsertRoutineRunProgress,
  heartbeatRoutineRunProgress,
  finishRoutineRunProgress,
  HEARTBEAT_INTERVAL_MS,
  STUCK_THRESHOLD_MS,
  ORPHAN_IGNORE_MS,
} from "@/server/inngest/routine-run-progress";

beforeEach(() => {
  builder = makeBuilder();
  fromMock.mockClear();
  fromMock.mockImplementation(() => builder);
  captureException.mockClear();
});

describe("routine-run-progress live-state helper", () => {
  it("threshold invariant is contiguous: interval < stuck < orphan-ignore (DI-P1-B)", () => {
    expect(HEARTBEAT_INTERVAL_MS).toBeLessThan(STUCK_THRESHOLD_MS);
    expect(STUCK_THRESHOLD_MS).toBeLessThan(ORPHAN_IGNORE_MS);
  });

  describe("upsertRoutineRunProgress", () => {
    it("upserts on run_id and OMITS started_at (preserved across replay — DI-P2-D)", async () => {
      await upsertRoutineRunProgress("cron-bug-fixer", "run-1", 1);
      const [payload, opts] = builder._calls.upsert[0] as [
        Record<string, unknown>,
        Record<string, unknown>,
      ];
      expect(opts).toEqual({ onConflict: "run_id" });
      expect(payload).toMatchObject({
        routine_id: "cron-bug-fixer",
        run_id: "run-1",
        attempt: 1,
      });
      expect(payload).toHaveProperty("last_heartbeat_at");
      // started_at must NOT be in the payload — omission preserves it on conflict.
      expect(payload).not.toHaveProperty("started_at");
    });

    it("reaps stale orphans with a staleness GUARD, not an unconditional run_id<>$2 (DI-P1-A)", async () => {
      await upsertRoutineRunProgress("cron-bug-fixer", "run-2", 2);
      // delete-stale scopes to same routine, excludes self, AND requires staleness.
      expect(builder._calls.eq).toContainEqual(["routine_id", "cron-bug-fixer"]);
      expect(builder._calls.neq).toContainEqual(["run_id", "run-2"]);
      expect(builder._calls.lt.length).toBe(1);
      expect((builder._calls.lt[0] as string[])[0]).toBe("last_heartbeat_at");
    });

    it("is fail-soft: a DB error mirrors to Sentry and does NOT throw", async () => {
      builder = makeBuilder({ error: new Error("db down") });
      fromMock.mockImplementation(() => builder);
      await expect(
        upsertRoutineRunProgress("cron-bug-fixer", "run-3", 1),
      ).resolves.toBeUndefined();
      expect(captureException).toHaveBeenCalled();
    });
  });

  describe("heartbeatRoutineRunProgress", () => {
    it("is UPDATE-only keyed on run_id (never an upsert — DI-P2-E, no phantom resurrection)", async () => {
      await heartbeatRoutineRunProgress("run-4");
      expect(builder._calls.update.length).toBe(1);
      expect((builder._calls.update[0] as Record<string, unknown>[])[0]).toHaveProperty(
        "last_heartbeat_at",
      );
      expect(builder._calls.upsert.length).toBe(0);
      expect(builder._calls.eq).toContainEqual(["run_id", "run-4"]);
    });

    it("is fail-soft on DB error", async () => {
      builder = makeBuilder({ error: new Error("db down") });
      fromMock.mockImplementation(() => builder);
      await expect(heartbeatRoutineRunProgress("run-5")).resolves.toBeUndefined();
      expect(captureException).toHaveBeenCalled();
    });
  });

  describe("finishRoutineRunProgress", () => {
    it("deletes the live row by run_id", async () => {
      await finishRoutineRunProgress("run-6");
      expect(builder._calls.delete.length).toBe(1);
      expect(builder._calls.eq).toContainEqual(["run_id", "run-6"]);
    });

    it("is fail-soft on DB error (delete error not misattributed to the terminal write)", async () => {
      builder = makeBuilder({ error: new Error("db down") });
      fromMock.mockImplementation(() => builder);
      await expect(finishRoutineRunProgress("run-7")).resolves.toBeUndefined();
      expect(captureException).toHaveBeenCalled();
    });
  });
});
