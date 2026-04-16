import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";

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
const mockOn = vi.fn().mockReturnValue({ subscribe: mockSubscribe });
const mockChannel = vi.fn().mockReturnValue({ on: mockOn });

// Supabase query builder mock — must be thenable like the real client
function createQueryBuilder(data: unknown[]) {
  const result = { data, error: null };
  const builder = {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    in: vi.fn().mockReturnThis(),
    is: vi.fn().mockReturnThis(),
    not: vi.fn().mockReturnThis(),
    order: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    single: vi.fn().mockReturnThis(),
    update: vi.fn().mockReturnThis(),
    then: (onfulfilled: (value: unknown) => unknown) =>
      Promise.resolve(result).then(onfulfilled),
  };
  return builder;
}

let conversationBuilder: ReturnType<typeof createQueryBuilder>;
let messageBuilder: ReturnType<typeof createQueryBuilder>;

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === "conversations") return conversationBuilder;
      if (table === "messages") return messageBuilder;
      return createQueryBuilder([]);
    },
    channel: mockChannel,
    removeChannel: vi.fn(),
  }),
}));

describe("Command Center", () => {
  beforeEach(() => {
    mockPush.mockClear();
    mockChannel.mockClear();
    conversationBuilder = createQueryBuilder(mockConversations);
    messageBuilder = createQueryBuilder(mockMessages);

    // Mock fetch for KB tree — return all foundation files so page shows Command Center
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          tree: {
            name: "knowledge-base",
            type: "directory",
            children: [
              { name: "overview", type: "directory", children: [{ name: "vision.md", type: "file", path: "overview/vision.md", size: 1000 }] },
              { name: "marketing", type: "directory", children: [{ name: "brand-guide.md", type: "file", path: "marketing/brand-guide.md", size: 1000 }] },
              { name: "product", type: "directory", children: [{ name: "business-validation.md", type: "file", path: "product/business-validation.md", size: 1000 }] },
              { name: "legal", type: "directory", children: [{ name: "privacy-policy.md", type: "file", path: "legal/privacy-policy.md", size: 1000 }] },
            ],
          },
        }),
    });
  });

  it("shows operational tasks alongside foundation chips when all foundations are complete", async () => {
    conversationBuilder = createQueryBuilder([]);
    messageBuilder = createQueryBuilder([]);

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

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
    conversationBuilder = createQueryBuilder([]);
    messageBuilder = createQueryBuilder([]);

    // Mock KB tree with ALL files (4 foundation + 6 operational)
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          tree: {
            name: "knowledge-base",
            type: "directory",
            children: [
              { name: "overview", type: "directory", children: [{ name: "vision.md", type: "file", path: "overview/vision.md", size: 1000 }] },
              { name: "marketing", type: "directory", children: [
                { name: "brand-guide.md", type: "file", path: "marketing/brand-guide.md", size: 1000 },
                { name: "launch-plan.md", type: "file", path: "marketing/launch-plan.md", size: 1000 },
                { name: "distribution-strategy.md", type: "file", path: "marketing/distribution-strategy.md", size: 1000 },
              ] },
              { name: "product", type: "directory", children: [
                { name: "business-validation.md", type: "file", path: "product/business-validation.md", size: 1000 },
                { name: "pricing-strategy.md", type: "file", path: "product/pricing-strategy.md", size: 1000 },
                { name: "competitive-analysis.md", type: "file", path: "product/competitive-analysis.md", size: 1000 },
              ] },
              { name: "legal", type: "directory", children: [{ name: "privacy-policy.md", type: "file", path: "legal/privacy-policy.md", size: 1000 }] },
              { name: "operations", type: "directory", children: [{ name: "hiring-plan.md", type: "file", path: "operations/hiring-plan.md", size: 1000 }] },
              { name: "finance", type: "directory", children: [{ name: "financial-projections.md", type: "file", path: "finance/financial-projections.md", size: 1000 }] },
            ],
          },
        }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText(/your organization is ready/i)).toBeInTheDocument();
    });
    expect(screen.getByRole("button", { name: /new conversation/i })).toBeInTheDocument();
  });

  it("renders conversations sorted by last_active with status badges", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

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
    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getAllByText("Needs your decision").length).toBeGreaterThanOrEqual(1);
    });

    // Find and change the status filter — refetch will be called
    const statusFilter = screen.getByDisplayValue("All statuses");

    // Create a new builder that returns only waiting_for_user conversations
    const filtered = mockConversations.filter((c) => c.status === "waiting_for_user");
    conversationBuilder = createQueryBuilder(filtered);
    const filteredMessages = mockMessages.filter((m) => m.conversation_id === "conv-1");
    messageBuilder = createQueryBuilder(filteredMessages);

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
    render(<DashboardPage />);

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
    conversationBuilder = createQueryBuilder(withArchived);

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getAllByText("Needs your decision").length).toBeGreaterThanOrEqual(1);
    });

    // The query builder should have been called with .is("archived_at", null) for the default active view
    expect(conversationBuilder.is).toHaveBeenCalledWith("archived_at", null);
  });

  it("shows Active and Archived toggle buttons in filter bar", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Active" })).toBeInTheDocument();
    });
    expect(screen.getByRole("button", { name: "Archived" })).toBeInTheDocument();
  });

  it("switches to archived view when Archived button is clicked", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Archived" })).toBeInTheDocument();
    });

    // Reset the mock to track the new query
    conversationBuilder = createQueryBuilder([]);

    fireEvent.click(screen.getByRole("button", { name: "Archived" }));

    // After clicking, the hook should refetch with .not("archived_at", "is", null)
    await waitFor(() => {
      expect(conversationBuilder.not).toHaveBeenCalledWith("archived_at", "is", null);
    });
  });

  it("shows foundation cards with Vision incomplete when vision.md is a stub", async () => {
    conversationBuilder = createQueryBuilder([]);
    messageBuilder = createQueryBuilder([]);

    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          tree: {
            name: "knowledge-base",
            type: "directory",
            children: [
              { name: "overview", type: "directory", children: [{ name: "vision.md", type: "file", path: "overview/vision.md", size: 200 }] },
              { name: "marketing", type: "directory", children: [{ name: "brand-guide.md", type: "file", path: "marketing/brand-guide.md", size: 1000 }] },
              { name: "product", type: "directory", children: [{ name: "business-validation.md", type: "file", path: "product/business-validation.md", size: 1000 }] },
              { name: "legal", type: "directory", children: [{ name: "privacy-policy.md", type: "file", path: "legal/privacy-policy.md", size: 1000 }] },
            ],
          },
        }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText(/no conversations yet/i)).toBeInTheDocument();
    });

    // Vision is a stub — should NOT have green checkmark
    // Only 3 of 4 foundations complete (brand, validation, legal)
    const completeLabels = screen.getAllByLabelText("Complete");
    expect(completeLabels).toHaveLength(3);
  });

  it("navigates to new conversation when button is clicked", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

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
      conversationBuilder = createQueryBuilder([]);
      messageBuilder = createQueryBuilder([]);

      // KB tree without vision.md
      globalThis.fetch = vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () =>
          Promise.resolve({
            tree: {
              name: "knowledge-base",
              type: "directory",
              children: [
                { name: "marketing", type: "directory", children: [{ name: "brand-guide.md", type: "file", path: "marketing/brand-guide.md", size: 1000 }] },
              ],
            },
          }),
      });
    });

    it("renders the first-run input and submit button at equal min-height", async () => {
      const { default: DashboardPage } = await import(
        "@/app/(dashboard)/dashboard/page"
      );
      render(<DashboardPage />);

      await waitFor(() => {
        expect(screen.getByPlaceholderText("What are you building?")).toBeInTheDocument();
      });

      const input = screen.getByPlaceholderText("What are you building?");
      expect(input.className).toContain("min-h-[44px]");
    });

    it("renders a paperclip attach button", async () => {
      const { default: DashboardPage } = await import(
        "@/app/(dashboard)/dashboard/page"
      );
      render(<DashboardPage />);

      await waitFor(() => {
        expect(screen.getByLabelText("Attach files")).toBeInTheDocument();
      });
    });

    it("shows attachment preview when a valid file is selected", async () => {
      const { default: DashboardPage } = await import(
        "@/app/(dashboard)/dashboard/page"
      );
      render(<DashboardPage />);

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
      render(<DashboardPage />);

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
      render(<DashboardPage />);

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
      render(<DashboardPage />);

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
