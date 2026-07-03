import {
  describe,
  it,
  expect,
  beforeEach,
  afterEach,
  vi,
} from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { userEvent } from "@testing-library/user-event";

// PR-B (#4379) Phase 5.3 — LeaderLoopStatus integration tests.
//
// Covers:
//   - State-matrix integration: pre-row → "acknowledged_starting"; populated
//     row drives `working`/`stopping`/`done`/`undone`/`failure_*`.
//   - Stop button → POST /cancel with optimistic UI flip to "stopping".
//   - Undo button → POST /undo, 200 success / 207 partial ledger /
//     409 already_undone.
//   - Cost badge → GET /cost, formatted as `Cost: $X.XX (N turn(s))`.
//   - Realtime subscription → no polling; CHANNEL_ERROR → 2s polling
//     fallback (FR3).

const { createClientMock } = vi.hoisted(() => ({
  createClientMock: vi.fn(),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: createClientMock,
}));

interface FakeRow {
  failure_reason: string | null;
  reversal_handles: unknown[] | null;
  undone_at: string | null;
  acknowledged_at: string | null;
  artifact_url: string | null;
  cancellation_requested_at: string | null;
  current_turn: number | null;
}

interface FakeChannel {
  on: (event: string, filter: unknown, handler: (p: { new: FakeRow }) => void) => FakeChannel;
  subscribe: (cb: (status: string) => void) => FakeChannel;
  _emit: (row: FakeRow) => void;
  _statusCallback: ((status: string) => void) | null;
}

function buildFakeChannel(): FakeChannel {
  let updateHandler: ((p: { new: FakeRow }) => void) | null = null;
  const ch: FakeChannel = {
    on: ((_event: string, _filter: unknown, handler: (p: { new: FakeRow }) => void) => {
      updateHandler = handler;
      return ch;
    }) as FakeChannel["on"],
    subscribe: ((cb: (status: string) => void) => {
      ch._statusCallback = cb;
      // Default: immediately report SUBSCRIBED (happy path, no polling).
      queueMicrotask(() => cb("SUBSCRIBED"));
      return ch;
    }) as FakeChannel["subscribe"],
    _emit: (row: FakeRow) => {
      if (updateHandler) updateHandler({ new: row });
    },
    _statusCallback: null,
  };
  return ch;
}

function buildSupabaseClient(initialRow: FakeRow | null, channel: FakeChannel) {
  const fromChain: Record<string, unknown> = {};
  Object.assign(fromChain, {
    select: vi.fn(() => fromChain),
    eq: vi.fn(() => fromChain),
    maybeSingle: vi.fn(() => Promise.resolve({ data: initialRow, error: null })),
  });
  return {
    from: vi.fn(() => fromChain),
    channel: vi.fn(() => channel),
    removeChannel: vi.fn(),
  };
}

const ORIGINAL_FETCH = globalThis.fetch;

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  fetchMock = vi.fn(async (input: string) => {
    if (input.endsWith("/cost")) {
      return new Response(
        JSON.stringify({ cumulativeCents: 0, turnCount: 0 }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }
    return new Response(JSON.stringify({}), { status: 200 });
  });
  globalThis.fetch = fetchMock as unknown as typeof fetch;
  createClientMock.mockReset();
});

afterEach(() => {
  globalThis.fetch = ORIGINAL_FETCH;
});

describe("LeaderLoopStatus — initial render before action_sends row", () => {
  it("renders 'acknowledged_starting' copy when no row exists yet", async () => {
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() => buildSupabaseClient(null, channel));

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );

    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      const panel = screen.getByTestId("leader-loop-status");
      expect(panel.getAttribute("data-state-kind")).toBe(
        "acknowledged_starting",
      );
    });
  });
});

