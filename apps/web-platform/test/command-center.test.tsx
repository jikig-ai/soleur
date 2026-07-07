import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { SwrTestProvider } from "./helpers/swr-wrapper";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { buildSupabaseQueryBuilder } from "./mocks/supabase-query-builder";
import { makeEnrichedListRpc } from "./helpers/mock-supabase";

// Mock next/navigation — stable reference prevents useEffect re-fires
const mockPush = vi.fn();
const mockRouter = { push: mockPush };
vi.mock("next/navigation", () => ({
  useRouter: () => mockRouter,
  usePathname: () => "/dashboard",
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
}));

// Mock conversation data
const mockConversations = [
  {
    id: "conv-1",
    user_id: "user-1",
    domain_leader: "cto",
    session_id: null,
    status: "waiting_for_user" as const,
    total_cost_usd: 0,
    input_tokens: 0,
    output_tokens: 0,
    last_active: new Date(Date.now() - 2 * 60000).toISOString(), // 2m ago
    created_at: new Date(Date.now() - 3600000).toISOString(),
    archived_at: null,
  },
  {
    id: "conv-2",
    user_id: "user-1",
    domain_leader: "cmo",
    session_id: null,
    status: "active" as const,
    total_cost_usd: 0,
    input_tokens: 0,
    output_tokens: 0,
    last_active: new Date(Date.now() - 15 * 60000).toISOString(), // 15m ago
    created_at: new Date(Date.now() - 7200000).toISOString(),
    archived_at: null,
  },
  {
    id: "conv-3",
    user_id: "user-1",
    domain_leader: "cfo",
    session_id: null,
    status: "completed" as const,
    total_cost_usd: 0,
    input_tokens: 0,
    output_tokens: 0,
    last_active: new Date(Date.now() - 86400000).toISOString(), // 1d ago
    created_at: new Date(Date.now() - 172800000).toISOString(),
    archived_at: null,
  },
];

const mockMessages = [
  {
    conversation_id: "conv-1",
    role: "user",
    content: "Review PR #1742: WebSocket validation and error logging",
    leader_id: null,
    created_at: new Date(Date.now() - 3600000).toISOString(),
  },
  {
    conversation_id: "conv-1",
    role: "assistant",
    content: "CTO wants to merge this PR but needs your approval on the breaking change.",
    leader_id: "cto",
    created_at: new Date(Date.now() - 2 * 60000).toISOString(),
  },
  {
    conversation_id: "conv-2",
    role: "user",
    content: "Deploy documentation site to GitHub Pages",
    leader_id: null,
    created_at: new Date(Date.now() - 7200000).toISOString(),
  },
  {
    conversation_id: "conv-3",
    role: "user",
    content: "Draft privacy policy for GDPR compliance",
    leader_id: null,
    created_at: new Date(Date.now() - 172800000).toISOString(),
  },
];

// Mock Supabase channel
const mockSubscribe = vi.fn().mockReturnValue({ unsubscribe: vi.fn() });
// Chainable channel mock: useConversations chains .on(UPDATE).on(INSERT) before
// .subscribe(), so .on() must return the channel itself (not a subscribe-only stub).
const mockOn = vi.fn();
const mockChannelObj = { on: mockOn, subscribe: mockSubscribe };
mockOn.mockReturnValue(mockChannelObj);
const mockChannel = vi.fn().mockReturnValue(mockChannelObj);

let conversationBuilder: ReturnType<typeof buildSupabaseQueryBuilder>;
let messageBuilder: ReturnType<typeof buildSupabaseQueryBuilder>;
// Default: simulate a connected repo so the new repo_url scoping + the
// dashboard disconnected-hint effect both short-circuit sensibly.
const DEFAULT_USERS_ROW = { repo_url: "https://github.com/acme/repo" };

// useConversations now resolves its repo scope from GET /api/workspace/active-repo
// (ADR-044), not users.repo_url. The page also fetches the KB tree. This helper
// returns a URL-aware fetch mock: the active-repo route gets the connected-repo
// payload; every other URL (the KB tree) gets the supplied response.
const ACTIVE_REPO_RESPONSE = {
  workspaceId: "ws-1",
  repoUrl: "https://github.com/acme/repo",
  repoName: "acme/repo",
  repoStatus: "connected",
  fellBackToSolo: false,
};

function mockFetchWithActiveRepo(treeResponse: {
  ok: boolean;
  status: number;
  json: () => Promise<unknown>;
}) {
  return vi.fn().mockImplementation((url: string) =>
    typeof url === "string" && url.startsWith("/api/workspace/active-repo")
      ? Promise.resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve(ACTIVE_REPO_RESPONSE),
        })
      : Promise.resolve(treeResponse),
  );
}

