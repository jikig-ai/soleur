import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

let mockPathname = "/dashboard";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  usePathname: () => mockPathname,
  // ConversationsRail (mounted via the drawer aside since the rail PR)
  // calls useParams<{ conversationId }>(); a missing export would crash
  // every render. The DashboardLayout test set predates the rail mount
  // and doesn't care about active-row indication, so an empty-object
  // mock is sufficient.
  useParams: () => ({}),
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
    removeAllChannels: vi.fn(() => Promise.resolve([])),
  }),
}));

import { createUseTeamNamesMock } from "./mocks/use-team-names";

vi.mock("@/hooks/use-team-names", () => ({
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
  useTeamNames: () => createUseTeamNamesMock(),
}));

import DashboardLayout from "@/app/(dashboard)/layout";

describe("Dashboard sidebar collapse", () => {
  beforeEach(() => {
    mockPathname = "/dashboard";
    localStorage.clear();
  });

  afterEach(() => {
    localStorage.clear();
  });

  it("renders a collapse toggle button", () => {
    render(<DashboardLayout><div>content</div></DashboardLayout>);
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
  });

  it("toggles aria-label when collapse toggle is clicked", async () => {
    render(<DashboardLayout><div>content</div></DashboardLayout>);
    const toggle = screen.getByLabelText("Collapse sidebar");
    await userEvent.click(toggle);
    expect(screen.getByLabelText("Expand sidebar")).toBeInTheDocument();
  });

  it("adds title attributes to nav links when collapsed", async () => {
    render(<DashboardLayout><div>content</div></DashboardLayout>);
    const toggle = screen.getByLabelText("Collapse sidebar");
    await userEvent.click(toggle);
    expect(screen.getByTitle("Dashboard")).toBeInTheDocument();
    expect(screen.getByTitle("Knowledge Base")).toBeInTheDocument();
    expect(screen.getByTitle("Settings")).toBeInTheDocument();
  });

  it("does not show title attributes when expanded", () => {
    render(<DashboardLayout><div>content</div></DashboardLayout>);
    expect(screen.queryByTitle("Dashboard")).not.toBeInTheDocument();
  });

  it("persists collapse state to localStorage", async () => {
    render(<DashboardLayout><div>content</div></DashboardLayout>);
    const toggle = screen.getByLabelText("Collapse sidebar");
    await userEvent.click(toggle);
    expect(localStorage.getItem("soleur:sidebar.main.collapsed")).toBe("1");
  });

  it("toggles sidebar on Cmd+B when on /dashboard", () => {
    render(<DashboardLayout><div>content</div></DashboardLayout>);
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(screen.getByLabelText("Expand sidebar")).toBeInTheDocument();
  });

  it("toggles sidebar on Ctrl+B when on /dashboard", () => {
    render(<DashboardLayout><div>content</div></DashboardLayout>);
    fireEvent.keyDown(document, { key: "b", ctrlKey: true });
    expect(screen.getByLabelText("Expand sidebar")).toBeInTheDocument();
  });

  it("does NOT toggle sidebar on Cmd+B when on /dashboard/kb route", () => {
    mockPathname = "/dashboard/kb/some-file";
    render(<DashboardLayout><div>content</div></DashboardLayout>);
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    // Should still be expanded — main sidebar shortcut does not fire on KB routes
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
  });

  it("does NOT toggle sidebar on Cmd+B when on /dashboard/settings route", () => {
    mockPathname = "/dashboard/settings/team";
    render(<DashboardLayout><div>content</div></DashboardLayout>);
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
  });

  it("ignores Cmd+B when focus is in an input element", () => {
    render(
      <DashboardLayout>
        <input data-testid="test-input" />
      </DashboardLayout>,
    );
    const input = screen.getByTestId("test-input");
    fireEvent.keyDown(input, { key: "b", metaKey: true, bubbles: true });
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
  });

  it("ignores Cmd+B when focus is in a textarea", () => {
    render(
      <DashboardLayout>
        <textarea data-testid="test-textarea" />
      </DashboardLayout>,
    );
    const textarea = screen.getByTestId("test-textarea");
    fireEvent.keyDown(textarea, { key: "b", metaKey: true, bubbles: true });
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
  });
});
