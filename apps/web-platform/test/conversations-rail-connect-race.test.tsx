import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, render, screen, waitFor, act, cleanup } from "@testing-library/react";
import type { Conversation } from "@/lib/types";

// RED→GREEN regression for plan
// 2026-06-16-fix-recent-conversations-rail-optimistic-insert.
//
// Bug (second attempt — the "still" in the report): a freshly-STARTED
// conversation does not appear in the Recent Conversations rail until it
// completes. PR #5391 added a Realtime INSERT subscription + a one-shot
// SUBSCRIBED backfill, but the gap persists on the reported path
// (/dashboard → /dashboard/chat/new) because the rail portals per-drill
// (ADR-047) and mounts fresh, so its own `useConversations` instance hits a
// connect-race:
//
//   - The realtime own-channel subscribes after `userId` resolves but while
//     `workspaceId` is still `null` (it is set INSIDE the async
//     fetchConversations). An own-channel INSERT arriving in that window is
//     dropped by `shouldDropForScope` (conv.workspace_id !== null) — the code
//     itself documents this at use-conversations.ts:98-99.
//   - The completion UPDATE is `prev.map(...)` — it patches existing rows only
//     and cannot ADD a missing one. So the row surfaces only on the next full
//     refetch ("appears only after it completes").
//
// Contract (this fix), all on the rail's OWN hook instance:
//   1. Backfill when `workspaceId` resolves (null → id): a row dropped during
//      the null-workspace window is recovered by a bounded refetch (fires once
//      on the transition, not per render).
//   2. An own-channel INSERT dropped for an unresolved (null) workspace is NOT
//      lost: it schedules the recovery backfill AND mirrors the silent drop to
//      Sentry (cq-silent-fallback-must-mirror-to-sentry).
//   3. Scope-guard parity preserved: a second workspace's rail never shows this
//      workspace's new conversation (F3 cross-scope-leak containment).
//   4. The UPDATE path stays map-only (membership is owned by insert/backfill).

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

// Sentry mirror spy (the client-safe shim). Asserted by AC3.
const warnSilentFallbackMock = vi.fn();
vi.mock("@/lib/client-observability", () => ({
  warnSilentFallback: (...args: unknown[]) => warnSilentFallbackMock(...args),
  reportSilentFallback: vi.fn(),
}));

// next/navigation: useParams for the active-row highlight (no active row here).
const paramsMock = vi.fn(() => ({}) as Record<string, string>);
vi.mock("next/navigation", () => ({
  useParams: () => paramsMock(),
}));

const state: {
  // What the conversations list query returns, per call index (1-based).
  // The connect-race tests want the INITIAL query to return [] (row not yet in
  // the DB snapshot the first query saw) and the RECOVERY backfill to return
  // the row — so the backfill is provably the mechanism that lands it.
  convResultByCall: Conversation[][];
  fallbackConvResult: Conversation[];
  convCalls: number;
  messages: { conversation_id: string; role: string; content: string; leader_id: string | null; created_at: string }[];
  channels: ChannelMock[];
  activeRepoCalls: number;
  workspaceIdResponse: string | null;
  repoUrlResponse: string | null;
  // Gate the FIRST active-repo fetch so workspaceId stays null while we fire an
  // own-channel INSERT into the connect-race window. Call `releaseActiveRepo()`
  // to let it resolve (workspaceId → id).
  deferFirstActiveRepo: boolean;
  releaseActiveRepo: (() => void) | null;
} = {
  convResultByCall: [],
  fallbackConvResult: [],
  convCalls: 0,
  messages: [],
  channels: [],
  activeRepoCalls: 0,
  workspaceIdResponse: WS_ID,
  repoUrlResponse: ACTIVE_REPO_URL,
  deferFirstActiveRepo: false,
  releaseActiveRepo: null,
};

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

function nextConvResult(): Conversation[] {
  state.convCalls += 1;
  const byCall = state.convResultByCall[state.convCalls - 1];
  return byCall ?? state.fallbackConvResult;
}

function buildConversationsChain() {
  const chain: Record<string, unknown> = {};
  Object.assign(chain, {
    select: vi.fn(() => chain),
    eq: vi.fn(() => chain),
    is: vi.fn(() => chain),
    not: vi.fn(() => chain),
    order: vi.fn(() => chain),
    limit: vi.fn(() => Promise.resolve({ data: nextConvResult(), error: null })),
  });
  return chain;
}

