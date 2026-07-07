import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";

// RED phase for plan 2026-04-29-feat-command-center-conversation-nav.
//
// Contract:
//   useConversations({ limit: N }) MUST thread N to query.limit(N).
//   Default behaviour is unchanged: omitting `limit` keeps the existing
//   query.limit(50) ceiling.
//
// The conversation rail consumes useConversations({ limit: 15 }); failing
// to thread limit through means the rail would either over-fetch (50 rows
// rendered as 15 client-side, wasted bytes + Realtime payloads) or under-
// fetch (if a future bump moves the default below 15). The hook contract
// is the load-bearing seam.

import { makeEnrichedListRpc } from "./helpers/mock-supabase";

const rpcSpy = vi.fn<(name: string, args: Record<string, unknown>) => void>();

function buildConversationRows(count: number) {
  return Array.from({ length: count }, (_, i) => ({
    id: `conv-${i}`,
    user_id: "u1",
    repo_url: "https://github.com/acme/repo",
    status: "active",
    domain_leader: null,
    archived_at: null,
    last_active: new Date().toISOString(),
    created_at: new Date().toISOString(),
  }));
}

function buildSupabaseClient(rows: ReturnType<typeof buildConversationRows>) {
  // The list read now flows through the list_conversations_enriched RPC
  // (migration 125); `p_limit` is threaded into the RPC args (the old
  // `.from("conversations").limit(n)` seam). The `from` throw asserts the
  // hook no longer touches conversations/messages tables for the list fetch.
  const rpc = makeEnrichedListRpc(rows, []);
  return {
    auth: {
      getUser: vi.fn(() =>
        Promise.resolve({ data: { user: { id: "u1" } }, error: null }),
      ),
    },
    rpc: vi.fn((name: string, args: Record<string, unknown>) => {
      rpcSpy(name, args);
      return rpc(name, args);
    }),
    from: vi.fn((table: string) => {
      throw new Error(`unexpected .from("${table}") during list fetch`);
    }),
    channel: vi.fn(() => {
      const ch: Record<string, unknown> = {};
      Object.assign(ch, {
        on: vi.fn(() => ch),
        subscribe: vi.fn(() => ch),
      });
      return ch;
    }),
    removeChannel: vi.fn(),
  };
}

function lastLimitArg(): number | undefined {
  const call = rpcSpy.mock.calls.at(-1);
  return call?.[1]?.p_limit as number | undefined;
}

const { createClientMock } = vi.hoisted(() => ({
  createClientMock: vi.fn(),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: createClientMock,
}));

describe("useConversations({ limit })", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    rpcSpy.mockClear();
    // Repo scope now comes from GET /api/workspace/active-repo (ADR-044),
    // not users.repo_url. Stub it to the same repo the conversation rows
    // carry so the list query is reached.
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: () =>
          Promise.resolve({
            workspaceId: "ws-1",
            repoUrl: "https://github.com/acme/repo",
            repoName: "acme/repo",
            repoStatus: "connected",
            fellBackToSolo: false,
          }),
      }),
    );
  });

  it("threads limit through to the underlying Supabase query", async () => {
    const rows = buildConversationRows(30);
    createClientMock.mockImplementation(() => buildSupabaseClient(rows));

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations({ limit: 15 }));

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(lastLimitArg()).toBe(15);
    expect(result.current.conversations.length).toBeLessThanOrEqual(15);
  });

  it("defaults to limit(50) when limit is omitted", async () => {
    const rows = buildConversationRows(80);
    createClientMock.mockImplementation(() => buildSupabaseClient(rows));

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations());

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(lastLimitArg()).toBe(50);
    expect(result.current.conversations.length).toBeLessThanOrEqual(50);
  });

  it("respects an explicit limit smaller than the default", async () => {
    const rows = buildConversationRows(80);
    createClientMock.mockImplementation(() => buildSupabaseClient(rows));

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations({ limit: 5 }));

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(lastLimitArg()).toBe(5);
    expect(result.current.conversations.length).toBeLessThanOrEqual(5);
  });
});
