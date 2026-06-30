import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

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
      onAuthStateChange: () => ({
        data: { subscription: { unsubscribe: vi.fn() } },
      }),
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

// Collapse-state signal. The dedicated ▢ collapse button was removed as a
// duplicate (the resize slider now owns collapse/expand), so the button's
// aria-label is no longer a usable probe. The route-independent signal is the
// <aside> width class: md:w-56 expanded, md:w-14 collapsed, md:w-0 hidden.
function asideOf(container: HTMLElement): HTMLElement {
  const aside = container.querySelector("aside");
  if (!aside) throw new Error("sidebar <aside> not found");
  return aside as HTMLElement;
}
const isCollapsed = (aside: HTMLElement) => aside.className.includes("md:w-14");
const isExpanded = (aside: HTMLElement) => aside.className.includes("md:w-56");

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

  // Both collapse/expand affordances are present: the floated « toggle button
  // AND the resize slider. (The full-hide 0px control was removed.)
  it("renders both the collapse toggle button and the resize slider", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
    expect(screen.getByLabelText("Resize sidebar")).toBeInTheDocument();
    // Full-hide is gone — no "Hide sidebar" / "Show sidebar" controls remain.
    expect(screen.queryByLabelText("Hide sidebar")).not.toBeInTheDocument();
    expect(screen.queryByLabelText("Show sidebar")).not.toBeInTheDocument();
  });

  // The « toggle button collapses/expands; its aria-label flips with state.
  it("toggles collapse when the « toggle button is clicked", () => {
    const { container } = render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const aside = asideOf(container);
    expect(isExpanded(aside)).toBe(true);
    fireEvent.click(screen.getByLabelText("Collapse sidebar"));
    expect(isCollapsed(aside)).toBe(true);
    fireEvent.click(screen.getByLabelText("Expand sidebar"));
    expect(isExpanded(aside)).toBe(true);
  });

  // The toggle glyph rotates 180° (« → ») when collapsed so it reads as "expand".
  it("rotates the toggle glyph when collapsed", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const expandedGlyph = screen.getByLabelText("Collapse sidebar").querySelector("svg");
    expect(expandedGlyph?.getAttribute("class") ?? "").not.toContain("rotate-180");
    fireEvent.click(screen.getByLabelText("Collapse sidebar"));
    const collapsedGlyph = screen.getByLabelText("Expand sidebar").querySelector("svg");
    expect(collapsedGlyph?.getAttribute("class") ?? "").toContain("rotate-180");
  });

  // Double-clicking the slider also toggles collapse (second affordance).
  it("toggles collapse when the resize slider is double-clicked", () => {
    const { container } = render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const aside = asideOf(container);
    expect(isExpanded(aside)).toBe(true);
    fireEvent.doubleClick(screen.getByLabelText("Resize sidebar"));
    expect(isCollapsed(aside)).toBe(true);
    fireEvent.doubleClick(screen.getByLabelText("Resize sidebar"));
    expect(isExpanded(aside)).toBe(true);
  });

  it("adds title attributes to nav links when collapsed", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(screen.getByTitle("Dashboard")).toBeInTheDocument();
    expect(screen.getByTitle("Knowledge Base")).toBeInTheDocument();
    expect(screen.getByTitle("Settings")).toBeInTheDocument();
  });

  it("does not show title attributes when expanded", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    expect(screen.queryByTitle("Dashboard")).not.toBeInTheDocument();
  });

  it("persists collapse state to localStorage", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(localStorage.getItem("soleur:sidebar.main.collapsed")).toBe("1");
  });

  it("toggles sidebar on Cmd+B when on /dashboard", () => {
    const { container } = render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const aside = asideOf(container);
    expect(isExpanded(aside)).toBe(true);
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(isCollapsed(aside)).toBe(true);
  });

  it("toggles sidebar on Ctrl+B when on /dashboard", () => {
    const { container } = render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const aside = asideOf(container);
    fireEvent.keyDown(document, { key: "b", ctrlKey: true });
    expect(isCollapsed(aside)).toBe(true);
  });

  // AC5: ⌘B is now the SINGLE rail owner — it toggles the one rail on EVERY
  // section, including KB / Settings / Chat (the per-route handlers that
  // previously suppressed it there are gone).
  it("DOES toggle the single rail on Cmd+B when on /dashboard/kb route", () => {
    mockPathname = "/dashboard/kb/some-file";
    const { container } = render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const aside = asideOf(container);
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(isCollapsed(aside)).toBe(true);
  });

  it("DOES toggle the single rail on Cmd+B when on /dashboard/settings route", () => {
    mockPathname = "/dashboard/settings/team";
    const { container } = render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const aside = asideOf(container);
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(isCollapsed(aside)).toBe(true);
  });

  it("DOES toggle the single rail on Cmd+B when on /dashboard/chat route", () => {
    mockPathname = "/dashboard/chat/abc-123";
    const { container } = render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const aside = asideOf(container);
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(isCollapsed(aside)).toBe(true);
  });

  it("ignores Cmd+B when focus is in an input element", () => {
    const { container } = render(
      <Wrap>
        <DashboardLayout>
          <input data-testid="test-input" />
        </DashboardLayout>
      </Wrap>,
    );
    const aside = asideOf(container);
    const input = screen.getByTestId("test-input");
    fireEvent.keyDown(input, { key: "b", metaKey: true, bubbles: true });
    expect(isExpanded(aside)).toBe(true);
  });

  it("ignores Cmd+B when focus is in a textarea", () => {
    const { container } = render(
      <Wrap>
        <DashboardLayout>
          <textarea data-testid="test-textarea" />
        </DashboardLayout>
      </Wrap>,
    );
    const aside = asideOf(container);
    const textarea = screen.getByTestId("test-textarea");
    fireEvent.keyDown(textarea, { key: "b", metaKey: true, bubbles: true });
    expect(isExpanded(aside)).toBe(true);
  });
});
