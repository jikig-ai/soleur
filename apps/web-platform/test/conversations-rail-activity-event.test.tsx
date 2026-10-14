import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor, act } from "@testing-library/react";
import type { Conversation } from "@/lib/types";
import { enrichConversationFixtures } from "./helpers/mock-supabase";
import { SwrTestProvider } from "./helpers/swr-wrapper";

// RED→GREEN regression for plan
// 2026-09-30-fix-conversations-rail-live-status-plan (PR #9270).
//
// Bug: the rail's badge for the VIEWED conversation stays at its terminal
// status ("Done"/"Needs your decision") while the session is actively
// working; it only corrects on exit + re-entry (a remount + refetch).
// The rail's only live-update channel is the realtime UPDATE subscription,
// which is observably lossy in this window — the same class the
// `CONVERSATION_CREATED_EVENT` mechanism was built for.
//
// Contract (this fix): `chat-surface` dispatches `CONVERSATION_ACTIVITY_EVENT`
// on the viewed conversation's derived turn boundaries (streamState
// transitions + gate transitions); the rail's `useConversations` listener
// runs a debounced QUIET refetch — deterministic, realtime-independent.

const ACTIVE_REPO_URL = "https://github.com/acme/active";
const WS_ID = "ws-A";

type RealtimeHandler = {
  event: string;
  filter?: string;
  cb: (payload: { new: unknown; eventType?: string }) => void;
};

interface ChannelMock {
  name: string;
  handlers: RealtimeHandler[];
  statusCb: ((status: string) => void) | null;
  on: (type: string, config: { event: string; filter?: string }, cb: RealtimeHandler["cb"]) => ChannelMock;
  subscribe: (cb?: (status: string) => void) => ChannelMock;
}

const state: {
  rows: Conversation[];
  channels: ChannelMock[];
  rpcCalls: number;
  deferRpcOnCall: number | null;
  releaseRpc: (() => void) | null;
} = { rows: [], channels: [], rpcCalls: 0, deferRpcOnCall: null, releaseRpc: null };

function buildChannel(name: string): ChannelMock {
  const ch: ChannelMock = {
    name,
    handlers: [],
    statusCb: null,
    on: vi.fn((_type: string, config: { event: string; filter?: string }, cb: RealtimeHandler["cb"]) => {
      ch.handlers.push({ event: config.event, filter: config.filter, cb });
      return ch;
    }),
    subscribe: vi.fn((cb?: (status: string) => void) => {
      if (cb) ch.statusCb = cb;
      return ch;
    }),
  };
  state.channels.push(ch);
  return ch;
}

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getSession: vi.fn(() =>
        Promise.resolve({
          data: { session: { user: { id: "user-1" } } },
          error: null,
        }),
      ),
      getUser: vi.fn(() =>
        Promise.resolve({ data: { user: { id: "user-1" } }, error: null }),
      ),
    },
    rpc: vi.fn((name: string) => {
      if (name !== "list_conversations_enriched") {
        return Promise.resolve({ data: null, error: { message: `unexpected rpc: ${name}` } });
      }
      state.rpcCalls += 1;
      const body = () => ({
        data: enrichConversationFixtures(state.rows, []),
        error: null,
      });
      // Hold the Nth call pending so the test can assert loading stays false
      // while the event refetch is IN FLIGHT (the quiet contract — a post-hoc
      // loading===false read after completion would be vacuous).
      if (state.deferRpcOnCall === state.rpcCalls) {
        return new Promise((resolve) => {
          state.releaseRpc = () => resolve(body());
        });
      }
      return Promise.resolve(body());
    }),
    from: vi.fn((table: string) => {
      const chain: Record<string, unknown> = {};
      Object.assign(chain, {
        select: vi.fn(() => chain),
        eq: vi.fn(() => chain),
        is: vi.fn(() => chain),
        in: vi.fn(() => chain),
        not: vi.fn(() => chain),
        order: vi.fn(() => chain),
        limit: vi.fn(() => Promise.resolve({ data: state.rows, error: null })),
      });
      if (table === "conversations" || table === "messages") return chain;
      throw new Error(`unexpected table: ${table}`);
    }),
    channel: vi.fn((name: string) => buildChannel(name)),
    removeChannel: vi.fn(),
  }),
}));

