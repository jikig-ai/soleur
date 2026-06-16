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

  it("Recent Runs failed row expands to show error_summary", async () => {
    const failed = {
      id: "r1",
      routine_id: "cron-legal-audit",
      status: "failed",
      trigger_source: "scheduled",
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
    await waitFor(() =>
      expect(screen.getByText(/boom: upstream 503/)).toBeTruthy(),
    );
  });

  // #5402 — PR-2 Concierge "Draft a routine" tab.
  it("shows an active Draft a routine tab (not the disabled v2 placeholder)", async () => {
    render(<RoutinesSurface />);
    const draftTab = screen.getByRole("tab", { name: /Draft a routine/ });
    expect(draftTab).toBeTruthy();
    // The PR-1 placeholder had no role=tab and was cursor-not-allowed; the new
    // one is a real tab with a "new" badge (not "v2").
    expect(screen.queryByText("v2")).toBeNull();
    expect(screen.getByText("new")).toBeTruthy();
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
