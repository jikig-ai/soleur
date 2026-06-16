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
// Contract (this fix — plan 2026-06-16-feat-sidebar-new-conversation-rail), all
// on the rail's OWN hook instance:
//   1. UNCONDITIONAL backfill when `workspaceId` resolves (null → id): the
//      scope-resolve refetch now fires once on the transition REGARDLESS of
//      whether an own-channel INSERT was dropped — so a row that surfaces only
//      via a later commit / a pre-SUBSCRIBED-buffered INSERT (no drop recorded)
//      is still recovered. The previous `pendingScopeRecoveryRef` gate and its
//      `own-insert-deferred-unresolved-workspace` Sentry mirror are REMOVED:
//      "the user-paced first message hasn't arrived yet" is normal latency, not
//      a silent fallback (code-simplicity-reviewer).
//   2. The backfill is a QUIET refetch (skips setLoading/setError) so a
//      background reconcile cannot blank or error-flash the rail (AC4b).
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
  // Gate the SECOND active-repo fetch (the scope-resolve backfill) so we can
  // observe loading state WHILE the backfill is in flight (AC4b quiet-refetch).
  deferBackfillActiveRepo: boolean;
  releaseBackfillActiveRepo: (() => void) | null;
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
  deferBackfillActiveRepo: false,
  releaseBackfillActiveRepo: null,
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

