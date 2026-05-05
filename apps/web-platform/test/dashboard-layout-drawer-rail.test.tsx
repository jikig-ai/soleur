import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";

// Phase 4 RED: the dashboard mobile drawer must render the chat
// conversations rail so users on small viewports can switch threads
// without leaving the drawer. Per plan
// 2026-04-29-feat-command-center-conversation-nav-plan.md task 4.1.

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  usePathname: () => "/dashboard/chat/conv-1",
  useParams: () => ({ conversationId: "conv-1" }),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getSession: () =>
        Promise.resolve({ data: { session: null }, error: null }),
      getUser: () => Promise.resolve({ data: { user: null }, error: null }),
      signOut: vi.fn(() => Promise.resolve({ error: null })),
    },
    from: () => ({
      select: () => ({
        eq: () => ({
          single: () => Promise.resolve({ data: null, error: null }),
          maybeSingle: () => Promise.resolve({ data: null, error: null }),
        }),
      }),
    }),
    channel: () => ({
      on: vi.fn().mockReturnThis(),
      subscribe: vi.fn().mockReturnThis(),
    }),
    removeChannel: vi.fn(),
    removeAllChannels: vi.fn(() => []),
  }),
}));

vi.mock("@/hooks/use-team-names", () => ({
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
  useTeamNames: () => createUseTeamNamesMock(),
}));

vi.mock("@/hooks/use-conversations", async (importOriginal) => {
  const actual = await importOriginal<
    typeof import("@/hooks/use-conversations")
  >();
  return {
    ...actual,
    useConversations: () => ({
      conversations: [],
      loading: false,
      error: null,
      refetch: vi.fn(),
      archiveConversation: vi.fn(),
      unarchiveConversation: vi.fn(),
      updateStatus: vi.fn(),
    }),
  };
});

// fetch /api/admin/check is called on mount
const fetchMock = vi.fn(() =>
  Promise.resolve({
    ok: true,
    json: () => Promise.resolve({ isAdmin: false }),
  } as Response),
);

beforeEach(() => {
  vi.stubGlobal("fetch", fetchMock);
  fetchMock.mockClear();
});

afterEach(() => {
  vi.unstubAllGlobals();
  cleanup();
});

describe("DashboardLayout — mobile drawer surfaces ConversationsRail", () => {
  it("does NOT mount the rail in the drawer when closed (avoids duplicate Realtime channel)", async () => {
    const { default: DashboardLayout } = await import(
      "@/app/(dashboard)/layout"
    );

    render(
      <DashboardLayout>
        <div data-testid="page">page</div>
      </DashboardLayout>,
    );

    // Default drawerOpen=false. The rail must NOT mount yet — mounting
    // unconditionally would open a duplicate "command-center" Realtime
    // channel alongside the chat-segment layout's rail. See review
    // feedback on PR #3021 (perf P1).
    expect(
      screen.queryByTestId("conversations-rail-drawer"),
    ).not.toBeInTheDocument();
  });

  it("mounts the rail inside the drawer when the user opens it on a chat route", async () => {
    const { default: DashboardLayout } = await import(
      "@/app/(dashboard)/layout"
    );

    render(
      <DashboardLayout>
        <div data-testid="page">page</div>
      </DashboardLayout>,
    );

    // Simulate the mobile menu button click — this is the only path that
    // sets drawerOpen=true (md+ users never see the button).
    fireEvent.click(screen.getByLabelText(/open navigation/i));

    const rail = screen.getByTestId("conversations-rail-drawer");
    expect(rail).toBeInTheDocument();

    // Footer "View all in Dashboard" link must be visible inside the
    // drawer-mounted rail so users on mobile can jump back to /dashboard.
    const viewAll = screen.getByRole("link", {
      name: /view all in dashboard/i,
    });
    expect(viewAll).toHaveAttribute("href", "/dashboard");
  });
});
