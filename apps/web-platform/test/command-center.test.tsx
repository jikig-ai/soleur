import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

// Mock next/navigation — stable reference prevents useEffect re-fires
const mockPush = vi.fn();
const mockRouter = { push: mockPush };
vi.mock("next/navigation", () => ({
  useRouter: () => mockRouter,
  usePathname: () => "/dashboard",
}));

// Mock conversation data
const mockConversations = [
  {
    id: "conv-1",
    user_id: "user-1",
    domain_leader: "cto",
    session_id: null,
    status: "waiting_for_user" as const,
    last_active: new Date(Date.now() - 2 * 60000).toISOString(), // 2m ago
    created_at: new Date(Date.now() - 3600000).toISOString(),
  },
  {
    id: "conv-2",
    user_id: "user-1",
    domain_leader: "cmo",
    session_id: null,
    status: "active" as const,
    last_active: new Date(Date.now() - 15 * 60000).toISOString(), // 15m ago
    created_at: new Date(Date.now() - 7200000).toISOString(),
  },
  {
    id: "conv-3",
    user_id: "user-1",
    domain_leader: "cfo",
    session_id: null,
    status: "completed" as const,
    last_active: new Date(Date.now() - 86400000).toISOString(), // 1d ago
    created_at: new Date(Date.now() - 172800000).toISOString(),
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
              { name: "overview", type: "directory", children: [{ name: "vision.md", type: "file", path: "overview/vision.md" }] },
              { name: "marketing", type: "directory", children: [{ name: "brand-guide.md", type: "file", path: "marketing/brand-guide.md" }] },
              { name: "product", type: "directory", children: [{ name: "business-validation.md", type: "file", path: "product/business-validation.md" }] },
              { name: "legal", type: "directory", children: [{ name: "privacy-policy.md", type: "file", path: "legal/privacy-policy.md" }] },
            ],
          },
        }),
    });
  });

  it("shows empty state with suggested prompts when user has no conversations", async () => {
    conversationBuilder = createQueryBuilder([]);
    messageBuilder = createQueryBuilder([]);

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
});
