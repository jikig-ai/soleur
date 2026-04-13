import { describe, it, expect, vi, beforeEach, type Mock } from "vitest";
import { render, screen, waitFor, fireEvent } from "@testing-library/react";

// Mock next/navigation — stable reference prevents useEffect re-fires
const mockPush = vi.fn();
const mockRouter = { push: mockPush };
vi.mock("next/navigation", () => ({
  useRouter: () => mockRouter,
  usePathname: () => "/dashboard",
}));

// Supabase query builder mock (thenable, matches existing pattern)
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

const mockSubscribe = vi.fn().mockReturnValue({ unsubscribe: vi.fn() });
const mockOn = vi.fn().mockReturnValue({ subscribe: mockSubscribe });
const mockChannel = vi.fn().mockReturnValue({ on: mockOn });

let conversationBuilder: ReturnType<typeof createQueryBuilder>;
let messageBuilder: ReturnType<typeof createQueryBuilder>;
let userBuilder: ReturnType<typeof createQueryBuilder>;

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
      if (table === "users") return userBuilder;
      return createQueryBuilder([]);
    },
    channel: mockChannel,
    removeChannel: vi.fn(),
  }),
}));

// Helper: build a KB tree structure matching the API response
function buildMockTree(
  filePaths: string[],
  sizes?: Record<string, number>,
) {
  // Build a nested TreeNode from flat paths
  const root: Record<string, unknown> = {
    name: "knowledge-base",
    type: "directory",
    children: [] as unknown[],
  };

  for (const p of filePaths) {
    const parts = p.split("/");
    let current = root;

    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      const isFile = i === parts.length - 1;
      let children = current.children as Record<string, unknown>[];

      if (isFile) {
        children.push({
          name: part,
          type: "file",
          path: p,
          modifiedAt: new Date().toISOString(),
          size: sizes?.[p] ?? 1000,
        });
      } else {
        let dir = children.find(
          (c) => c.name === part && c.type === "directory",
        );
        if (!dir) {
          dir = { name: part, type: "directory", children: [] };
          children.push(dir);
        }
        current = dir as Record<string, unknown>;
      }
    }
  }

  return root;
}

let fetchMock: Mock;

beforeEach(() => {
  vi.resetModules();
  mockPush.mockClear();
  mockChannel.mockClear();
  conversationBuilder = createQueryBuilder([]);
  messageBuilder = createQueryBuilder([]);
  userBuilder = createQueryBuilder([
    { onboarding_completed_at: null, pwa_banner_dismissed_at: null },
  ]);
  fetchMock = vi.fn();
  globalThis.fetch = fetchMock;
});