// Per-call conversations-query result, indexed by COMPLETION order at
// `.limit()`-resolution time. In the connect-race tests call 1 is the resumed
// initial fetch (already past its deferred active-repo await when released) and
// call 2 is the recovery backfill (starts from scratch), so call 1 reliably
// reaches the query first — `[[], [newRow]]` therefore maps initial→[] and
// backfill→[newRow] deterministically. A no-op backfill never produces a call 2,
// so the recovery `waitFor` times out and the test fails (non-vacuous).
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
  state.deferBackfillActiveRepo = false;
  state.releaseBackfillActiveRepo = null;

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
        if (state.activeRepoCalls === 2 && state.deferBackfillActiveRepo) {
          return new Promise((resolve) => {
            state.releaseBackfillActiveRepo = () => resolve(body);
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

    await waitFor(() => expect(screen.getByText("Fix Issue 4826")).toBeInTheDocument(), {
      timeout: 3000,
    });
  });

  it("AC2/AC3: a null-workspace own INSERT is recovered by the scope-resolve backfill (NO Sentry mirror — normal latency, not a silent fallback)", async () => {
    state.deferFirstActiveRepo = true;
    // Initial query (call 1) returns empty; the recovery backfill (call 2)
    // returns the new row — so the backfill is provably what lands it.
    const newRow = makeRow({ id: "conv-recovered" });
    state.convResultByCall = [[], [newRow]];
    state.fallbackConvResult = [newRow];

    const { useConversations } = await import("@/hooks/use-conversations");
    const view = renderHook(() => useConversations({ limit: 15 }));

    await waitFor(() => expect(state.channels.some((c) => c.name === "command-center-own")).toBe(true));

    // INSERT while workspaceId is still null → dropped (shouldDropForScope:
    // workspace_id !== null). No silent-fallback mirror is emitted anymore — the
    // pendingScopeRecoveryRef arming branch + its Sentry slug were removed.
    await act(async () => {
      handlerOn("command-center-own", "INSERT")({ new: newRow, eventType: "INSERT" });
    });
    expect(view.result.current.conversations.map((c) => c.id)).not.toContain("conv-recovered");
    expect(warnSilentFallbackMock).not.toHaveBeenCalled();

    // Resolve scope → the unconditional null→id backfill lands the row.
    await act(async () => {
      state.releaseActiveRepo?.();
    });

    await waitFor(
      () => expect(view.result.current.conversations.map((c) => c.id)).toContain("conv-recovered"),
      { timeout: 3000 },
    );
    // Still no silent-fallback mirror after recovery.
    expect(warnSilentFallbackMock).not.toHaveBeenCalled();
  });

  it("AC3 (unconditional): the new row appears via the null→id backfill even when NO own INSERT was dropped", async () => {
    // The reported residual gap: no own-channel INSERT is dropped in the connect
    // window (row created later / INSERT buffered pre-SUBSCRIBED), so the OLD
    // pendingScopeRecoveryRef gate would NEVER arm and the backfill would never
    // fire. The unconditional null→id backfill must still land the row. This is
    // the test that distinguishes gated-from-unconditional: with the gate intact
    // there is no call 2, the row never surfaces, and the waitFor times out.
    state.deferFirstActiveRepo = true;
    const newRow = makeRow({ id: "conv-unconditional" });
    state.convResultByCall = [[] /* initial: empty */, [newRow] /* backfill */];
    state.fallbackConvResult = [newRow];

    const { useConversations } = await import("@/hooks/use-conversations");
    const view = renderHook(() => useConversations({ limit: 15 }));

    await waitFor(() => expect(state.channels.some((c) => c.name === "command-center-own")).toBe(true));

    // NO INSERT fired — nothing arms a recovery in the old gated path.
    // Resolve scope → the UNCONDITIONAL backfill must fetch and land the row.
    await act(async () => {
      state.releaseActiveRepo?.();
    });

    await waitFor(
      () => expect(view.result.current.conversations.map((c) => c.id)).toContain("conv-unconditional"),
      { timeout: 3000 },
    );
    expect(warnSilentFallbackMock).not.toHaveBeenCalled();
  });

  it("AC4b: the scope-resolve backfill is a QUIET refetch — loading is never toggled while it is in flight", async () => {
    // The initial fetch returns a row and settles (loading=false). The null→id
    // transition fires the backfill; defer its active-repo call so it stays in
    // flight. A QUIET refetch must NOT flip loading back to true (which would
    // re-enter the rail's !loading-gated empty/error branches and blank/flash
    // the rail). A non-quiet refetch would flip loading=true → this fails.
    const row = makeRow({ id: "existing-row" });
    state.convResultByCall = [[row] /* initial returns the row */];
    state.fallbackConvResult = [row];
    state.deferBackfillActiveRepo = true;

    const { useConversations } = await import("@/hooks/use-conversations");
    const view = renderHook(() => useConversations({ limit: 15 }));

    // Initial fetch settles: row present, loading false.
    await waitFor(() =>
      expect(view.result.current.conversations.map((c) => c.id)).toContain("existing-row"),
    );
    expect(view.result.current.loading).toBe(false);

    // The backfill (call 2) dispatches via the null→id transition effect. Await
    // it deterministically (waitFor, not a bare microtask flush — the effect may
    // need more than one turn to schedule + run), then assert loading stayed
    // false the whole time it was in flight (quiet). A non-quiet refetch would
    // have flipped loading=true synchronously before the deferred await.
    await waitFor(() => expect(state.activeRepoCalls).toBe(2)); // initial + backfill
    expect(view.result.current.loading).toBe(false);

    // Release the backfill; the row stays and loading is still false.
    await act(async () => {
      state.releaseBackfillActiveRepo?.();
    });
    await waitFor(() => expect(view.result.current.loading).toBe(false));
    expect(view.result.current.conversations.map((c) => c.id)).toContain("existing-row");
  });

  it("refetches on the soleur:conversation-created event so a new conversation appears WITHOUT realtime or a reload (deterministic recovery)", async () => {
    // The real-world failure (reproduced in a headless browser, 2026-06-17): a
    // freshly-started conversation's realtime own-channel INSERT is missed
    // because the rail re-subscribes during the new-conversation navigation (the
    // INSERT lands in the pre-SUBSCRIBED window supabase-js never replays) and
    // the mount-time backfills already ran before the row existed. chat-surface
    // emits `soleur:conversation-created` the moment the server assigns the real
    // id; the rail must refetch on it and surface the row — no realtime INSERT,
    // no reload. With the listener absent, no refetch fires and the row never
    // appears (the bug), so this is non-vacuous.
    const existing = makeRow({ id: "conv-existing" });
    const created = makeRow({ id: "conv-created-via-event" });
    state.fallbackConvResult = [existing];

    const { useConversations } = await import("@/hooks/use-conversations");
    const view = renderHook(() => useConversations({ limit: 15 }));
    await waitFor(() =>
      expect(view.result.current.conversations.map((c) => c.id)).toEqual(["conv-existing"]),
    );

    // A new conversation now exists server-side; chat-surface fires the signal.
    // NO own-channel INSERT is delivered to the rail (the missed-realtime case).
    state.fallbackConvResult = [created, existing];
    const { CONVERSATION_CREATED_EVENT } = await import("@/hooks/use-conversations");
    await act(async () => {
      window.dispatchEvent(
        new CustomEvent(CONVERSATION_CREATED_EVENT, {
          detail: { conversationId: "conv-created-via-event" },
        }),
      );
    });
    await waitFor(
      () => expect(view.result.current.conversations.map((c) => c.id)).toContain("conv-created-via-event"),
      { timeout: 3000 },
    );
  });

  it("retries the event refetch until the LAZILY-committed conversation row appears (commit-timing race, #5449 follow-up)", async () => {
    // The real-world race (found via live headless-browser repro, 2026-06-17):
    // the event fires at session_started, but the conversation ROW is created
    // lazily on the first persisted message — slightly LATER. So the FIRST
    // refetch on the event runs before the row is committed and misses it; the
    // bounded retry (keyed on the event's conversationId) must keep refetching
    // until the row appears. Non-vacuous: a single refetch leaves the row absent
    // forever (the bug this enhancement fixes).
    const existing = makeRow({ id: "conv-existing" });
    const late = makeRow({ id: "conv-late-commit" });
    state.fallbackConvResult = [existing]; // row NOT committed yet
    const { useConversations, CONVERSATION_CREATED_EVENT } = await import(
      "@/hooks/use-conversations"
    );
    const view = renderHook(() => useConversations({ limit: 15 }));
    await waitFor(() =>
      expect(view.result.current.conversations.map((c) => c.id)).toEqual(["conv-existing"]),
    );

    // Event fires before the row commits — the first refetch misses it.
    await act(async () => {
      window.dispatchEvent(
        new CustomEvent(CONVERSATION_CREATED_EVENT, {
          detail: { conversationId: "conv-late-commit" },
        }),
      );
      await Promise.resolve();
    });
    expect(view.result.current.conversations.map((c) => c.id)).not.toContain("conv-late-commit");

    // The row commits a beat later; the bounded retry must surface it.
    state.fallbackConvResult = [late, existing];
    await waitFor(
      () => expect(view.result.current.conversations.map((c) => c.id)).toContain("conv-late-commit"),
      { timeout: 5000 },
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
    await waitFor(
      () => expect(view.result.current.conversations.map((c) => c.id)).toContain("conv-bounded"),
      { timeout: 3000 },
    );

    // active-repo calls so far: initial (1) + recovery backfill (2). A bare
    // re-render must NOT trigger another backfill (transition-gated). The exact
    // count is 2 (not 3) because the channel mock never fires the own-channel
    // SUBSCRIBED callback — in production that path adds its own backfill, but
    // this test isolates the SCOPE-RESOLVE backfill. A third call here would be
    // a real defect (an un-gated refetch); do not loosen this assertion.
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
