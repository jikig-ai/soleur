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
import { ThemeProvider } from "@/components/theme/theme-provider";

// happy-dom does not provide window.matchMedia by default, but ThemeProvider
// (mounted via the dashboard sidebar's ThemeToggle) reads it on mount.
const stubMatchMedia = () => ({
  matches: false,
  addEventListener: () => {},
  removeEventListener: () => {},
});

function Wrap({ children }: { children: React.ReactNode }) {
  return <ThemeProvider>{children}</ThemeProvider>;
}

describe("Dashboard sidebar collapse", () => {
  beforeEach(() => {
    mockPathname = "/dashboard";
    localStorage.clear();
    vi.stubGlobal("matchMedia", stubMatchMedia);
  });

  afterEach(() => {
    localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("renders a collapse toggle button", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
  });

  // Reclaimed-space restructure: the dedicated desktop toggle row was removed so
  // the workspace context band rises to the sidebar top (~45px reclaimed). The
  // collapse toggle is now FLOATED (`absolute right-3 top-10`, `md:flex`) instead of
  // living in an in-flow row. jsdom has no layout engine, so this pins the
  // className tokens against a silent revert to the old in-flow row; the pixel
  // proof (reclaimed space + no chevron/tile overlap) lives in the e2e VRT gate
  // (e2e/nav-states-shell.e2e.ts).
  it("floats the collapse toggle out of flow (absolute, top-right, md:flex) so the band owns the sidebar top", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const toggle = screen.getByLabelText("Collapse sidebar");
    expect(toggle.className).toContain("absolute");
    expect(toggle.className).toContain("md:flex");
    // top-10 (40px) vertically centers the h-6 toggle on the workspace pill, whose
    // center sits ~52px below the aside top (the band is offset ~12px below the aside
    // top + pt-2 + pill half-height); not the old top-3 corner offset that read ~28px
    // high. jsdom has no layout engine, so this is a className drift tripwire; the
    // pixel proof (≤2px rect-center alignment) lives in e2e/nav-states-shell.e2e.ts (AC1).
    expect(toggle.className).toContain("top-10");
    expect(toggle.className).not.toContain("top-3");
    expect(toggle.className).toContain("right-3");
  });

  it("toggles aria-label when collapse toggle is clicked", async () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const toggle = screen.getByLabelText("Collapse sidebar");
    await userEvent.click(toggle);
    expect(screen.getByLabelText("Expand sidebar")).toBeInTheDocument();
  });

  it("adds title attributes to nav links when collapsed", async () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const toggle = screen.getByLabelText("Collapse sidebar");
    await userEvent.click(toggle);
    expect(screen.getByTitle("Dashboard")).toBeInTheDocument();
    expect(screen.getByTitle("Knowledge Base")).toBeInTheDocument();
    expect(screen.getByTitle("Settings")).toBeInTheDocument();
  });

  it("does not show title attributes when expanded", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    expect(screen.queryByTitle("Dashboard")).not.toBeInTheDocument();
  });

  it("persists collapse state to localStorage", async () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const toggle = screen.getByLabelText("Collapse sidebar");
    await userEvent.click(toggle);
    expect(localStorage.getItem("soleur:sidebar.main.collapsed")).toBe("1");
  });

  it("toggles sidebar on Cmd+B when on /dashboard", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(screen.getByLabelText("Expand sidebar")).toBeInTheDocument();
  });

  it("toggles sidebar on Ctrl+B when on /dashboard", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    fireEvent.keyDown(document, { key: "b", ctrlKey: true });
    expect(screen.getByLabelText("Expand sidebar")).toBeInTheDocument();
  });

  // AC5: ⌘B is now the SINGLE rail owner — it toggles the one rail on EVERY
  // section, including KB / Settings / Chat (the per-route handlers that
  // previously suppressed it there are gone).
  it("DOES toggle the single rail on Cmd+B when on /dashboard/kb route", () => {
    mockPathname = "/dashboard/kb/some-file";
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(screen.getByLabelText("Expand sidebar")).toBeInTheDocument();
  });

  it("DOES toggle the single rail on Cmd+B when on /dashboard/settings route", () => {
    mockPathname = "/dashboard/settings/team";
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(screen.getByLabelText("Expand sidebar")).toBeInTheDocument();
  });

  it("DOES toggle the single rail on Cmd+B when on /dashboard/chat route", () => {
    mockPathname = "/dashboard/chat/abc-123";
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(screen.getByLabelText("Expand sidebar")).toBeInTheDocument();
  });

  it("ignores Cmd+B when focus is in an input element", () => {
    render(
      <Wrap>
        <DashboardLayout>
          <input data-testid="test-input" />
        </DashboardLayout>
      </Wrap>,
    );
    const input = screen.getByTestId("test-input");
    fireEvent.keyDown(input, { key: "b", metaKey: true, bubbles: true });
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
  });

  it("ignores Cmd+B when focus is in a textarea", () => {
    render(
      <Wrap>
        <DashboardLayout>
          <textarea data-testid="test-textarea" />
        </DashboardLayout>
      </Wrap>,
    );
    const textarea = screen.getByTestId("test-textarea");
    fireEvent.keyDown(textarea, { key: "b", metaKey: true, bubbles: true });
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
  });
});
