import { describe, expect, it } from "vitest";
import { EXPECTED_CRON_FUNCTIONS } from "@/server/inngest/cron-manifest";
import {
  listRecentRuns,
  listRoutinesWithLastRun,
} from "@/server/routines/list-routines";

function makeClient(opts: { latest?: unknown[]; runs?: unknown[] }) {
  return {
    from(table: string) {
      return {
        select() {
          if (table === "routine_runs_latest") {
            return Promise.resolve({ data: opts.latest ?? [], error: null });
          }
          const chain: Record<string, unknown> = {
            order() {
              return chain;
            },
            limit() {
              return Promise.resolve({ data: opts.runs ?? [], error: null });
            },
            lt() {
              return {
                limit: () =>
                  Promise.resolve({ data: opts.runs ?? [], error: null }),
              };
            },
          };
          return chain;
        },
      };
    },
  } as never;
}

describe("listRoutinesWithLastRun", () => {
  it("returns one item per cron with metadata + merged last run", async () => {
    const latest = [
      {
        routine_id: "cron-daily-triage",
        status: "completed",
        trigger_source: "scheduled",
        started_at: "2026-06-15T04:00:00Z",
        ended_at: "2026-06-15T04:00:08Z",
        duration_ms: 8000,
        error_summary: null,
      },
    ];
    const items = await listRoutinesWithLastRun(makeClient({ latest }));
    expect(items).toHaveLength(EXPECTED_CRON_FUNCTIONS.length);
    const triage = items.find((i) => i.fnId === "cron-daily-triage")!;
    expect(triage.domain).toBeTruthy();
    expect(triage.ownerRole).toBeTruthy();
    expect(triage.lastRun?.status).toBe("completed");
    const neverRun = items.find((i) => i.fnId === "cron-legal-audit")!;
    expect(neverRun.lastRun).toBeNull();
  });
});

describe("listRecentRuns", () => {
  it("returns a page with nextCursor=null when fewer than limit+1 rows", async () => {
    const runs = [
      { id: "r1", routine_id: "cron-daily-triage", status: "completed", trigger_source: "scheduled", started_at: "2026-06-15T04:00:00Z", ended_at: null, duration_ms: 10, error_summary: null },
    ];
    const page = await listRecentRuns(makeClient({ runs }), { limit: 50 });
    expect(page.runs).toHaveLength(1);
    expect(page.nextCursor).toBeNull();
  });

  it("sets nextCursor and trims to limit when more rows exist", async () => {
    const runs = Array.from({ length: 3 }, (_, i) => ({
      id: `r${i}`,
      routine_id: "cron-daily-triage",
      status: "completed",
      trigger_source: "scheduled",
      started_at: `2026-06-15T0${i}:00:00Z`,
      ended_at: null,
      duration_ms: 10,
      error_summary: null,
    }));
    const page = await listRecentRuns(makeClient({ runs }), { limit: 2 });
    expect(page.runs).toHaveLength(2);
    expect(page.nextCursor).toBe("2026-06-15T01:00:00Z");
  });
});
