import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { enrichConversationFixtures } from "./helpers/mock-supabase";

// Originally RED phase for plan
// 2026-04-22-fix-command-center-stale-conversations-after-repo-swap.
// Updated by plan
// 2026-06-15-fix-conversations-rail-empty-repo-url-source-divergence: the
// repo scope source moved from the deprecated `users.repo_url` column to
// GET /api/workspace/active-repo (workspaces.repo_url, ADR-044). The list-
// scoping contract below is unchanged in shape; only its SOURCE changed.
//
// Contract:
//   useConversations() must scope the list query to the user's CURRENT repo,
//   read from /api/workspace/active-repo. Pre-swap conversations (different
//   repo_url) must not render. When the route returns repoUrl=null
//   (disconnected), the hook returns an empty list without issuing the main
//   list query.
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
    // Scope is now the p_repo_url arg (was the `.eq("repo_url")` predicate); we
    // capture it into state.capturedEq so the scoping assertion is unchanged,
    // and return only that repo's conversations enriched with the message
    // snippets — mirroring the RLS-preserving RPC's behavior.
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
      return buildConversationsBuilder();
    },
    channel: mockChannel,
    removeChannel: vi.fn(),
  }),
}));

// --- Tests ------------------------------------------------------------------

describe("useConversations — repo scoping (source: /api/workspace/active-repo)", () => {
  beforeEach(() => {
    resetState();
    mockChannel.mockClear();
    vi.restoreAllMocks();
    // Repo scope now comes from GET /api/workspace/active-repo (ADR-044).
    // Resolve `repoUrl` lazily from state.currentRepoUrl so each test can set
    // it before renderHook.
    vi.stubGlobal(
      "fetch",
      vi.fn().mockImplementation(() =>
        Promise.resolve({
          ok: true,
          json: () =>
            Promise.resolve({
              workspaceId: "ws-1",
              repoUrl: state.currentRepoUrl,
              repoName: null,
              repoStatus: state.currentRepoUrl ? "connected" : "not_connected",
              fellBackToSolo: false,
            }),
        }),
      ),
    );
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

  // NOTE: The former "refetches when users.repo_url changes in another tab"
  // test was removed with plan
  // 2026-06-15-fix-conversations-rail-empty-repo-url-source-divergence. The
  // cross-tab `users` UPDATE realtime channel was deleted because the hook no
  // longer reads `users.repo_url` — repo scope comes from
  // /api/workspace/active-repo. A workspace switch is a hard navigation to
  // /dashboard (org-switcher remounts → fetchConversations re-runs), so there
  // is no resubscribe gap to cover and nothing to refetch on a `users` event.
});
