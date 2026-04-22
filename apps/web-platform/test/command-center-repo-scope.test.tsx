import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor, act } from "@testing-library/react";

// RED phase for plan 2026-04-22-fix-command-center-stale-conversations-after-repo-swap.
//
// Contract:
//   useConversations() must scope the list query to the user's CURRENT
//   users.repo_url. Pre-swap conversations (different repo_url) must not
//   render. When users.repo_url is null (disconnected), the hook returns
//   an empty list without issuing the main list query.
//
//   The Realtime channel for conversations stays on user_id only (realtime-js
//   single-column filter limitation); cross-repo payloads must be dropped in
//   the callback by comparing payload.new.repo_url to currentRepoUrl.

// --- Supabase mock plumbing -------------------------------------------------

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => ({
    names: {},
    loading: false,
    error: null,
  }),
}));

type Row = Record<string, unknown>;

interface MockState {
  currentRepoUrl: string | null;
  conversationsByRepo: Record<string, Row[]>;
  messages: Row[];
  capturedEq: Array<[string, unknown]>;
}

const state: MockState = {
  currentRepoUrl: null,
  conversationsByRepo: {},
  messages: [],
  capturedEq: [],
};

function resetState() {
  state.currentRepoUrl = null;
  state.conversationsByRepo = {};
  state.messages = [];
  state.capturedEq = [];
}

function buildConversationsBuilder() {
  const predicates: Array<[string, unknown]> = [];
  const builder: Record<string, unknown> = {
    select: vi.fn(() => builder),
    eq: vi.fn((col: string, val: unknown) => {
      predicates.push([col, val]);
      state.capturedEq.push([col, val]);
      return builder;
    }),
    in: vi.fn(() => builder),
    is: vi.fn(() => builder),
    not: vi.fn(() => builder),
    order: vi.fn(() => builder),
    limit: vi.fn((_n: number) => {
      const repoPred = predicates.find(([c]) => c === "repo_url");
      // If no repo_url predicate was applied, the list is NOT scoped —
      // return everything across repos (this is the bug we're fixing).
      let rows: Row[];
      if (!repoPred) {
        rows = Object.values(state.conversationsByRepo).flat();
      } else {
        rows = state.conversationsByRepo[String(repoPred[1])] ?? [];
      }
      return Promise.resolve({ data: rows, error: null });
    }),
    then: (onfulfilled: (value: unknown) => unknown) =>
      Promise.resolve({ data: [], error: null }).then(onfulfilled),
  };
  return builder;
}

function buildMessagesBuilder() {
  const builder: Record<string, unknown> = {
    select: vi.fn(() => builder),
    in: vi.fn(() => builder),
    order: vi.fn(() =>
      Promise.resolve({ data: state.messages, error: null }),
    ),
    then: (onfulfilled: (value: unknown) => unknown) =>
      Promise.resolve({ data: state.messages, error: null }).then(onfulfilled),
  };
  return builder;
}

function buildUsersBuilder() {
  const builder: Record<string, unknown> = {
    select: vi.fn(() => builder),
    eq: vi.fn(() => builder),
    single: vi.fn(() =>
      Promise.resolve({
        data: { repo_url: state.currentRepoUrl },
        error: null,
      }),
    ),
    maybeSingle: vi.fn(() =>
      Promise.resolve({
        data: { repo_url: state.currentRepoUrl },
        error: null,
      }),
    ),
  };
  return builder;
}

const mockChannel = vi.fn().mockReturnValue({
  on: vi.fn().mockReturnThis(),
  subscribe: vi.fn().mockReturnValue({ unsubscribe: vi.fn() }),
});

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === "conversations") return buildConversationsBuilder();
      if (table === "messages") return buildMessagesBuilder();
      if (table === "users") return buildUsersBuilder();
      return buildConversationsBuilder();
    },
    channel: mockChannel,
    removeChannel: vi.fn(),
  }),
}));

// --- Tests ------------------------------------------------------------------

