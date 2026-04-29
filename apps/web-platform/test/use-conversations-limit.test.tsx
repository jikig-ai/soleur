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

const limitSpy = vi.fn<(n: number) => void>();

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

function buildConversationsChain(rows: ReturnType<typeof buildConversationRows>) {
  const chain: Record<string, unknown> = {};
  Object.assign(chain, {
    select: vi.fn(() => chain),
    eq: vi.fn(() => chain),
    is: vi.fn(() => chain),
    not: vi.fn(() => chain),
    order: vi.fn(() => chain),
    limit: vi.fn((n: number) => {
      limitSpy(n);
      return Promise.resolve({ data: rows.slice(0, n), error: null });
    }),
  });
  return chain;
}

function buildUsersChain() {
  const chain: Record<string, unknown> = {};
  Object.assign(chain, {
    select: vi.fn(() => chain),
    eq: vi.fn(() => chain),
    maybeSingle: vi.fn(() =>
      Promise.resolve({
        data: { repo_url: "https://github.com/acme/repo" },
        error: null,
      }),
    ),
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

function buildSupabaseClient(rows: ReturnType<typeof buildConversationRows>) {
  return {
    auth: {
      getUser: vi.fn(() =>
        Promise.resolve({ data: { user: { id: "u1" } }, error: null }),
      ),
    },
    from: vi.fn((table: string) => {
      if (table === "users") return buildUsersChain();
      if (table === "conversations") return buildConversationsChain(rows);
      if (table === "messages") return buildMessagesChain();
      throw new Error(`unexpected table: ${table}`);
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

const { createClientMock } = vi.hoisted(() => ({
  createClientMock: vi.fn(),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: createClientMock,
}));

vi.mock("@/lib/repo-url", () => ({
  normalizeRepoUrl: (s: string | null | undefined) => (s ?? "").trim(),
}));

describe("useConversations({ limit })", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    limitSpy.mockClear();
  });

  it("threads limit through to the underlying Supabase query", async () => {
    const rows = buildConversationRows(30);
    createClientMock.mockImplementation(() => buildSupabaseClient(rows));

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations({ limit: 15 }));

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(limitSpy).toHaveBeenCalledWith(15);
    expect(result.current.conversations.length).toBeLessThanOrEqual(15);
  });

  it("defaults to limit(50) when limit is omitted", async () => {
    const rows = buildConversationRows(80);
    createClientMock.mockImplementation(() => buildSupabaseClient(rows));

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations());

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(limitSpy).toHaveBeenCalledWith(50);
    expect(result.current.conversations.length).toBeLessThanOrEqual(50);
  });

  it("respects an explicit limit smaller than the default", async () => {
    const rows = buildConversationRows(80);
    createClientMock.mockImplementation(() => buildSupabaseClient(rows));

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations({ limit: 5 }));

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(limitSpy).toHaveBeenCalledWith(5);
    expect(result.current.conversations.length).toBeLessThanOrEqual(5);
  });
});
