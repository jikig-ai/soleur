import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor, act } from "@testing-library/react";
import type { Conversation } from "@/lib/types";
import { enrichConversationFixtures } from "./helpers/mock-supabase";

// RED→GREEN regression for plan
// 2026-06-15-fix-active-conversation-missing-from-rail.
//
// Bug (regression): an active/in-progress conversation does not appear in the
// Recent Conversations rail. #5317 fixed the repo_url-SOURCE divergence; this is
// a SECOND, independent defect: the rail's data hook (`useConversations`) learns
// about conversations only via a mount-time fetch + Supabase Realtime UPDATE
// events. There is NO INSERT subscription, so a conversation created AFTER the
// rail mounts on an empty list is never added — the rail stays "No conversations
// yet." until a manual remount/refetch. Per ADR-047 the rail portals outside the
// Next.js swap region, so it stays mounted and never re-runs its mount effect.
//
// Contract (this fix):
//  1. A scoped Realtime INSERT subscription prepends a freshly-created
//     conversation matching the current repo_url + workspace_id scope.
//  2. A bounded `SUBSCRIBED`-status backfill refetch closes the
//     reconnection/initial-load gap (at-least-once delivery; no replay).
//  3. INSERT and UPDATE share ONE `shouldDropForScope` guard (repo_url +
//     visibility + archive) and ONE `deriveRailTitle` helper (system branch).
//  4. The INSERT reducer is fill-only (never downgrades an enriched row) and
//     de-duped + truncated to `limit`.

const ACTIVE_REPO_URL = "https://github.com/acme/active";
const WS_ID = "ws-1";

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

// Mutable conversation result so the SUBSCRIBED backfill refetch can return a
// different row set from the mount-time fetch.
const state: {
  rows: Conversation[];
  channels: ChannelMock[];
  activeRepoFetches: number;
} = { rows: [], channels: [], activeRepoFetches: 0 };

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

function buildConversationsChain() {
  const chain: Record<string, unknown> = {};
  Object.assign(chain, {
    select: vi.fn(() => chain),
    eq: vi.fn(() => chain),
    is: vi.fn(() => chain),
    not: vi.fn(() => chain),
    order: vi.fn(() => chain),
    limit: vi.fn(() => Promise.resolve({ data: state.rows, error: null })),
  });
  return chain;
}

function buildMessagesChain() {
  const chain: Record<string, unknown> = {};
  Object.assign(chain, {
    select: vi.fn(() => chain),
    in: vi.fn(() => chain),
    order: vi.fn(() => Promise.resolve({ data: [], error: null })),
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
    // The list read now flows through list_conversations_enriched (migration
    // 125). state.rows carries no message fixtures here, so the snippet fields
    // are null and titles derive from domain_leader exactly as the old
    // messages-chain (which returned []) produced them.
    rpc: vi.fn((name: string) => {
      if (name !== "list_conversations_enriched") {
        return Promise.resolve({ data: null, error: { message: `unexpected rpc: ${name}` } });
      }
      return Promise.resolve({ data: enrichConversationFixtures(state.rows, []), error: null });
    }),
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

function insertHandler(channelName: string): RealtimeHandler["cb"] {
  const ch = lastChannel(channelName);
  const h = ch.handlers.find((x) => x.event === "INSERT");
  if (!h) throw new Error(`no INSERT handler on ${channelName}`);
  return h.cb;
}

async function mountEmptyRail() {
  const { useConversations } = await import("@/hooks/use-conversations");
  const view = renderHook(() => useConversations({ limit: 15 }));
  await waitFor(() => expect(view.result.current.loading).toBe(false));
  return view;
}

beforeEach(() => {
  vi.clearAllMocks();
  state.rows = [];
  state.channels = [];
  state.activeRepoFetches = 0;
  vi.stubGlobal(
    "fetch",
    vi.fn((url: string) => {
      if (url === "/api/workspace/active-repo") state.activeRepoFetches += 1;
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            workspaceId: WS_ID,
            repoUrl: ACTIVE_REPO_URL,
            repoName: "acme/active",
            repoStatus: "connected",
            fellBackToSolo: false,
          }),
      });
    }),
  );
});