describe("Start Fresh Onboarding - KB State Derivation", () => {
  it("shows first-run view when KB tree has no vision.md", async () => {
    // Empty KB tree
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () => Promise.resolve({ tree: buildMockTree([]) }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(
        screen.getByText(/tell your organization what you're building/i),
      ).toBeInTheDocument();
    });
  });

  it("shows foundations view when only vision.md exists", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({ tree: buildMockTree(["overview/vision.md"]) }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText(/complete these to brief your department leaders/i)).toBeInTheDocument();
    });
    // Vision card should be marked complete
    expect(screen.getByText("Vision")).toBeInTheDocument();
    // Empty conversation placeholder should also appear
    expect(screen.getByText(/no conversations yet/i)).toBeInTheDocument();
  });

  it("shows Command Center when all 4 foundation files exist", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          tree: buildMockTree([
            "overview/vision.md",
            "marketing/brand-guide.md",
            "product/business-validation.md",
            "legal/privacy-policy.md",
          ]),
        }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(
        screen.getByText(/your organization is ready/i),
      ).toBeInTheDocument();
    });
  });

  it("marks correct cards as done with partial files", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          tree: buildMockTree([
            "overview/vision.md",
            "marketing/brand-guide.md",
          ]),
        }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText(/complete these to brief your department leaders/i)).toBeInTheDocument();
    });

    // Vision and Brand should be complete (checkmark accessible text)
    const completeLabels = screen.getAllByLabelText("Complete");
    expect(completeLabels).toHaveLength(2);

    // Business Validation and Legal should be not-done (clickable prompts)
    expect(screen.getByText("Business Validation")).toBeInTheDocument();
    expect(screen.getByText("Legal Foundations")).toBeInTheDocument();
  });

  it("shows provisioning state on API 503", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: false,
      status: 503,
      json: () => Promise.resolve({ error: "Workspace not ready" }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(
        screen.getByText(/setting up your workspace/i),
      ).toBeInTheDocument();
    });
  });

  it("shows foundation cards and conversation list together when foundations incomplete and conversations exist", async () => {
    // Partial foundations (vision only)
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({ tree: buildMockTree(["overview/vision.md"]) }),
    });

    // Conversations exist
    conversationBuilder = createQueryBuilder([
      {
        id: "conv-1",
        user_id: "user-1",
        domain_leader: "cmo",
        session_id: null,
        status: "completed",
        total_cost_usd: 0,
        input_tokens: 0,
        output_tokens: 0,
        last_active: new Date().toISOString(),
        created_at: new Date().toISOString(),
        title: "Brand strategy discussion",
        archived_at: null,
      },
    ]);

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    // Foundation cards should be visible
    await waitFor(() => {
      expect(screen.getByText(/complete these to brief your department leaders/i)).toBeInTheDocument();
    });

    // Conversation list should also be visible (filter bar indicates inbox state)
    expect(screen.getByText(/all statuses/i)).toBeInTheDocument();
    // Foundation card titles
    expect(screen.getByText("Brand Identity")).toBeInTheDocument();
    expect(screen.getByText("Legal Foundations")).toBeInTheDocument();
  });

  it("stub vision.md does not count as foundation complete", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          tree: buildMockTree(
            ["overview/vision.md"],
            { "overview/vision.md": 200 },
          ),
        }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      // Vision exists but is stub — should show foundation cards
      expect(screen.getByText(/no conversations yet/i)).toBeInTheDocument();
    });

    // No green checkmarks — vision is a stub (< 500 bytes)
    expect(screen.queryByLabelText("Complete")).not.toBeInTheDocument();
  });

  it("shows all foundations complete only when all files >= 500 bytes", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          tree: buildMockTree(
            [
              "overview/vision.md",
              "marketing/brand-guide.md",
              "product/business-validation.md",
              "legal/privacy-policy.md",
            ],
            { "overview/vision.md": 300 },
          ),
        }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      // Vision is a stub so not all foundations complete — shows foundations view
      expect(screen.getByText(/complete these to brief your department leaders/i)).toBeInTheDocument();
    });

    // Should NOT show "Your organization is ready"
    expect(screen.queryByText(/your organization is ready/i)).not.toBeInTheDocument();
  });

  it("falls through to Command Center on API error", async () => {
    fetchMock.mockRejectedValueOnce(new Error("Network error"));

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    // Should fall through to empty state (no foundations visible since KB state unknown)
    await waitFor(() => {
      expect(
        screen.getByText(/no conversations yet/i),
      ).toBeInTheDocument();
    });
  });
});

describe("Start Fresh Onboarding - Conditional Rendering", () => {
  it("shows loading skeleton while KB tree is fetching", async () => {
    // Never resolve the fetch
    fetchMock.mockReturnValueOnce(new Promise(() => {}));

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    // Should show skeleton, not the Command Center or first-run view
    expect(screen.queryByText(/your organization is ready/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/tell your organization/i)).not.toBeInTheDocument();
    expect(document.querySelector(".animate-pulse")).toBeInTheDocument();
  });

  it("first-run view hides leader strip and suggested prompts", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () => Promise.resolve({ tree: buildMockTree([]) }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(
        screen.getByText(/tell your organization what you're building/i),
      ).toBeInTheDocument();
    });

    // No leader strip
    expect(screen.queryByText("YOUR ORGANIZATION")).not.toBeInTheDocument();
    // No generic suggested prompts
    expect(
      screen.queryByText(/review my go-to-market strategy/i),
    ).not.toBeInTheDocument();
  });

  it("foundation card click navigates to new chat with prompt", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({ tree: buildMockTree(["overview/vision.md"]) }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText("Brand Identity")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText("Brand Identity"));

    expect(mockPush).toHaveBeenCalledWith(
      expect.stringContaining("/dashboard/chat/new?msg="),
    );
  });

  it("done card links to KB viewer", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          tree: buildMockTree([
            "overview/vision.md",
            "marketing/brand-guide.md",
          ]),
        }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText(/complete these to brief your department leaders/i)).toBeInTheDocument();
    });

    // Done cards should be links to KB viewer
    const visionLink = screen.getByText("Vision").closest("a");
    expect(visionLink).toHaveAttribute(
      "href",
      "/dashboard/kb/overview/vision.md",
    );
  });
});
