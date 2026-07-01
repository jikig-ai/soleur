import { describe, it, expect } from "vitest";
import { listLiveRuns } from "@/server/routines/list-routines";
import {
  STUCK_THRESHOLD_MS,
  ORPHAN_IGNORE_MS,
} from "@/server/inngest/routine-run-progress";

const NOW = 1_800_000_000_000; // fixed reference instant

function iso(msAgo: number): string {
  return new Date(NOW - msAgo).toISOString();
}

function mockSupabase(rows: unknown[]) {
  return {
    from: () => ({
      select: () => Promise.resolve({ data: rows, error: null }),
    }),
  } as never;
}

describe("listLiveRuns — reader-computed live status", () => {
  it("fresh heartbeat => running", async () => {
    const out = await listLiveRuns(
      mockSupabase([
        { id: "a", routine_id: "cron-bug-fixer", run_id: "r1", attempt: 1, started_at: iso(10_000), last_heartbeat_at: iso(1_000) },
      ]),
      NOW,
    );
    expect(out).toHaveLength(1);
    expect(out[0].status).toBe("running");
    expect(out[0].resumed).toBe(false);
  });

  it("stale heartbeat (> stuck threshold, < orphan bound) => stuck", async () => {
    const out = await listLiveRuns(
      mockSupabase([
        { id: "b", routine_id: "cron-ux-audit", run_id: "r2", attempt: 1, started_at: iso(200_000), last_heartbeat_at: iso(STUCK_THRESHOLD_MS + 5_000) },
      ]),
      NOW,
    );
    expect(out[0].status).toBe("stuck");
  });

  it("heartbeat older than the orphan bound => ignored (dropped, not stuck-forever)", async () => {
    const out = await listLiveRuns(
      mockSupabase([
        { id: "c", routine_id: "cron-seo-aeo-audit", run_id: "r3", attempt: 1, started_at: iso(ORPHAN_IGNORE_MS + 60_000), last_heartbeat_at: iso(ORPHAN_IGNORE_MS + 1_000) },
      ]),
      NOW,
    );
    expect(out).toHaveLength(0);
  });

  it("DI-P1-B: a healthy long run (OLD started_at, FRESH heartbeat) is running, NOT dropped/stuck", async () => {
    const out = await listLiveRuns(
      mockSupabase([
        // started ~50 min ago (older than ORPHAN_IGNORE_MS) but heartbeated 5s ago
        { id: "d", routine_id: "cron-bug-fixer", run_id: "r4", attempt: 1, started_at: iso(ORPHAN_IGNORE_MS + 600_000), last_heartbeat_at: iso(5_000) },
      ]),
      NOW,
    );
    expect(out).toHaveLength(1);
    expect(out[0].status).toBe("running");
  });

  it("attempt > 1 => resumed overlay (status stays running/stuck)", async () => {
    const out = await listLiveRuns(
      mockSupabase([
        { id: "e", routine_id: "cron-bug-fixer", run_id: "r5", attempt: 2, started_at: iso(30_000), last_heartbeat_at: iso(2_000) },
      ]),
      NOW,
    );
    expect(out[0].resumed).toBe(true);
    expect(out[0].status).toBe("running");
  });

  it("returns newest-first by started_at", async () => {
    const out = await listLiveRuns(
      mockSupabase([
        { id: "old", routine_id: "cron-a", run_id: "ro", attempt: 1, started_at: iso(90_000), last_heartbeat_at: iso(1_000) },
        { id: "new", routine_id: "cron-b", run_id: "rn", attempt: 1, started_at: iso(10_000), last_heartbeat_at: iso(1_000) },
      ]),
      NOW,
    );
    expect(out.map((r) => r.id)).toEqual(["new", "old"]);
  });
});