describe("LeaderLoopStatus — state-matrix integration (AC11)", () => {
  it("renders 'working' state + Stop button when current_turn>0 and not acknowledged", async () => {
    const row: FakeRow = {
      failure_reason: null,
      reversal_handles: null,
      undone_at: null,
      acknowledged_at: null,
      artifact_url: null,
      cancellation_requested_at: null,
      current_turn: 2,
    };
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() => buildSupabaseClient(row, channel));

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );

    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      const panel = screen.getByTestId("leader-loop-status");
      expect(panel.getAttribute("data-state-kind")).toBe("working");
    });
    expect(screen.getByLabelText(/Stop agent/)).toBeInTheDocument();
    expect(screen.queryByLabelText(/Undo agent action/)).toBeNull();
    expect(screen.getByTestId("leader-loop-copy").textContent).toMatch(
      /Working — turn 2/,
    );
  });

  it("renders 'done' state with AcknowledgedPill + Undo button when artifact present", async () => {
    const row: FakeRow = {
      failure_reason: null,
      reversal_handles: [{ kind: "pr_comment", owner: "a", repo: "b", commentId: 1 }],
      undone_at: null,
      acknowledged_at: "2026-05-25T00:00:00Z",
      artifact_url: "https://github.com/a/b/pull/7",
      cancellation_requested_at: null,
      current_turn: 3,
    };
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() => buildSupabaseClient(row, channel));

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );

    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      const panel = screen.getByTestId("leader-loop-status");
      expect(panel.getAttribute("data-state-kind")).toBe("done");
    });

    const pill = screen.getByTestId("acknowledged-pill");
    expect(pill.getAttribute("data-pill-state")).toBe("ack");
    expect(pill.getAttribute("href")).toBe("https://github.com/a/b/pull/7");
    expect(screen.getByLabelText(/Undo agent action/)).toBeInTheDocument();
  });

  it("renders 'failure_no_artifact' state with Retry when failure_reason is Retry-eligible", async () => {
    const row: FakeRow = {
      failure_reason: "anthropic_timeout",
      reversal_handles: null,
      undone_at: null,
      acknowledged_at: null,
      artifact_url: null,
      cancellation_requested_at: null,
      current_turn: 1,
    };
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() => buildSupabaseClient(row, channel));

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );

    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      const panel = screen.getByTestId("leader-loop-status");
      expect(panel.getAttribute("data-state-kind")).toBe("failure_no_artifact");
    });
    expect(screen.getByLabelText(/Retry agent/)).toBeInTheDocument();
    // CPO-2: raw failure_reason never leaks.
    expect(screen.getByTestId("leader-loop-copy").textContent).not.toMatch(
      /anthropic_timeout/,
    );
  });
});

describe("LeaderLoopStatus — Resume button (feat-l5-runaway-guard PR-A)", () => {
  const pausedRow: FakeRow = {
    failure_reason: "byok_cap_exceeded",
    reversal_handles: null,
    undone_at: null,
    acknowledged_at: null,
    artifact_url: null,
    cancellation_requested_at: null,
    current_turn: 1,
  };

  it("shows Resume on a paused-state failure and POSTs the resume route on click", async () => {
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() => buildSupabaseClient(pausedRow, channel));

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );
    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      expect(
        screen.getByTestId("leader-loop-status").getAttribute("data-state-kind"),
      ).toBe("failure_no_artifact");
    });

    const resumeBtn = screen.getByLabelText(/Resume run|Clear pause/i);
    const user = userEvent.setup();
    await user.click(resumeBtn);

    await waitFor(() => {
      const resumeCalls = fetchMock.mock.calls.filter((c) =>
        String(c[0]).endsWith("/api/dashboard/runtime/resume"),
      );
      expect(resumeCalls).toHaveLength(1);
      expect((resumeCalls[0][1] as RequestInit).method).toBe("POST");
    });
  });

  it("does NOT show Resume for a non-pausing failure (cost_ceiling_exceeded)", async () => {
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() =>
      buildSupabaseClient({ ...pausedRow, failure_reason: "cost_ceiling_exceeded" }, channel),
    );

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );
    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      expect(
        screen.getByTestId("leader-loop-status").getAttribute("data-state-kind"),
      ).toBe("failure_no_artifact");
    });
    expect(screen.queryByLabelText(/Resume run|Clear pause/i)).toBeNull();
  });
});