describe("useConversations — Realtime INSERT + SUBSCRIBED backfill", () => {
  it("AC1: a scope-matching INSERT after an empty mount appears in the rail", async () => {
    const { result } = await mountEmptyRail();
    expect(result.current.conversations.length).toBe(0);

    act(() => {
      insertHandler("command-center-own")({
        new: makeRow({ id: "conv-new", domain_leader: "cto" }),
        eventType: "INSERT",
      });
    });

    expect(result.current.conversations.map((c) => c.id)).toContain("conv-new");
  });

  it("AC2: INSERT with a mismatched repo_url is dropped", async () => {
    const { result } = await mountEmptyRail();
    act(() => {
      insertHandler("command-center-own")({
        new: makeRow({ id: "foreign", repo_url: "https://github.com/evil/other" }),
        eventType: "INSERT",
      });
    });
    expect(result.current.conversations.length).toBe(0);
  });

  it("AC2: INSERT on the shared channel with visibility !== 'workspace' is dropped", async () => {
    const { result } = await mountEmptyRail();
    act(() => {
      insertHandler("command-center-shared")({
        new: makeRow({ id: "priv", visibility: "private" }),
        eventType: "INSERT",
      });
    });
    expect(result.current.conversations.length).toBe(0);
  });

  it("AC2: a shared-channel INSERT with visibility 'workspace' is accepted", async () => {
    const { result } = await mountEmptyRail();
    act(() => {
      insertHandler("command-center-shared")({
        new: makeRow({ id: "shared-1", visibility: "workspace" }),
        eventType: "INSERT",
      });
    });
    expect(result.current.conversations.map((c) => c.id)).toContain("shared-1");
  });

  it("AC2: INSERT with a mismatched workspace_id (same repo) is dropped", async () => {
    // Owner-with-two-same-repo-workspaces case: the own channel filters only on
    // user_id, so a conversation created in workspace B (same repo_url) must NOT
    // surface in the workspace-A rail. The guard scopes by workspace_id too.
    const { result } = await mountEmptyRail();
    act(() => {
      insertHandler("command-center-own")({
        new: makeRow({ id: "ws-b", workspace_id: "ws-other" }),
        eventType: "INSERT",
      });
    });
    expect(result.current.conversations.length).toBe(0);
  });

  it("AC2: an INSERT already archived is dropped when archiveFilter is 'active'", async () => {
    const { result } = await mountEmptyRail();
    act(() => {
      insertHandler("command-center-own")({
        new: makeRow({ id: "arch", archived_at: new Date().toISOString() }),
        eventType: "INSERT",
      });
    });
    expect(result.current.conversations.length).toBe(0);
  });

  it("AC3 (fill-only): a placeholder INSERT does not downgrade an already-enriched row", async () => {
    // Mount with an enriched row whose title is provably NOT the placeholder
    // default. domain_leader "cto" → the fetch path derives "<leader>
    // conversation" (a non-"Untitled" title); a placeholder INSERT for the same
    // id carries domain_leader: null → would derive "Untitled conversation". So
    // if the reducer wrongly overwrote on id-collision, the title would change.
    // Asserting before.title !== "Untitled conversation" makes this non-vacuous.
    state.rows = [makeRow({ id: "conv-x", domain_leader: "cto" })];
    const { useConversations } = await import("@/hooks/use-conversations");
    const view = renderHook(() => useConversations({ limit: 15 }));
    await waitFor(() => expect(view.result.current.loading).toBe(false));
    const before = view.result.current.conversations.find((c) => c.id === "conv-x");
    expect(before).toBeDefined();
    expect(before?.title).not.toBe("Untitled conversation"); // non-vacuity guard

    act(() => {
      insertHandler("command-center-own")({
        new: makeRow({ id: "conv-x", domain_leader: null }),
        eventType: "INSERT",
      });
    });

    const after = view.result.current.conversations.filter((c) => c.id === "conv-x");
    expect(after).toHaveLength(1); // de-dup: no duplicate row
    expect(after[0]?.title).toBe(before?.title); // fill-only: enriched title preserved
  });

  it("AC3b (system title): an INSERT for a system conversation reads 'Project Analysis'", async () => {
    const { result } = await mountEmptyRail();
    act(() => {
      insertHandler("command-center-own")({
        new: makeRow({ id: "sys-1", domain_leader: "system" as Conversation["domain_leader"] }),
        eventType: "INSERT",
      });
    });
    const row = result.current.conversations.find((c) => c.id === "sys-1");
    expect(row?.title).toBe("Project Analysis");
  });

  it("AC4 (limit): a burst of INSERTs never exceeds the hook limit, most-recent-first", async () => {
    const { result } = await mountEmptyRail();
    act(() => {
      const cb = insertHandler("command-center-own");
      for (let i = 0; i < 20; i += 1) {
        cb({ new: makeRow({ id: `burst-${i}` }), eventType: "INSERT" });
      }
    });
    expect(result.current.conversations.length).toBe(15);
    // Last INSERT is the most recent → at the head.
    expect(result.current.conversations[0]?.id).toBe("burst-19");
  });

  it("AC5 (SUBSCRIBED backfill, bounded): one extra fetch on SUBSCRIBED, none on re-render", async () => {
    const { rerender } = await mountEmptyRail();
    const afterMount = state.activeRepoFetches;
    expect(afterMount).toBeGreaterThanOrEqual(1);

    await act(async () => {
      lastChannel("command-center-own").statusCb?.("SUBSCRIBED");
    });
    await waitFor(() =>
      expect(state.activeRepoFetches).toBe(afterMount + 1),
    );

    // A re-render must NOT trigger another backfill.
    rerender();
    expect(state.activeRepoFetches).toBe(afterMount + 1);
  });
});
