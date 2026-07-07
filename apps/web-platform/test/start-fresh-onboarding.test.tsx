import { describe, it, expect, vi, beforeEach, type Mock } from "vitest";
import { render, screen, waitFor, fireEvent } from "@testing-library/react";
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

const mockSubscribe = vi.fn().mockReturnValue({ unsubscribe: vi.fn() });
// Chainable channel mock: useConversations chains .on(UPDATE).on(INSERT) before
// .subscribe(), so .on() must return the channel itself (not a subscribe-only stub).
const mockOn = vi.fn();
const mockChannelObj = { on: mockOn, subscribe: mockSubscribe };
mockOn.mockReturnValue(mockChannelObj);
const mockChannel = vi.fn().mockReturnValue(mockChannelObj);

let conversationBuilder: ReturnType<typeof buildSupabaseQueryBuilder>;
let messageBuilder: ReturnType<typeof buildSupabaseQueryBuilder>;
let userBuilder: ReturnType<typeof buildSupabaseQueryBuilder>;

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      }),
    },
    // The list read flows through the list_conversations_enriched RPC
    // (migration 125), deriving from the current conversation/message builders.
    rpc: async (name: string, args: Record<string, unknown>) => {
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
      if (table === "users") return userBuilder;
      return buildSupabaseQueryBuilder({ data: [] });
    },
    channel: mockChannel,
    removeChannel: vi.fn(),
  }),
}));

// Helper: build the /api/dashboard/foundation-status `paths` map (existence +
// size for the known foundation paths) matching the API response shape.
function buildFoundationPaths(
  filePaths: string[],
  sizes?: Record<string, number>,
): Record<string, { exists: boolean; size: number }> {
  const paths: Record<string, { exists: boolean; size: number }> = {};
  for (const p of filePaths) {
    paths[p] = { exists: true, size: sizes?.[p] ?? 1000 };
  }
  return paths;
}

let fetchMock: Mock;

// useConversations resolves its repo scope from GET /api/workspace/active-repo
// (ADR-044), not users.repo_url. Connected-repo payload for that route.
const ACTIVE_REPO_RESPONSE = {
  workspaceId: "ws-1",
  repoUrl: "https://github.com/acme/repo",
  repoName: "acme/repo",
  repoStatus: "connected",
  fellBackToSolo: false,
};

beforeEach(() => {
  vi.resetModules();
  mockPush.mockClear();
  mockChannel.mockClear();
  conversationBuilder = buildSupabaseQueryBuilder({ data: [] });
  messageBuilder = buildSupabaseQueryBuilder({ data: [] });
  userBuilder = buildSupabaseQueryBuilder({
    data: [{ onboarding_completed_at: null, pwa_banner_dismissed_at: null }],
    singleRow: { repo_url: "https://github.com/acme/repo" },
  });
  fetchMock = vi.fn();
  // Route the active-repo call to a fixed payload via an outer wrapper so it
  // never consumes the per-test KB-tree `mockResolvedValueOnce` queue on
  // `fetchMock` (the two fetches fire in non-deterministic effect order).
  globalThis.fetch = vi
    .fn()
    .mockImplementation((url: string, ...rest: unknown[]) => {
      if (typeof url === "string" && url.startsWith("/api/workspace/active-repo")) {
        return Promise.resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve(ACTIVE_REPO_RESPONSE),
        });
      }
      return (fetchMock as (...a: unknown[]) => unknown)(url, ...rest);
    });
});

describe("Start Fresh Onboarding - KB State Derivation", () => {
  it("shows first-run view when KB tree has no vision.md", async () => {
    // Empty KB tree
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () => Promise.resolve({ paths: buildFoundationPaths([]) }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

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
        Promise.resolve({ paths: buildFoundationPaths(["overview/vision.md"]) }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    await waitFor(() => {
      expect(screen.getByText(/complete these to brief your department leaders/i)).toBeInTheDocument();
    });
    // Vision card should be marked complete
    expect(screen.getByText("Vision")).toBeInTheDocument();
    // Empty conversation placeholder should also appear
    expect(screen.getByText(/no conversations yet/i)).toBeInTheDocument();
  });

  it("shows operational tasks when all 4 foundation files exist", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          paths: buildFoundationPaths([
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
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    // All foundations complete → show as chips, operational tasks appear
    await waitFor(() => {
      expect(screen.getByText(/no conversations yet/i)).toBeInTheDocument();
    });
    // Operational tasks should be visible in the grid
    expect(screen.getByText("Set pricing strategy")).toBeInTheDocument();
  });

  it("shows 'organization is ready' when all foundation and operational files exist", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          paths: buildFoundationPaths([
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
        }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

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
          paths: buildFoundationPaths([
            "overview/vision.md",
            "marketing/brand-guide.md",
          ]),
        }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    await waitFor(() => {
      expect(screen.getByText(/complete these to brief your department leaders/i)).toBeInTheDocument();
    });

    // Vision and Brand should be complete (shown as chips)
    const chipsRow = document.querySelector("[data-testid='completed-chips']");
    expect(chipsRow).not.toBeNull();
    expect(chipsRow!.querySelectorAll("a")).toHaveLength(2);

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
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

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
        Promise.resolve({ paths: buildFoundationPaths(["overview/vision.md"]) }),
    });

    // Conversations exist
    conversationBuilder = buildSupabaseQueryBuilder({ data: [
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
    ] });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

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
          paths: buildFoundationPaths(
            ["overview/vision.md"],
            { "overview/vision.md": 200 },
          ),
        }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

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
          paths: buildFoundationPaths(
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
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

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
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

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
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

    // Should show skeleton, not the Command Center or first-run view
    expect(screen.queryByText(/your organization is ready/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/tell your organization/i)).not.toBeInTheDocument();
    expect(document.querySelector(".animate-pulse")).toBeInTheDocument();
  });

  it("first-run view hides leader strip and suggested prompts", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () => Promise.resolve({ paths: buildFoundationPaths([]) }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

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
        Promise.resolve({ paths: buildFoundationPaths(["overview/vision.md"]) }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

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
          paths: buildFoundationPaths([
            "overview/vision.md",
            "marketing/brand-guide.md",
          ]),
        }),
    });

    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<SwrTestProvider><DashboardPage /></SwrTestProvider>);

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
