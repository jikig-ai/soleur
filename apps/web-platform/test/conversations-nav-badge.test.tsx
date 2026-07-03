import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";

// Two concerns in this file:
//  1. fetchConversationAttentionCount builds the correctly-scoped count query
//     (mock supabase) — this is the load-bearing "count matches the list" logic.
//  2. The badge gates on the active repo and honours the never-a-false-0 contract
//     (mock swr).

const useSWRMock = vi.fn();
vi.mock("swr", async (importOriginal) => {
  const actual = await importOriginal<typeof import("swr")>();
  return { ...actual, default: (...args: unknown[]) => useSWRMock(...args) };
});

const eqCalls: Array<[string, unknown]> = [];
const isCalls: Array<[string, unknown]> = [];
const inCalls: Array<[string, unknown]> = [];
let queryResult: { count: number | null; error: unknown } = {
  count: 0,
  error: null,
};
let mockUser: { id: string } | null = { id: "user-1" };

function makeQuery() {
  const q: Record<string, unknown> = {
    select: vi.fn(() => q),
    eq: vi.fn((c: string, v: unknown) => {
      eqCalls.push([c, v]);
      return q;
    }),
    is: vi.fn((c: string, v: unknown) => {
      isCalls.push([c, v]);
      return q;
    }),
    in: vi.fn((c: string, v: unknown) => {
      inCalls.push([c, v]);
      return q;
    }),
    then: (resolve: (r: typeof queryResult) => void) => resolve(queryResult),
  };
  return q;
}

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getUser: () => Promise.resolve({ data: { user: mockUser } }),
    },
    from: () => makeQuery(),
  }),
}));

beforeEach(() => {
  useSWRMock.mockReset();
  eqCalls.length = 0;
  isCalls.length = 0;
  inCalls.length = 0;
  queryResult = { count: 0, error: null };
  mockUser = { id: "user-1" };
});
afterEach(() => cleanup());

describe("fetchConversationAttentionCount", () => {
  it("scopes to active repo + workspace + not-archived + attention statuses", async () => {
    queryResult = { count: 4, error: null };
    const { fetchConversationAttentionCount } = await import(
      "@/components/dashboard/conversations-nav-badge"
    );
    const n = await fetchConversationAttentionCount([
      "dashboard:conversation-attention-count",
      "https://github.com/acme/repo",
      "ws-123",
    ]);
    expect(n).toBe(4);
    expect(eqCalls).toContainEqual(["repo_url", "https://github.com/acme/repo"]);
    expect(eqCalls).toContainEqual(["workspace_id", "ws-123"]);
    expect(isCalls).toContainEqual(["archived_at", null]);
    expect(inCalls).toContainEqual([
      "status",
      ["waiting_for_user", "failed"],
    ]);
  });

  it("throws on query error so the badge omits (never a false 0)", async () => {
    queryResult = { count: null, error: { message: "boom" } };
    const { fetchConversationAttentionCount } = await import(
      "@/components/dashboard/conversations-nav-badge"
    );
    await expect(
      fetchConversationAttentionCount([
        "dashboard:conversation-attention-count",
        "r",
        "w",
      ]),
    ).rejects.toThrow(/conversation attention count/);
  });
});

describe("ConversationsNavBadge", () => {
  // useSWR is called twice: (1) active-repo, (2) the count. Route by key.
  function wireSWR(opts: {
    activeRepo: { repoUrl?: string | null; workspaceId?: string | null };
    count?: number;
    countError?: unknown;
    countUndefined?: boolean;
  }) {
    useSWRMock.mockImplementation((key: unknown) => {
      if (Array.isArray(key) && key[0] === "/api/workspace/active-repo") {
        return { data: opts.activeRepo, error: undefined };
      }
      // Count hook. A null key means SWR does not fetch → data stays undefined
      // (this is the active-repo gate). Simulate that faithfully.
      if (key == null) return { data: undefined, error: undefined };
      return {
        data: opts.countUndefined ? undefined : opts.count,
        error: opts.countError,
      };
    });
  }

  async function render_() {
    const { ConversationsNavBadge } = await import(
      "@/components/dashboard/conversations-nav-badge"
    );
    return render(<ConversationsNavBadge collapsed={false} />);
  }

  it("renders the count once the active repo resolves", async () => {
    wireSWR({
      activeRepo: { repoUrl: "https://github.com/acme/repo", workspaceId: "ws-1" },
      count: 2,
    });
    await render_();
    const badge = screen.getByTestId("dashboard-nav-badge");
    expect(badge).toHaveTextContent("2");
    expect(badge).toHaveAccessibleName("2 conversations need your attention");
  });

  it("gates (no badge) when no active repo is connected", async () => {
    wireSWR({ activeRepo: { repoUrl: null, workspaceId: null }, count: 5 });
    await render_();
    // The count key is null → hook returns null → omit, even though a stale
    // count value is present in the mock.
    expect(
      screen.queryByTestId("dashboard-nav-badge"),
    ).not.toBeInTheDocument();
  });

  it("omits at count 0", async () => {
    wireSWR({
      activeRepo: { repoUrl: "r", workspaceId: "w" },
      count: 0,
    });
    await render_();
    expect(
      screen.queryByTestId("dashboard-nav-badge"),
    ).not.toBeInTheDocument();
  });

  it("omits (never a false 0) on a cold count error", async () => {
    wireSWR({
      activeRepo: { repoUrl: "r", workspaceId: "w" },
      countUndefined: true,
      countError: new Error("500"),
    });
    await render_();
    expect(
      screen.queryByTestId("dashboard-nav-badge"),
    ).not.toBeInTheDocument();
  });
});