describe("LeaderLoopStatus — Stop button (AC13)", () => {
  it("posts /cancel and optimistically flips to 'stopping'", async () => {
    const row: FakeRow = {
      failure_reason: null,
      reversal_handles: null,
      undone_at: null,
      acknowledged_at: null,
      artifact_url: null,
      cancellation_requested_at: null,
      current_turn: 2,
    };
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() => buildSupabaseClient(row, channel));

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );

    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      expect(screen.getByTestId("leader-loop-status").getAttribute("data-state-kind")).toBe(
        "working",
      );
    });

    const user = userEvent.setup();
    await user.click(screen.getByLabelText(/Stop agent/));

    await waitFor(() => {
      expect(screen.getByTestId("leader-loop-status").getAttribute("data-state-kind")).toBe(
        "stopping",
      );
    });

    const cancelCalls = fetchMock.mock.calls.filter((c) =>
      String(c[0]).endsWith("/cancel"),
    );
    expect(cancelCalls).toHaveLength(1);
    expect((cancelCalls[0][1] as RequestInit).method).toBe("POST");
  });
});

describe("LeaderLoopStatus — Undo button (AC14)", () => {
  const baseDoneRow: FakeRow = {
    failure_reason: null,
    reversal_handles: [{ kind: "pr_comment", owner: "a", repo: "b", commentId: 1 }],
    undone_at: null,
    acknowledged_at: "2026-05-25T00:00:00Z",
    artifact_url: "https://github.com/a/b/pull/7",
    cancellation_requested_at: null,
    current_turn: 3,
  };

  it("happy 200 — calls /undo POST", async () => {
    fetchMock.mockImplementation(async (input: string) => {
      if (input.endsWith("/cost")) {
        return new Response(
          JSON.stringify({ cumulativeCents: 0, turnCount: 0 }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }
      if (input.endsWith("/undo")) {
        return new Response(
          JSON.stringify({ allSucceeded: true, elements: [] }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }
      return new Response(JSON.stringify({}), { status: 200 });
    });
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() => buildSupabaseClient(baseDoneRow, channel));

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );

    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      expect(screen.getByLabelText(/Undo agent action/)).toBeInTheDocument();
    });
    const user = userEvent.setup();
    await user.click(screen.getByLabelText(/Undo agent action/));

    await waitFor(() => {
      const undoCalls = fetchMock.mock.calls.filter((c) =>
        String(c[0]).endsWith("/undo"),
      );
      expect(undoCalls).toHaveLength(1);
      expect((undoCalls[0][1] as RequestInit).method).toBe("POST");
    });
  });

  it("207 partial — renders per-element ledger", async () => {
    fetchMock.mockImplementation(async (input: string) => {
      if (input.endsWith("/cost")) {
        return new Response(
          JSON.stringify({ cumulativeCents: 0, turnCount: 0 }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }
      if (input.endsWith("/undo")) {
        return new Response(
          JSON.stringify({
            allSucceeded: false,
            elements: [
              { index: 0, kind: "pr_comment", status: "reverted" },
              { index: 1, kind: "branch", status: "failed_5xx", error: "boom" },
            ],
          }),
          { status: 207, headers: { "Content-Type": "application/json" } },
        );
      }
      return new Response(JSON.stringify({}), { status: 200 });
    });
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() => buildSupabaseClient(baseDoneRow, channel));

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );

    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      expect(screen.getByLabelText(/Undo agent action/)).toBeInTheDocument();
    });
    const user = userEvent.setup();
    await user.click(screen.getByLabelText(/Undo agent action/));

    await waitFor(() => {
      const ledger = screen.getByTestId("undo-partial-ledger");
      expect(ledger).toBeInTheDocument();
      expect(ledger.textContent).toMatch(/pr_comment.*reverted/);
      expect(ledger.textContent).toMatch(/branch.*failed_5xx.*boom/);
    });
  });

  it("409 — renders 'Already undone' copy", async () => {
    fetchMock.mockImplementation(async (input: string) => {
      if (input.endsWith("/cost")) {
        return new Response(
          JSON.stringify({ cumulativeCents: 0, turnCount: 0 }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }
      if (input.endsWith("/undo")) {
        return new Response(
          JSON.stringify({ error: "already_undone", copy: "Already undone." }),
          { status: 409, headers: { "Content-Type": "application/json" } },
        );
      }
      return new Response(JSON.stringify({}), { status: 200 });
    });
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() => buildSupabaseClient(baseDoneRow, channel));

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );

    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      expect(screen.getByLabelText(/Undo agent action/)).toBeInTheDocument();
    });
    const user = userEvent.setup();
    await user.click(screen.getByLabelText(/Undo agent action/));

    await waitFor(() => {
      expect(screen.getByTestId("undo-already-undone")).toBeInTheDocument();
    });
  });
});

