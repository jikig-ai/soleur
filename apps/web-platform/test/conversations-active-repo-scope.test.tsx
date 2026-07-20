import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { enrichConversationFixtures } from "./helpers/mock-supabase";

// RED→GREEN regression for plan
// 2026-06-15-fix-conversations-rail-empty-repo-url-source-divergence.
//
// Bug: the Recent Conversations rail showed the empty state while the user was
// in an active conversation. Root cause: `useConversations` scoped the list by
// the DEPRECATED `users.repo_url` column, while the server stamps conversations
// with `workspaces.repo_url` (ADR-044, #4543). For a joined workspace member
// (whose own `users.repo_url` is empty) the two diverge, so the client filtered
// out every conversation and hard-returned `setConversations([])`.
//
// Contract: the hook MUST derive its repo scope from
// `GET /api/workspace/active-repo` (which resolves `workspaces.repo_url` via the
// active workspace, ADR-044), NOT from `users.repo_url`.
//
// This test is the discriminating RED: the active-repo route returns a repoUrl
// while `users.repo_url` is null (the joined-member scenario). Against the
// pre-fix hook (reads `users.repo_url` → null → empty) it FAILS; against the
// fixed hook (reads the route → repoUrl → lists the row) it PASSES.

const ACTIVE_REPO_URL = "https://github.com/acme/active";

type Row = Record<string, unknown>;

interface MockState {
  // Simulated DEPRECATED per-user column: null for a joined member. The fixed
  // hook must NOT read this; if it does, the test goes RED.
  usersRepoUrl: string | null;
  conversationsByRepo: Record<string, Row[]>;
  messages: Row[];
  capturedEq: Array<[string, unknown]>;
}

const state: MockState = {
  usersRepoUrl: null,
  conversationsByRepo: {},
  messages: [],
  capturedEq: [],
};

function resetState() {
  state.usersRepoUrl = null;
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
    limit: vi.fn(() => {
      const repoPred = predicates.find(([c]) => c === "repo_url");
      // No repo_url predicate → not scoped → return everything (the bug shape).
      const rows = !repoPred
        ? Object.values(state.conversationsByRepo).flat()
        : (state.conversationsByRepo[String(repoPred[1])] ?? []);
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
    order: vi.fn(() => Promise.resolve({ data: state.messages, error: null })),
    then: (onfulfilled: (value: unknown) => unknown) =>
      Promise.resolve({ data: state.messages, error: null }).then(onfulfilled),
  };
  return builder;
}

// `users` builder kept ONLY so a pre-fix hook can read it and go RED. The fixed
// hook never calls `.from("users")` for repo scoping (AC1/AC8).
function buildUsersBuilder() {
  const builder: Record<string, unknown> = {
    select: vi.fn(() => builder),
    eq: vi.fn(() => builder),
    maybeSingle: vi.fn(() =>
      Promise.resolve({ data: { repo_url: state.usersRepoUrl }, error: null }),
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
    // The list read flows through list_conversations_enriched (migration 125).
    // Scope is now the p_repo_url arg; capture it into state.capturedEq so the
    // scoping assertions are unchanged, and return only that repo's rows.
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name !== "list_conversations_enriched") {
        return Promise.resolve({ data: null, error: { message: `unexpected rpc: ${name}` } });
      }
      const repo = (args.p_repo_url as string | null) ?? null;
      state.capturedEq.push(["repo_url", repo]);
      const rows = repo == null ? [] : (state.conversationsByRepo[repo] ?? []);
      return Promise.resolve({
        data: enrichConversationFixtures(
          rows as { id: string }[],
          state.messages as { conversation_id: string; role: string; content: string; leader_id?: string | null; created_at?: string }[],
        ),
        error: null,
      });
    },
    from: (table: string) => {
      if (table === "conversations") return buildConversationsBuilder();
      if (table === "messages") return buildMessagesBuilder();
      if (table === "users") return buildUsersBuilder();
      // workspace_members must NOT be read after the fix; if a pre-fix hook
      // reads it, return null so the channel path stays inert.
      if (table === "workspace_members") {
        const b: Record<string, unknown> = {
          select: vi.fn(() => b),
          eq: vi.fn(() => b),
          maybeSingle: vi.fn(() => Promise.resolve({ data: null, error: null })),
        };
        return b;
      }
      return buildConversationsBuilder();
    },
    channel: mockChannel,
    removeChannel: vi.fn(),
  }),
}));