vi.mock("@/lib/client-observability", () => ({
  warnSilentFallback: vi.fn(),
  reportSilentFallback: vi.fn(),
}));

function makeRow(overrides: Partial<Conversation> = {}): Conversation {
  return {
    id: "conv-1",
    user_id: "user-1",
    repo_url: ACTIVE_REPO_URL,
    workspace_id: WS_ID,
    visibility: "private",
    domain_leader: null,
    session_id: null,
    status: "active",
    total_cost_usd: 0,
    input_tokens: 0,
    output_tokens: 0,
    last_active: new Date().toISOString(),
    created_at: new Date().toISOString(),
    archived_at: null,
    ...overrides,
  };
}

const swrWrapper = ({ children }: { children: React.ReactNode }) => (
  <SwrTestProvider>{children}</SwrTestProvider>
);

async function mountRail() {
  const { useConversations } = await import("@/hooks/use-conversations");
  const view = renderHook(() => useConversations({ limit: 15 }), { wrapper: swrWrapper });
  await waitFor(() => expect(view.result.current.loading).toBe(false));
  return view;
}

beforeEach(() => {
  vi.clearAllMocks();
  state.rows = [];
  state.channels = [];
  state.rpcCalls = 0;
  state.deferRpcOnCall = null;
  state.releaseRpc = null;
  vi.stubGlobal(
    "fetch",
    vi.fn((_url: string) =>
      Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            workspaceId: WS_ID,
            repoUrl: ACTIVE_REPO_URL,
            repoName: "acme/active",
            repoStatus: "connected",
            fellBackToSolo: false,
          }),
      }),
    ),
  );
});

describe("useConversations — CONVERSATION_ACTIVITY_EVENT quiet refetch", () => {
  it("the viewed conversation's stale badge refetches to the live status on the event — no realtime, no remount", async () => {
    // The reported bug: a `completed` conversation's rail badge reads "Done"
    // while its turn is running. Realtime UPDATE is missed (dead channel /
    // re-subscribe window); the deterministic event must recover it in place.
    state.rows = [makeRow({ id: "conv-live", status: "completed" })];
    const view = await mountRail();
    expect(view.result.current.conversations[0]?.status).toBe("completed");
    const callsBefore = state.rpcCalls;

    // The server has flipped the row to 'active' (turn-start write); the
    // realtime UPDATE never lands — chat-surface fires the activity signal.
    // The refetch RPC is held pending so `loading` is observable WHILE the
    // fetch is in flight — a `background: false` mutation would flip
    // loading=true here (a post-hoc read after completion cannot see the
    // flash, so pinning mid-flight is what makes the quiet contract
    // non-vacuous).
    state.rows = [makeRow({ id: "conv-live", status: "active" })];
    state.deferRpcOnCall = callsBefore + 1;
    const { CONVERSATION_ACTIVITY_EVENT } = await import("@/hooks/use-conversations");
    await act(async () => {
      window.dispatchEvent(
        new CustomEvent(CONVERSATION_ACTIVITY_EVENT, {
          detail: { conversationId: "conv-live" },
        }),
      );
    });
    await waitFor(() => expect(state.rpcCalls).toBe(callsBefore + 1), {
      timeout: 3000,
    });
    expect(view.result.current.loading).toBe(false); // pending fetch, still quiet
    await act(async () => {
      state.releaseRpc?.();
    });
    await waitFor(() =>
      expect(view.result.current.conversations[0]?.status).toBe("active"),
    );
    expect(view.result.current.loading).toBe(false);
  });

  it("coalesces a burst of activity events into a single refetch (debounce)", async () => {
    state.rows = [makeRow({ id: "conv-live", status: "active" })];
    await mountRail();
    const callsBefore = state.rpcCalls;

    const { CONVERSATION_ACTIVITY_EVENT } = await import("@/hooks/use-conversations");
    await act(async () => {
      for (let i = 0; i < 3; i++) {
        window.dispatchEvent(
          new CustomEvent(CONVERSATION_ACTIVITY_EVENT, {
            detail: { conversationId: "conv-live" },
          }),
        );
      }
    });

    await waitFor(() => expect(state.rpcCalls).toBeGreaterThan(callsBefore), {
      timeout: 3000,
    });
    // One debounced refetch, not three — per-leader/frame bursts must not
    // triple the RPC load.
    expect(state.rpcCalls - callsBefore).toBe(1);
  });
});