// The dashboard now derives foundation-card state from
// /api/dashboard/foundation-status (a { paths: { <kbPath>: {exists,size} } }
// map) instead of the whole KB tree. Build a 200 response for a set of existing
// paths (default size 1000 ≥ FOUNDATION_MIN_CONTENT_BYTES = complete).
function foundationResponse(
  filePaths: string[],
  sizes: Record<string, number> = {},
) {
  const paths: Record<string, { exists: boolean; size: number }> = {};
  for (const p of filePaths) {
    paths[p] = { exists: true, size: sizes[p] ?? 1000 };
  }
  return {
    ok: true,
    status: 200,
    json: () => Promise.resolve({ paths }),
  };
}

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      }),
    },
    // The conversation-list read now flows through the list_conversations_enriched
    // RPC (migration 125): it derives from the current conversation/message
    // builders' data and applies the archive/status/domain filters the hook
    // previously issued as chained `.is`/`.not`/`.eq` calls. listRpcCalls
    // captures the args so the filter assertions can inspect them.
    rpc: async (name: string, args: Record<string, unknown>) => {
      listRpcCalls.push({ name, args });
      const conv = (await conversationBuilder) as { data: unknown[] };
      const msg = (await messageBuilder) as { data: unknown[] };
      return makeEnrichedListRpc(
        (conv.data ?? []) as { id: string }[],
        (msg.data ?? []) as { conversation_id: string; role: string; content: string; leader_id?: string | null; created_at?: string }[],
      )(name, args);
    },
    from: (table: string) => {
      if (table === "conversations") return conversationBuilder;
      if (table === "messages") return messageBuilder;
      if (table === "users") return buildSupabaseQueryBuilder({ data: [], singleRow: DEFAULT_USERS_ROW });
      return buildSupabaseQueryBuilder({ data: [] });
    },
    channel: mockChannel,
    removeChannel: vi.fn(),
  }),
}));

// Captures every list_conversations_enriched RPC invocation for filter-arg
// assertions (replaces the old chained-call inspection). Reset per test.
let listRpcCalls: { name: string; args: Record<string, unknown> }[] = [];

