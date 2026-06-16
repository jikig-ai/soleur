import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  render,
  screen,
  fireEvent,
  waitFor,
  cleanup,
} from "@testing-library/react";
import { RoutinesSurface } from "@/components/routines/routines-surface";

// Stub the heavy chat surface (WS/agent stack) — assert it mounts with the
// routine-authoring mode flag rather than booting the real Concierge. #5402.
const chatSurfaceProps = vi.hoisted(() => ({ last: null as unknown }));
vi.mock("@/components/chat/chat-surface", () => ({
  ChatSurface: (props: Record<string, unknown>) => {
    chatSurfaceProps.last = props;
    return <div data-testid="chat-surface-stub" />;
  },
}));

// Records every GET .../runs request URL so tests can assert filter params
// (routineId / status / triggerSource / since) flow into the query string.
const runsRequests = vi.hoisted(() => ({ urls: [] as string[] }));

const ALLOWED = {
  fnId: "cron-daily-triage",
  domain: "Operations",
  ownerRole: "COO",
  scheduleLabel: "Daily 04:00 UTC",
  manualTrigger: "allowed",
  lastRun: {
    status: "completed",
    trigger_source: "scheduled",
    started_at: new Date(Date.now() - 3600_000).toISOString(),
    ended_at: new Date().toISOString(),
    duration_ms: 8000,
    error_summary: null,
  },
};
const PROTECTED = {
  fnId: "cron-content-publisher",
  domain: "Marketing",
  ownerRole: "CMO",
  scheduleLabel: "Daily 14:00 UTC",
  manualTrigger: "confirm",
  lastRun: null,
};

function mockFetch(handlers: {
  routines?: unknown;
  runStatus?: number;
  runs?: { runs: unknown[]; nextCursor: string | null };
}) {
  return vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input.toString();
    // Run-now is POST .../run; runs history is GET .../runs (run is a substring
    // of runs, so disambiguate by method).
    if (url.includes("/api/dashboard/routines/run") && init?.method === "POST") {
      const status = handlers.runStatus ?? 202;
      return {
        ok: status < 400,
        status,
        json: async () => ({ dispatched: "evt", error: "confirmation_required" }),
      } as Response;
    }
    if (url.includes("/api/dashboard/routines/runs")) {
      runsRequests.urls.push(url);
      return {
        ok: true,
        status: 200,
        json: async () => handlers.runs ?? { runs: [], nextCursor: null },
      } as Response;
    }
    // /api/dashboard/routines
    return {
      ok: true,
      status: 200,
      json: async () => ({ routines: handlers.routines ?? [ALLOWED, PROTECTED] }),
    } as Response;
  });
}