function makeConversationRow(repoUrl: string): Row {
  return {
    id: "conv-active",
    user_id: "user-1",
    repo_url: repoUrl,
    domain_leader: null,
    session_id: null,
    status: "active",
    total_cost_usd: 0,
    input_tokens: 0,
    output_tokens: 0,
    last_active: new Date(Date.now() - 1_000).toISOString(),
    created_at: new Date(Date.now() - 2_000).toISOString(),
    archived_at: null,
  };
}

describe("useConversations — repo scope from /api/workspace/active-repo (ADR-044)", () => {
  beforeEach(() => {
    resetState();
    mockChannel.mockClear();
    vi.restoreAllMocks();
  });

  it("surfaces the active conversation when the route returns a repoUrl even though users.repo_url is null (joined member)", async () => {
    // Joined-member divergence: own users.repo_url is empty…
    state.usersRepoUrl = null;
    // …but the active workspace's repo (via the route) is connected, and the
    // conversation row was stamped with that workspace repo_url server-side.
    state.conversationsByRepo = {
      [ACTIVE_REPO_URL]: [makeConversationRow(ACTIVE_REPO_URL)],
    };

    const fetchSpy = vi.fn().mockResolvedValue({
      ok: true,
      json: () =>
        Promise.resolve({
          workspaceId: "ws-1",
          repoUrl: ACTIVE_REPO_URL,
          repoName: "acme/active",
          repoStatus: "connected",
          fellBackToSolo: false,
        }),
    });
    vi.stubGlobal("fetch", fetchSpy);

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Core assertion: the rail is populated (NOT the empty state).
    expect(result.current.conversations.length).toBe(1);
    expect(result.current.conversations[0]?.id).toBe("conv-active");

    // The list query scoped to the ROUTE's repoUrl, not users.repo_url.
    const repoEq = state.capturedEq.find(([c]) => c === "repo_url");
    expect(repoEq?.[1]).toBe(ACTIVE_REPO_URL);

    // And it actually asked the canonical route.
    expect(fetchSpy).toHaveBeenCalledWith("/api/workspace/active-repo");
  });

  it("shows the empty state when the route reports no connected repo (repoUrl null)", async () => {
    // Even with a stale users.repo_url present, a null route repoUrl wins:
    // the user has no connected repo → empty rail (correct behavior).
    state.usersRepoUrl = "https://github.com/acme/stale";
    state.conversationsByRepo = {
      "https://github.com/acme/stale": [
        makeConversationRow("https://github.com/acme/stale"),
      ],
    };

    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: () =>
          Promise.resolve({
            workspaceId: "ws-1",
            repoUrl: null,
            repoName: null,
            repoStatus: "not_connected",
            fellBackToSolo: false,
          }),
      }),
    );

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.conversations.length).toBe(0);
    // No list query should have been scoped by the stale users.repo_url.
    const repoEq = state.capturedEq.find(([c]) => c === "repo_url");
    expect(repoEq).toBeUndefined();
  });

  it("surfaces an error (no silent empty flash) when the route fetch fails", async () => {
    state.usersRepoUrl = null;
    state.conversationsByRepo = {
      [ACTIVE_REPO_URL]: [makeConversationRow(ACTIVE_REPO_URL)],
    };

    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: false, status: 503, json: () => Promise.resolve({}) }),
    );

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.error).toBe("Failed to resolve the active repository");
    expect(result.current.conversations.length).toBe(0);
  });
});