describe("useConversations — repo_url scoping", () => {
  beforeEach(() => {
    resetState();
    mockChannel.mockClear();
  });

  it("returns ONLY the conversations matching the user's current repo_url", async () => {
    state.currentRepoUrl = "https://github.com/acme/new";
    state.conversationsByRepo = {
      "https://github.com/acme/old": [
        {
          id: "conv-old",
          user_id: "user-1",
          repo_url: "https://github.com/acme/old",
          domain_leader: null,
          session_id: null,
          status: "completed",
          total_cost_usd: 0,
          input_tokens: 0,
          output_tokens: 0,
          last_active: new Date(Date.now() - 10_000).toISOString(),
          created_at: new Date(Date.now() - 20_000).toISOString(),
          archived_at: null,
        },
      ],
      "https://github.com/acme/new": [
        {
          id: "conv-new",
          user_id: "user-1",
          repo_url: "https://github.com/acme/new",
          domain_leader: null,
          session_id: null,
          status: "active",
          total_cost_usd: 0,
          input_tokens: 0,
          output_tokens: 0,
          last_active: new Date(Date.now() - 1_000).toISOString(),
          created_at: new Date(Date.now() - 2_000).toISOString(),
          archived_at: null,
        },
      ],
    };

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Pin exact post-state per cq-mutation-assertions-pin-exact-post-state.
    expect(result.current.conversations.length).toBe(1);
    expect(result.current.conversations[0]?.id).toBe("conv-new");

    // The list query MUST have an .eq("repo_url", current) predicate —
    // this is the load-bearing claim of the plan.
    const repoEq = state.capturedEq.find(([c]) => c === "repo_url");
    expect(repoEq?.[1]).toBe("https://github.com/acme/new");
  });

  it("returns an empty list when the user's repo_url is null (disconnected)", async () => {
    state.currentRepoUrl = null;
    state.conversationsByRepo = {
      "https://github.com/acme/old": [
        {
          id: "conv-orphan",
          user_id: "user-1",
          repo_url: "https://github.com/acme/old",
          domain_leader: null,
          session_id: null,
          status: "completed",
          total_cost_usd: 0,
          input_tokens: 0,
          output_tokens: 0,
          last_active: new Date(Date.now() - 10_000).toISOString(),
          created_at: new Date(Date.now() - 20_000).toISOString(),
          archived_at: null,
        },
      ],
    };

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.conversations.length).toBe(0);
  });

  it("refetches and re-scopes when users.repo_url changes in another tab (race R-C)", async () => {
    state.currentRepoUrl = "https://github.com/acme/first";
    state.conversationsByRepo = {
      "https://github.com/acme/first": [
        {
          id: "conv-first",
          user_id: "user-1",
          repo_url: "https://github.com/acme/first",
          domain_leader: null,
          session_id: null,
          status: "active",
          total_cost_usd: 0,
          input_tokens: 0,
          output_tokens: 0,
          last_active: new Date().toISOString(),
          created_at: new Date(Date.now() - 2_000).toISOString(),
          archived_at: null,
        },
      ],
      "https://github.com/acme/second": [
        {
          id: "conv-second",
          user_id: "user-1",
          repo_url: "https://github.com/acme/second",
          domain_leader: null,
          session_id: null,
          status: "active",
          total_cost_usd: 0,
          input_tokens: 0,
          output_tokens: 0,
          last_active: new Date().toISOString(),
          created_at: new Date().toISOString(),
          archived_at: null,
        },
      ],
    };

    // Capture the users-channel UPDATE callback so the test can fire it.
    let usersCallback:
      | ((payload: { new: { repo_url: string | null } }) => void)
      | null = null;

    mockChannel.mockImplementation((name: string) => {
      const ch: Record<string, unknown> = {
        on: vi.fn((event: string, cfg: { table: string }, cb: unknown) => {
          if (cfg.table === "users") {
            usersCallback = cb as (p: {
              new: { repo_url: string | null };
            }) => void;
          }
          return ch;
        }),
        subscribe: vi.fn().mockReturnValue({ unsubscribe: vi.fn() }),
      };
      return ch;
    });

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations());

    await waitFor(() => {
      expect(result.current.conversations[0]?.id).toBe("conv-first");
    });

    // Another tab switched repos: users.repo_url changed.
    state.currentRepoUrl = "https://github.com/acme/second";

    await act(async () => {
      usersCallback?.({ new: { repo_url: "https://github.com/acme/second" } });
    });

    await waitFor(() => {
      expect(result.current.conversations[0]?.id).toBe("conv-second");
    });
  });
});