beforeEach(() => {
  runsRequests.urls = [];
  vi.stubGlobal("fetch", mockFetch({}));
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("RoutinesSurface", () => {
  it("renders routines grouped by domain with last-run state", async () => {
    render(<RoutinesSurface />);
    await waitFor(() => expect(screen.getByText("2 routines")).toBeTruthy());
    // Domain text appears in both the section heading and the row badge.
    expect(screen.getAllByText("Operations").length).toBeGreaterThanOrEqual(1);
    expect(screen.getAllByText("Marketing").length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText("Daily triage")).toBeTruthy();
    // protected routine shows the protected marker
    expect(screen.getByText("⚠ protected")).toBeTruthy();
  });

  it("Run-now on an allowed routine dispatches and shows optimistic Running", async () => {
    render(<RoutinesSurface />);
    await waitFor(() => screen.getByTestId("run-now-cron-daily-triage"));
    fireEvent.click(screen.getByTestId("run-now-cron-daily-triage"));
    await waitFor(() => expect(screen.getByText("running")).toBeTruthy());
  });

  it("Run-now on a protected routine opens the confirm modal, then confirms", async () => {
    vi.stubGlobal("fetch", mockFetch({ runStatus: 409 }));
    render(<RoutinesSurface />);
    await waitFor(() => screen.getByTestId("run-now-cron-content-publisher"));
    fireEvent.click(screen.getByTestId("run-now-cron-content-publisher"));
    await waitFor(() =>
      expect(screen.getByRole("dialog")).toBeTruthy(),
    );
    expect(screen.getByText(/Run protected routine now/)).toBeTruthy();
    // now confirm succeeds
    vi.stubGlobal("fetch", mockFetch({ runStatus: 202 }));
    fireEvent.click(screen.getByTestId("confirm-run"));
    await waitFor(() =>
      expect(screen.queryByRole("dialog")).toBeNull(),
    );
  });

  it("Recent Runs shows empty state when no runs", async () => {
    render(<RoutinesSurface />);
    fireEvent.click(screen.getByRole("tab", { name: "Recent Runs" }));
    await waitFor(() =>
      expect(screen.getByText(/No runs yet/)).toBeTruthy(),
    );
  });

  it("Recent Runs row click opens the detail panel (error_summary, run_id, actor as text, no UUID)", async () => {
    const failed = {
      id: "r1",
      run_id: "01J-RUN-ID",
      routine_id: "cron-legal-audit",
      status: "failed",
      trigger_source: "scheduled",
      actor_class: "system",
      started_at: new Date().toISOString(),
      ended_at: new Date().toISOString(),
      duration_ms: 1200,
      error_summary: "boom: upstream 503",
    };
    vi.stubGlobal(
      "fetch",
      mockFetch({ runs: { runs: [failed], nextCursor: null } }),
    );
    render(<RoutinesSurface />);
    fireEvent.click(screen.getByRole("tab", { name: "Recent Runs" }));
    await waitFor(() => screen.getByTestId("run-row-r1"));
    fireEvent.click(screen.getByTestId("run-row-r1"));
    const panel = await screen.findByTestId("run-detail-panel");
    expect(panel.textContent).toContain("boom: upstream 503");
    expect(panel.textContent).toContain("01J-RUN-ID");
    // actor_class surfaced as human text (system → "System"), never "(you)".
    expect(panel.textContent).toContain("System");
    expect(panel.textContent).not.toContain("(you)");
  });

  it("Recent Runs detail panel opens for a NON-failed row too (one detail path)", async () => {
    const ok = {
      id: "r9",
      run_id: "01J-OK",
      routine_id: "cron-daily-triage",
      status: "completed",
      trigger_source: "manual",
      actor_class: "human",
      started_at: new Date().toISOString(),
      ended_at: new Date().toISOString(),
      duration_ms: 900,
      error_summary: null,
    };
    vi.stubGlobal(
      "fetch",
      mockFetch({ runs: { runs: [ok], nextCursor: null } }),
    );
    render(<RoutinesSurface />);
    fireEvent.click(screen.getByRole("tab", { name: "Recent Runs" }));
    await waitFor(() => screen.getByTestId("run-row-r9"));
    fireEvent.click(screen.getByTestId("run-row-r9"));
    const panel = await screen.findByTestId("run-detail-panel");
    expect(panel.textContent).toContain("01J-OK");
  });

  it("Recent Runs status filter triggers a scoped refetch", async () => {
    render(<RoutinesSurface />);
    fireEvent.click(screen.getByRole("tab", { name: "Recent Runs" }));
    await waitFor(() => expect(runsRequests.urls.length).toBeGreaterThan(0));
    runsRequests.urls = [];
    fireEvent.click(screen.getByTestId("runs-filter-status-failed"));
    await waitFor(() =>
      expect(runsRequests.urls.some((u) => u.includes("status=failed"))).toBe(
        true,
      ),
    );
  });

  it("Recent Runs date-range preset wires a since= query param", async () => {
    render(<RoutinesSurface />);
    fireEvent.click(screen.getByRole("tab", { name: "Recent Runs" }));
    await waitFor(() => expect(runsRequests.urls.length).toBeGreaterThan(0));
    runsRequests.urls = [];
    fireEvent.click(screen.getByTestId("runs-filter-range-7d"));
    await waitFor(() =>
      expect(runsRequests.urls.some((u) => u.includes("since="))).toBe(true),
    );
  });

  it("Recent Runs surfaces an error state (not an empty table) on a failed fetch", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = typeof input === "string" ? input : input.toString();
        if (url.includes("/api/dashboard/routines/runs")) {
          return { ok: false, status: 502, json: async () => ({}) } as Response;
        }
        return {
          ok: true,
          status: 200,
          json: async () => ({ routines: [] }),
        } as Response;
      }),
    );
    render(<RoutinesSurface />);
    fireEvent.click(screen.getByRole("tab", { name: "Recent Runs" }));
    await waitFor(() =>
      expect(screen.getByText(/Failed to load runs/)).toBeTruthy(),
    );
    expect(screen.queryByText(/No runs yet/)).toBeNull();
  });

  // #5412 — tab renamed to "Draft a routine with Concierge" (no ✨, no "new").
  it("shows the Concierge draft tab with the renamed label (no sparkles / new badge)", async () => {
    render(<RoutinesSurface />);
    const draftTab = screen.getByRole("tab", {
      name: /Draft a routine with Concierge/,
    });
    expect(draftTab).toBeTruthy();
    expect(draftTab.textContent).not.toContain("✨");
    expect(screen.queryByText("new")).toBeNull();
    expect(screen.queryByText("v2")).toBeNull();
  });

  // #5412 — clicking a routine row opens a slide-over drawer (no route change)
  // with the routine's metadata + a log scoped to that routine (routineId param).
  it("clicking a routine opens a drawer with metadata + a scoped run log", async () => {
    const scoped = {
      id: "d1",
      run_id: "01J-DRAWER",
      routine_id: "cron-daily-triage",
      status: "completed",
      trigger_source: "scheduled",
      actor_class: "system",
      started_at: new Date().toISOString(),
      ended_at: new Date().toISOString(),
      duration_ms: 500,
      error_summary: null,
    };
    vi.stubGlobal(
      "fetch",
      mockFetch({ runs: { runs: [scoped], nextCursor: null } }),
    );
    render(<RoutinesSurface />);
    await waitFor(() => screen.getByTestId("routine-open-cron-daily-triage"));
    runsRequests.urls = [];
    fireEvent.click(screen.getByTestId("routine-open-cron-daily-triage"));
    const drawer = await screen.findByTestId("routine-detail-drawer");
    // Metadata shows the schedule + owner.
    expect(drawer.textContent).toContain("Daily 04:00 UTC");
    expect(drawer.textContent).toContain("COO");
    // The scoped log fetch is filtered to this routine.
    await waitFor(() =>
      expect(
        runsRequests.urls.some((u) =>
          u.includes("routineId=cron-daily-triage"),
        ),
      ).toBe(true),
    );
    // The drawer's scoped log is a second surface rendering RecentRun rows —
    // the no-operator-PII-framing contract must hold here too.
    expect(drawer.textContent).not.toContain("(you)");
  });

  it("Draft tab renders the intro (capability cards + suggestion chips) and mounts the chat in routine-authoring mode", async () => {
    chatSurfaceProps.last = null;
    render(<RoutinesSurface />);
    fireEvent.click(screen.getByRole("tab", { name: /Draft a routine/ }));
    // Intro state (mock 05): two capability cards + composer hint.
    expect(screen.getByText("Draft a new routine")).toBeTruthy();
    expect(screen.getByText(/Run & verify an existing routine/)).toBeTruthy();
    expect(screen.getByText(/New routines ship as code/)).toBeTruthy();
    expect(screen.getByText("Run & verify cron-legal-audit")).toBeTruthy();
    // Chat mounted, scoped to routine-authoring mode (no document path).
    expect(screen.getByTestId("chat-surface-stub")).toBeTruthy();
    const props = chatSurfaceProps.last as Record<string, unknown>;
    expect(props.variant).toBe("sidebar");
    expect(props.conversationId).toBe("new");
    expect(props.initialContext).toEqual({ type: "routine-authoring" });
  });
});