function buildMessagesChain() {
  const chain: Record<string, unknown> = {};
  Object.assign(chain, {
    select: vi.fn(() => chain),
    in: vi.fn(() => chain),
    order: vi.fn(() => Promise.resolve({ data: state.messages, error: null })),
  });
  return chain;
}

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getUser: vi.fn(() =>
        Promise.resolve({ data: { user: { id: "user-1" } }, error: null }),
      ),
    },
    from: vi.fn((table: string) => {
      if (table === "conversations") return buildConversationsChain();
      if (table === "messages") return buildMessagesChain();
      throw new Error(`unexpected table: ${table}`);
    }),
    channel: vi.fn((name: string) => buildChannel(name)),
    removeChannel: vi.fn(),
  }),
}));

function makeRow(overrides: Partial<Conversation> = {}): Conversation {
  return {
    id: "conv-new",
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

function lastChannel(name: string): ChannelMock {
  const matches = state.channels.filter((c) => c.name === name);
  const ch = matches[matches.length - 1];
  if (!ch) throw new Error(`channel ${name} was never created`);
  return ch;
}

function handlerOn(channelName: string, event: string): RealtimeHandler["cb"] {
  const ch = lastChannel(channelName);
  const h = ch.handlers.find((x) => x.event === event);
  if (!h) throw new Error(`no ${event} handler on ${channelName}`);
  return h.cb;
}

beforeEach(() => {
  vi.clearAllMocks();
  warnSilentFallbackMock.mockReset();
  paramsMock.mockReturnValue({});
  state.convResultByCall = [];
  state.fallbackConvResult = [];
  state.convCalls = 0;
  state.messages = [];
  state.channels = [];
  state.activeRepoCalls = 0;
  state.workspaceIdResponse = WS_ID;
  state.repoUrlResponse = ACTIVE_REPO_URL;
  state.deferFirstActiveRepo = false;
  state.releaseActiveRepo = null;

  vi.stubGlobal(
    "fetch",
    vi.fn((url: string) => {
      if (url === "/api/workspace/active-repo") {
        state.activeRepoCalls += 1;
        const body = {
          ok: true,
          json: () =>
            Promise.resolve({
              workspaceId: state.workspaceIdResponse,
              repoUrl: state.repoUrlResponse,
              repoName: "acme/active",
              repoStatus: "connected",
              fellBackToSolo: false,
            }),
        };
        if (state.activeRepoCalls === 1 && state.deferFirstActiveRepo) {
          return new Promise((resolve) => {
            state.releaseActiveRepo = () => resolve(body);
          });
        }
        return Promise.resolve(body);
      }
      return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
    }),
  );
});

afterEach(() => {
  cleanup();
});

describe("useConversations — fresh-mount connect-race (Recent Conversations rail)", () => {
  it("AC1: the new conversation row renders in the REAL rail before completion (connect-race path)", async () => {
    // Reproduce the reported path: the rail mounts while active-repo is still
    // in flight (workspaceId null). An own-channel INSERT for the new
    // conversation arrives in that window; the initial list query saw an empty
    // snapshot. The fix must surface the row once scope resolves.
    state.deferFirstActiveRepo = true;
    state.convResultByCall = [[] /* initial query: empty */];
    // Backfill (recovery) query returns the new row; its title derives from the
    // first user message ("Fix Issue 4826", matching the reported screenshot).
    const newRow = makeRow({ id: "conv-fix-4826" });
    state.fallbackConvResult = [newRow];
    state.messages = [
      {
        conversation_id: "conv-fix-4826",
        role: "user",
        content: "Fix Issue 4826",
        leader_id: null,
        created_at: new Date().toISOString(),
      },
    ];

    const { ConversationsRail } = await import("@/components/chat/conversations-rail");
    render(<ConversationsRail />);

    // Wait until the own channel exists (userId resolved, subscribed) while
    // active-repo is still deferred → workspaceId is still null.
    await waitFor(() => expect(state.channels.some((c) => c.name === "command-center-own")).toBe(true));

    // Fire the own-channel INSERT in the null-workspace window.
    await act(async () => {
      handlerOn("command-center-own", "INSERT")({
        new: newRow,
        eventType: "INSERT",
      });
    });

    // Now scope resolves → the recovery backfill must land the row in the rail.
    await act(async () => {
      state.releaseActiveRepo?.();
    });

    await waitFor(() => expect(screen.getByText("Fix Issue 4826")).toBeInTheDocument());
  });

  it("AC2/AC3: a null-workspace own INSERT is recovered by the scope-resolve backfill (and mirrored to Sentry)", async () => {
    state.deferFirstActiveRepo = true;
    // Initial query (call 1) returns empty; the recovery backfill (call 2)
    // returns the new row — so the backfill is provably what lands it.
    const newRow = makeRow({ id: "conv-recovered" });
    state.convResultByCall = [[], [newRow]];
    state.fallbackConvResult = [newRow];

    const { useConversations } = await import("@/hooks/use-conversations");
    const view = renderHook(() => useConversations({ limit: 15 }));

    await waitFor(() => expect(state.channels.some((c) => c.name === "command-center-own")).toBe(true));

    // INSERT while workspaceId is still null → dropped, but recovery scheduled
    // + silent drop mirrored to Sentry.
    await act(async () => {
      handlerOn("command-center-own", "INSERT")({ new: newRow, eventType: "INSERT" });
    });
    expect(view.result.current.conversations.map((c) => c.id)).not.toContain("conv-recovered");
    expect(warnSilentFallbackMock).toHaveBeenCalledTimes(1);
    expect(warnSilentFallbackMock.mock.calls[0]?.[1]).toMatchObject({ feature: "conversations-rail" });

    // Resolve scope → recovery backfill lands the row.
    await act(async () => {
      state.releaseActiveRepo?.();
    });

    await waitFor(() =>
      expect(view.result.current.conversations.map((c) => c.id)).toContain("conv-recovered"),
    );
  });

  it("AC2 (bounded): the scope-resolve backfill fires once, not per render", async () => {
    state.deferFirstActiveRepo = true;
    const newRow = makeRow({ id: "conv-bounded" });
    state.convResultByCall = [[], [newRow]];
    state.fallbackConvResult = [newRow];

    const { useConversations } = await import("@/hooks/use-conversations");
    const view = renderHook(() => useConversations({ limit: 15 }));
    await waitFor(() => expect(state.channels.some((c) => c.name === "command-center-own")).toBe(true));
    await act(async () => {
      handlerOn("command-center-own", "INSERT")({ new: newRow, eventType: "INSERT" });
    });
    await act(async () => {
      state.releaseActiveRepo?.();
    });
    await waitFor(() =>
      expect(view.result.current.conversations.map((c) => c.id)).toContain("conv-bounded"),
    );

    // active-repo calls so far: initial (1) + recovery backfill (2). A bare
    // re-render must NOT trigger another backfill (transition-gated).
    const callsAfterRecovery = state.activeRepoCalls;
    expect(callsAfterRecovery).toBe(2);
    view.rerender();
    await Promise.resolve();
    expect(state.activeRepoCalls).toBe(callsAfterRecovery);
  });

  it("AC4: a second workspace's rail does NOT show this workspace's new conversation (F3 containment)", async () => {
    // This rail is scoped to workspace B; an own-channel INSERT for a workspace-A
    // conversation on the SAME repo must be dropped (own-channel WAL filter is
    // user_id only — repo_url alone cannot discriminate two same-repo workspaces).
    state.workspaceIdResponse = "ws-B";
    state.fallbackConvResult = [];

    const { useConversations } = await import("@/hooks/use-conversations");
    const view = renderHook(() => useConversations({ limit: 15 }));
    await waitFor(() => expect(view.result.current.loading).toBe(false));

    await act(async () => {
      handlerOn("command-center-own", "INSERT")({
        new: makeRow({ id: "ws-a-conv", workspace_id: WS_ID }),
        eventType: "INSERT",
      });
    });

    expect(view.result.current.conversations.map((c) => c.id)).not.toContain("ws-a-conv");
  });

  it("AC5: a completion UPDATE for a row NOT present does not resurrect it (map-only preserved)", async () => {
    state.fallbackConvResult = [];
    const { useConversations } = await import("@/hooks/use-conversations");
    const view = renderHook(() => useConversations({ limit: 15 }));
    await waitFor(() => expect(view.result.current.loading).toBe(false));

    await act(async () => {
      handlerOn("command-center-own", "UPDATE")({
        new: makeRow({ id: "absent", status: "completed" }),
        eventType: "UPDATE",
      });
    });

    expect(view.result.current.conversations.map((c) => c.id)).not.toContain("absent");
  });
});
