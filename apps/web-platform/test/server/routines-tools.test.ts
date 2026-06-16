import { beforeEach, describe, expect, it, vi } from "vitest";

const { mockRunRoutine, mockListRoutines, mockListRuns } = vi.hoisted(() => ({
  mockRunRoutine: vi.fn(),
  mockListRoutines: vi.fn(),
  mockListRuns: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({ getServiceClient: () => ({}) }));
vi.mock("@/server/routines/run-routine", () => ({ runRoutine: mockRunRoutine }));
vi.mock("@/server/routines/list-routines", () => ({
  listRoutinesWithLastRun: mockListRoutines,
  listRecentRuns: mockListRuns,
}));

import { buildRoutineTools } from "@/server/routines-tools";
import { getToolTier, buildGateMessage } from "@/server/tool-tiers";

type ToolLike = { name: string; handler: (a: unknown) => Promise<{ content: Array<{ text: string }>; isError?: boolean }> };

function getTool(name: string): ToolLike {
  const { tools } = buildRoutineTools({ userId: "op-1" });
  const t = (tools as unknown as ToolLike[]).find((x) => x.name === name);
  if (!t) throw new Error(`tool ${name} not found`);
  return t;
}

beforeEach(() => {
  mockRunRoutine.mockReset();
  mockListRoutines.mockReset();
  mockListRuns.mockReset();
});

describe("routine tool tiers", () => {
  it("reads are auto-approve, run is gated", () => {
    expect(getToolTier("mcp__soleur_platform__routines_list")).toBe("auto-approve");
    expect(getToolTier("mcp__soleur_platform__routine_runs_list")).toBe("auto-approve");
    expect(getToolTier("mcp__soleur_platform__routine_run")).toBe("gated");
  });

  it("buildGateMessage names the routine for routine_run", () => {
    const msg = buildGateMessage("mcp__soleur_platform__routine_run", { fnId: "cron-content-publisher" });
    expect(msg).toContain("cron-content-publisher");
  });
});

describe("buildRoutineTools", () => {
  it("registers the three FQ tool names", () => {
    const { toolNames } = buildRoutineTools({ userId: "op-1" });
    expect(toolNames).toEqual([
      "mcp__soleur_platform__routines_list",
      "mcp__soleur_platform__routine_runs_list",
      "mcp__soleur_platform__routine_run",
    ]);
  });

  it("routine_run dispatches as agent with confirmed=true and operator as delegating_principal", async () => {
    mockRunRoutine.mockResolvedValue({ ok: true, event: "cron/daily-triage.manual-trigger" });
    const tool = getTool("routine_run");
    const res = await tool.handler({ fnId: "cron-daily-triage" });
    expect(mockRunRoutine).toHaveBeenCalledWith(
      expect.objectContaining({
        fnId: "cron-daily-triage",
        actorClass: "agent",
        confirmed: true,
        delegatingPrincipal: "op-1",
      }),
    );
    expect(res.isError).toBeUndefined();
    expect(res.content[0].text).toContain("dispatched");
  });

  it("routine_run surfaces unknown_routine as an error", async () => {
    mockRunRoutine.mockResolvedValue({ ok: false, code: "unknown_routine", status: 400 });
    const tool = getTool("routine_run");
    const res = await tool.handler({ fnId: "cfo-on-payment-failed" });
    expect(res.isError).toBe(true);
    expect(res.content[0].text).toContain("unknown_routine");
  });

  it("routines_list returns the shared list", async () => {
    mockListRoutines.mockResolvedValue([{ fnId: "cron-daily-triage" }]);
    const tool = getTool("routines_list");
    const res = await tool.handler({});
    expect(mockListRoutines).toHaveBeenCalledTimes(1);
    expect(res.content[0].text).toContain("cron-daily-triage");
  });

  // #5412 — agent-user filter parity. The tool forwards validated filters to
  // the shared listRecentRuns (same surface the dashboard route exposes).
  it("routine_runs_list forwards validated filters to listRecentRuns", async () => {
    mockListRuns.mockResolvedValue({ runs: [], nextCursor: null });
    const tool = getTool("routine_runs_list");
    await tool.handler({
      routineId: "cron-daily-triage",
      status: "failed",
      triggerSource: "agent",
      since: "2026-06-01T00:00:00.000Z",
    });
    expect(mockListRuns).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        routineId: "cron-daily-triage",
        status: "failed",
        triggerSource: "agent",
        since: "2026-06-01T00:00:00.000Z",
      }),
    );
  });

  it("routine_runs_list drops a routineId outside the cron manifest", async () => {
    mockListRuns.mockResolvedValue({ runs: [], nextCursor: null });
    const tool = getTool("routine_runs_list");
    await tool.handler({ routineId: "cron-bogus-not-real" });
    expect(mockListRuns).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ routineId: null }),
    );
  });
});
