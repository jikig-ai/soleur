import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
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
  it("renders the conversations rail inside the drawer aside", async () => {
    const { default: DashboardLayout } = await import(
      "@/app/(dashboard)/layout"
    );

    render(
      <DashboardLayout>
        <div data-testid="page">page</div>
      </DashboardLayout>,
    );

    // The rail is mobile-only (md:hidden). It still mounts in the drawer
    // tree so users can switch conversations from the drawer on phones.
    const rail = screen.getByTestId("conversations-rail-drawer");
    expect(rail).toBeInTheDocument();

    // Footer "View all in Command Center" link must be visible inside the
    // drawer-mounted rail so users on mobile can jump back to /dashboard.
    const viewAll = screen.getByRole("link", {
      name: /view all in command center/i,
    });
    expect(viewAll).toHaveAttribute("href", "/dashboard");
  });
});