describe("LeaderLoopStatus — Cost badge (AC15)", () => {
  it("formats cumulativeCents and turnCount as `Cost: $X.XX (N turns)`", async () => {
    fetchMock.mockImplementation(async (input: string) => {
      if (input.endsWith("/cost")) {
        return new Response(
          JSON.stringify({ cumulativeCents: 1234, turnCount: 3 }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }
      return new Response(JSON.stringify({}), { status: 200 });
    });
    const row: FakeRow = {
      failure_reason: null,
      reversal_handles: null,
      undone_at: null,
      acknowledged_at: null,
      artifact_url: null,
      cancellation_requested_at: null,
      current_turn: 3,
    };
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() => buildSupabaseClient(row, channel));

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );

    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      const badge = screen.getByTestId("cost-badge");
      expect(badge.textContent).toBe("Cost: $12.34 (3 turns)");
    });
  });

  it("renders singular 'turn' when turnCount === 1", async () => {
    fetchMock.mockImplementation(async (input: string) => {
      if (input.endsWith("/cost")) {
        return new Response(
          JSON.stringify({ cumulativeCents: 50, turnCount: 1 }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }
      return new Response(JSON.stringify({}), { status: 200 });
    });
    const row: FakeRow = {
      failure_reason: null,
      reversal_handles: null,
      undone_at: null,
      acknowledged_at: null,
      artifact_url: null,
      cancellation_requested_at: null,
      current_turn: 1,
    };
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() => buildSupabaseClient(row, channel));

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );

    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      const badge = screen.getByTestId("cost-badge");
      expect(badge.textContent).toBe("Cost: $0.50 (1 turn)");
    });
  });

  it("hides cost badge when turnCount === 0", async () => {
    const row: FakeRow = {
      failure_reason: null,
      reversal_handles: null,
      undone_at: null,
      acknowledged_at: null,
      artifact_url: null,
      cancellation_requested_at: null,
      current_turn: 1,
    };
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() => buildSupabaseClient(row, channel));

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );

    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      expect(screen.getByTestId("leader-loop-status")).toBeInTheDocument();
    });
    expect(screen.queryByTestId("cost-badge")).toBeNull();
  });
});