describe("Command Center", () => {
  beforeEach(() => {
    mockPush.mockClear();
    mockChannel.mockClear();
    listRpcCalls = [];
    conversationBuilder = buildSupabaseQueryBuilder({ data: mockConversations });
    messageBuilder = buildSupabaseQueryBuilder({ data: mockMessages });

    // Mock fetch for KB tree — return all foundation files so page shows Command Center
    globalThis.fetch = mockFetchWithActiveRepo(
      foundationResponse([
        "overview/vision.md",
        "marketing/brand-guide.md",
        "product/business-validation.md",
        "legal/privacy-policy.md",
      ]),
    );
  });

  it("shows operational tasks alongside foundation chips when all foundations are complete", async () => {
    conversationBuilder = buildSupabaseQueryBuilder({ data: [] });
    messageBuilder = buildSupabaseQueryBuilder({ data: [] });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    // All 4 foundations complete → show as chips, operational tasks in grid
    await waitFor(() => {
      expect(screen.getByText(/no conversations yet/i)).toBeInTheDocument();
    });
    // Foundation chips should be present
    expect(screen.getByText("Vision")).toBeInTheDocument();
    // Operational task buttons should appear
    expect(screen.getByText("Set pricing strategy")).toBeInTheDocument();
    expect(screen.getByText("Create competitive analysis")).toBeInTheDocument();
  });

  it("shows 'organization is ready' when all cards are complete", async () => {
    conversationBuilder = buildSupabaseQueryBuilder({ data: [] });
    messageBuilder = buildSupabaseQueryBuilder({ data: [] });

    // Mock KB tree with ALL files (4 foundation + 6 operational)
    globalThis.fetch = mockFetchWithActiveRepo(
      foundationResponse([
        "overview/vision.md",
        "marketing/brand-guide.md",
        "marketing/launch-plan.md",
        "marketing/distribution-strategy.md",
        "product/business-validation.md",
        "product/pricing-strategy.md",
        "product/competitive-analysis.md",
        "legal/privacy-policy.md",
        "operations/hiring-plan.md",
        "finance/financial-projections.md",
      ]),
    );

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    await waitFor(() => {
      expect(screen.getByText(/your organization is ready/i)).toBeInTheDocument();
    });
    expect(screen.getByRole("button", { name: /new conversation/i })).toBeInTheDocument();
  });

  it("renders conversations sorted by last_active with status badges", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    // Conversations render both mobile + desktop layouts, so use getAllByText
    await waitFor(() => {
      expect(screen.getAllByText("Needs your decision").length).toBeGreaterThanOrEqual(1);
    });
    // "Executing" also appears in dropdown option + badge(s)
    expect(screen.getAllByText("Executing").length).toBeGreaterThanOrEqual(2);
    expect(screen.getAllByText("Completed").length).toBeGreaterThanOrEqual(2);
  });

  it("filters conversations by status when dropdown is changed", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    await waitFor(() => {
      expect(screen.getAllByText("Needs your decision").length).toBeGreaterThanOrEqual(1);
    });

    // Find and change the status filter — refetch will be called
    const statusFilter = screen.getByDisplayValue("All statuses");

    // Create a new builder that returns only waiting_for_user conversations
    const filtered = mockConversations.filter((c) => c.status === "waiting_for_user");
    conversationBuilder = buildSupabaseQueryBuilder({ data: filtered });
    const filteredMessages = mockMessages.filter((m) => m.conversation_id === "conv-1");
    messageBuilder = buildSupabaseQueryBuilder({ data: filteredMessages });

    fireEvent.change(statusFilter, { target: { value: "waiting_for_user" } });

    // After filtering, only 1 conversation row should render (though badges also appear in dropdown)
    await waitFor(() => {
      // The filtered list should only show "Needs your decision" badge (in the rows)
      // "Executing" should only appear in the dropdown option, not in any row
      const executingBadges = screen.getAllByText("Executing");
      // Should be exactly 1 (dropdown option only, no badge in rows)
      expect(executingBadges.length).toBe(1);
    });
  });

  it("navigates to conversation detail when row is clicked", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    await waitFor(() => {
      // Title appears in both mobile and desktop layouts
      expect(screen.getAllByText(/Review PR #1742/).length).toBeGreaterThanOrEqual(1);
    });

    // Click the first conversation row (a div with role="button")
    const titleElements = screen.getAllByText(/Review PR #1742/);
    const row = titleElements[0].closest('[role="button"]');
    if (row) fireEvent.click(row);

    expect(mockPush).toHaveBeenCalledWith("/dashboard/chat/conv-1");
  });

  it("hides archived conversations from the default active view", async () => {
    // Include an archived conversation in the mock data
    const withArchived = [
      ...mockConversations,
      {
        id: "conv-archived",
        user_id: "user-1",
        domain_leader: "cpo",
        session_id: null,
        status: "completed" as const,
        total_cost_usd: 0,
        input_tokens: 0,
        output_tokens: 0,
        last_active: new Date(Date.now() - 604800000).toISOString(),
        created_at: new Date(Date.now() - 604800000).toISOString(),
        archived_at: new Date().toISOString(),
      },
    ];
    conversationBuilder = buildSupabaseQueryBuilder({ data: withArchived });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    await waitFor(() => {
      expect(screen.getAllByText("Needs your decision").length).toBeGreaterThanOrEqual(1);
    });

    // The active view requests the RPC with p_archive="active" (the RPC applies
    // the archived_at IS NULL filter server-side; the archived row is excluded).
    expect(listRpcCalls.some((c) => c.args.p_archive === "active")).toBe(true);
    expect(screen.queryByText(/conv-archived/)).toBeNull();
  });

  it("shows Active and Archived toggle buttons in filter bar", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Active" })).toBeInTheDocument();
    });
    expect(screen.getByRole("button", { name: "Archived" })).toBeInTheDocument();
  });

  it("switches to archived view when Archived button is clicked", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Archived" })).toBeInTheDocument();
    });

    // Reset to track the new query
    conversationBuilder = buildSupabaseQueryBuilder({ data: [] });
    listRpcCalls = [];

    fireEvent.click(screen.getByRole("button", { name: "Archived" }));

    // After clicking, the hook refetches with p_archive="archived" (the RPC
    // applies the archived_at IS NOT NULL filter server-side).
    await waitFor(() => {
      expect(listRpcCalls.some((c) => c.args.p_archive === "archived")).toBe(true);
    });
  });

  it("shows foundation cards with Vision incomplete when vision.md is a stub", async () => {
    conversationBuilder = buildSupabaseQueryBuilder({ data: [] });
    messageBuilder = buildSupabaseQueryBuilder({ data: [] });

    globalThis.fetch = mockFetchWithActiveRepo(
      // vision.md is a 200-byte stub (< FOUNDATION_MIN_CONTENT_BYTES) → Vision
      // incomplete; the other three are complete.
      foundationResponse(
        [
          "overview/vision.md",
          "marketing/brand-guide.md",
          "product/business-validation.md",
          "legal/privacy-policy.md",
        ],
        { "overview/vision.md": 200 },
      ),
    );

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    await waitFor(() => {
      expect(screen.getByText(/no conversations yet/i)).toBeInTheDocument();
    });

    // Vision is a stub — should NOT be in completed chips
    // Only 3 of 4 foundations complete (brand, validation, legal)
    const chipsRow = document.querySelector("[data-testid='completed-chips']");
    expect(chipsRow).not.toBeNull();
    const chipLinks = chipsRow!.querySelectorAll("a");
    expect(chipLinks).toHaveLength(3);
  });

  it("navigates to new conversation when button is clicked", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    await waitFor(() => {
      expect(screen.getByText(/New conversation/)).toBeInTheDocument();
    });

    // The "+ New conversation" button in the filter bar
    const buttons = screen.getAllByText(/New conversation/);
    fireEvent.click(buttons[0]);

    expect(mockPush).toHaveBeenCalledWith("/dashboard/chat/new");
  });

  // -------------------------------------------------------------------------
  // First-run state: input sizing + attachment support
  // -------------------------------------------------------------------------

  describe("first-run form", () => {
    beforeEach(() => {
      // No conversations + no vision.md triggers the first-run state
      conversationBuilder = buildSupabaseQueryBuilder({ data: [] });
      messageBuilder = buildSupabaseQueryBuilder({ data: [] });

      // Foundation status without vision.md
      globalThis.fetch = mockFetchWithActiveRepo(
        foundationResponse(["marketing/brand-guide.md"]),
      );
    });

    it("renders the first-run input and submit button at equal min-height", async () => {
      const { default: DashboardPage } = await import(
        "@/app/(dashboard)/dashboard/page"
      );
      render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

      await waitFor(() => {
        expect(screen.getByPlaceholderText("What are you building?")).toBeInTheDocument();
      });

      // Unified box (matches the shared ChatInput, chat-input.tsx): the
      // borderless input rests at the 36px button floor so the input, text
      // baseline, and send button line up inside the one bordered container.
      const input = screen.getByPlaceholderText("What are you building?");
      expect(input.className).toContain("min-h-[36px]");

      const sendButton = screen.getByLabelText("Send message");
      expect(sendButton.className).toContain("h-[36px]");
    });

    it("renders a paperclip attach button", async () => {
      const { default: DashboardPage } = await import(
        "@/app/(dashboard)/dashboard/page"
      );
      render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

      await waitFor(() => {
        expect(screen.getByLabelText("Attach files")).toBeInTheDocument();
      });
    });

    it("shows attachment preview when a valid file is selected", async () => {
      const { default: DashboardPage } = await import(
        "@/app/(dashboard)/dashboard/page"
      );
      render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

      await waitFor(() => {
        expect(screen.getByLabelText("Attach files")).toBeInTheDocument();
      });

      // Find the hidden file input and simulate file selection
      const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
      expect(fileInput).not.toBeNull();

      const pngFile = new File(["fake-png"], "test.png", { type: "image/png" });
      fireEvent.change(fileInput, { target: { files: [pngFile] } });

      await waitFor(() => {
        expect(screen.getByText("test.png")).toBeInTheDocument();
      });
    });

    it("shows error for unsupported file type", async () => {
      const { default: DashboardPage } = await import(
        "@/app/(dashboard)/dashboard/page"
      );
      render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

      await waitFor(() => {
        expect(screen.getByLabelText("Attach files")).toBeInTheDocument();
      });

      const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
      const exeFile = new File(["bad"], "malware.exe", { type: "application/x-executable" });
      fireEvent.change(fileInput, { target: { files: [exeFile] } });

      await waitFor(() => {
        expect(screen.getByText(/not a supported file type/)).toBeInTheDocument();
      });
    });

    it("removes attachment when X button is clicked", async () => {
      const { default: DashboardPage } = await import(
        "@/app/(dashboard)/dashboard/page"
      );
      render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

      await waitFor(() => {
        expect(screen.getByLabelText("Attach files")).toBeInTheDocument();
      });

      const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
      const file = new File(["data"], "doc.pdf", { type: "application/pdf" });
      fireEvent.change(fileInput, { target: { files: [file] } });

      await waitFor(() => {
        expect(screen.getByText("doc.pdf")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByLabelText("Remove doc.pdf"));

      await waitFor(() => {
        expect(screen.queryByText("doc.pdf")).not.toBeInTheDocument();
      });
    });

    it("navigates to chat/new on submit with text", async () => {
      const { default: DashboardPage } = await import(
        "@/app/(dashboard)/dashboard/page"
      );
      render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

      await waitFor(() => {
        expect(screen.getByPlaceholderText("What are you building?")).toBeInTheDocument();
      });

      const input = screen.getByPlaceholderText("What are you building?");
      fireEvent.change(input, { target: { value: "A SaaS for cats" } });
      fireEvent.submit(input.closest("form")!);

      expect(mockPush).toHaveBeenCalledWith(
        expect.stringContaining("/dashboard/chat/new"),
      );
    });
  });
});