describe("LeaderLoopStatus — FR3 polling fallback on terminal subscribe status", () => {
  it("CHANNEL_ERROR triggers 2s polling (calls fetchRow + refreshCost beyond the initial pull)", async () => {
    vi.useFakeTimers();
    try {
      const row: FakeRow = {
        failure_reason: null,
        reversal_handles: null,
        undone_at: null,
        acknowledged_at: null,
        artifact_url: null,
        cancellation_requested_at: null,
        current_turn: 1,
      };

      // Build a channel that reports CHANNEL_ERROR via the subscribe callback
      // so the component installs the 2s polling interval.
      let updateHandler: ((p: { new: FakeRow }) => void) | null = null;
      const ch: FakeChannel = {
        on: ((_event: string, _filter: unknown, handler: (p: { new: FakeRow }) => void) => {
          updateHandler = handler;
          return ch;
        }) as FakeChannel["on"],
        subscribe: ((cb: (status: string) => void) => {
          ch._statusCallback = cb;
          queueMicrotask(() => cb("CHANNEL_ERROR"));
          return ch;
        }) as FakeChannel["subscribe"],
        _emit: (r: FakeRow) => {
          if (updateHandler) updateHandler({ new: r });
        },
        _statusCallback: null,
      };

      let fetchRowCalls = 0;
      let fetchCostCalls = 0;
      fetchMock.mockImplementation(async (input: string) => {
        if (input.endsWith("/cost")) {
          fetchCostCalls++;
          return new Response(
            JSON.stringify({ cumulativeCents: 0, turnCount: 0 }),
            { status: 200, headers: { "Content-Type": "application/json" } },
          );
        }
        return new Response(JSON.stringify({}), { status: 200 });
      });

      const fromChain: Record<string, unknown> = {};
      Object.assign(fromChain, {
        select: vi.fn(() => fromChain),
        eq: vi.fn(() => fromChain),
        maybeSingle: vi.fn(() => {
          fetchRowCalls++;
          return Promise.resolve({ data: row, error: null });
        }),
      });
      createClientMock.mockImplementation(() => ({
        from: vi.fn(() => fromChain),
        channel: vi.fn(() => ch),
        removeChannel: vi.fn(),
      }));

      const { LeaderLoopStatus } = await import(
        "@/components/dashboard/leader-loop-status"
      );

      render(<LeaderLoopStatus messageId="msg-1" />);

      // Initial mount: 1 fetchRow + 1 /cost. Let microtasks settle.
      await Promise.resolve();
      await Promise.resolve();
      const initialFetchRowCalls = fetchRowCalls;
      const initialCostCalls = fetchCostCalls;

      // Advance 4 seconds → 2 polling ticks should have fired.
      await vi.advanceTimersByTimeAsync(4500);

      expect(fetchRowCalls).toBeGreaterThan(initialFetchRowCalls);
      expect(fetchCostCalls).toBeGreaterThan(initialCostCalls);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("LeaderLoopStatus — Realtime UPDATE drives state transitions", () => {
  it("transitions working → done when payload sets acknowledged_at + reversal_handles", async () => {
    const startRow: FakeRow = {
      failure_reason: null,
      reversal_handles: null,
      undone_at: null,
      acknowledged_at: null,
      artifact_url: null,
      cancellation_requested_at: null,
      current_turn: 2,
    };
    const channel = buildFakeChannel();
    createClientMock.mockImplementation(() =>
      buildSupabaseClient(startRow, channel),
    );

    const { LeaderLoopStatus } = await import(
      "@/components/dashboard/leader-loop-status"
    );

    render(<LeaderLoopStatus messageId="msg-1" />);

    await waitFor(() => {
      expect(screen.getByTestId("leader-loop-status").getAttribute("data-state-kind")).toBe(
        "working",
      );
    });

    channel._emit({
      ...startRow,
      acknowledged_at: "2026-05-25T00:00:00Z",
      reversal_handles: [{ kind: "branch", owner: "a", repo: "b", branchRef: "x" }],
      artifact_url: "https://github.com/a/b/pull/9",
      current_turn: 3,
    });

    await waitFor(() => {
      expect(screen.getByTestId("leader-loop-status").getAttribute("data-state-kind")).toBe(
        "done",
      );
    });
  });
});
