import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

let mockPathname = "/dashboard";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  usePathname: () => mockPathname,
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

const HIDDEN_KEY = "soleur:sidebar.main.hidden";
const COLLAPSE_KEY = "soleur:sidebar.main.collapsed";

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

function getAside(container: HTMLElement): HTMLElement {
  const aside = container.querySelector("aside");
  if (!aside) throw new Error("expected an <aside> rail in the layout");
  return aside as HTMLElement;
}

describe("Dashboard sidebar full-hide (0px)", () => {
  beforeEach(() => {
    mockPathname = "/dashboard";
    localStorage.clear();
    vi.stubGlobal("matchMedia", stubMatchMedia);
  });

  afterEach(() => {
    localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("renders a Hide sidebar button when the rail is visible", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    expect(screen.getByLabelText("Hide sidebar")).toBeInTheDocument();
  });

  it("does not render the reveal button while the rail is visible", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    expect(screen.queryByTestId("sidebar-reveal-button")).not.toBeInTheDocument();
  });

  // jsdom has no layout engine, so this pins the width-class tokens that drive
  // the 0px hide; the pixel proof (content reclaims the row, no sliver) lives in
  // the e2e VRT gate.
  it("drives the aside to md:w-0 (overflow-hidden, border-r-0) when hidden, md:w-56 when visible", async () => {
    const { container } = render(
      <Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>,
    );
    const aside = getAside(container);
    expect(aside.className).toContain("md:w-56");
    expect(aside.className).not.toContain("md:w-0");

    await userEvent.click(screen.getByLabelText("Hide sidebar"));

    expect(aside.className).toContain("md:w-0");
    expect(aside.className).toContain("md:overflow-hidden");
    expect(aside.className).toContain("md:border-r-0");
    expect(aside.className).not.toContain("md:w-56");
  });

  it("swaps the Hide button for the floating reveal hamburger when hidden", async () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    await userEvent.click(screen.getByLabelText("Hide sidebar"));
    expect(screen.getByTestId("sidebar-reveal-button")).toBeInTheDocument();
    expect(screen.queryByLabelText("Hide sidebar")).not.toBeInTheDocument();
  });

  it("persists the hidden state under its own key (not the collapse key)", async () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    await userEvent.click(screen.getByLabelText("Hide sidebar"));
    expect(localStorage.getItem(HIDDEN_KEY)).toBe("1");
    expect(localStorage.getItem(COLLAPSE_KEY)).toBeNull();
  });

  it("restores the rail when the reveal button is clicked", async () => {
    const { container } = render(
      <Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>,
    );
    await userEvent.click(screen.getByLabelText("Hide sidebar"));
    await userEvent.click(screen.getByTestId("sidebar-reveal-button"));
    expect(screen.getByLabelText("Hide sidebar")).toBeInTheDocument();
    expect(screen.queryByTestId("sidebar-reveal-button")).not.toBeInTheDocument();
    expect(getAside(container).className).toContain("md:w-56");
    expect(localStorage.getItem(HIDDEN_KEY)).toBeNull();
  });

  it("hydrates the hidden state from localStorage on mount", () => {
    localStorage.setItem(HIDDEN_KEY, "1");
    const { container } = render(
      <Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>,
    );
    expect(getAside(container).className).toContain("md:w-0");
    expect(screen.getByTestId("sidebar-reveal-button")).toBeInTheDocument();
  });

  it("toggles hide on Cmd+Shift+B (and leaves collapse untouched)", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    fireEvent.keyDown(document, { key: "B", metaKey: true, shiftKey: true });
    expect(screen.getByTestId("sidebar-reveal-button")).toBeInTheDocument();
    // Collapse state is independent — the rail did not collapse.
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
  });

  it("toggles hide on Ctrl+Shift+B", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    fireEvent.keyDown(document, { key: "B", ctrlKey: true, shiftKey: true });
    expect(screen.getByTestId("sidebar-reveal-button")).toBeInTheDocument();
  });

  // Disjoint shortcuts: bare ⌘B collapses (does NOT hide); ⌘⇧B hides (does NOT
  // collapse). A single keystroke must never trigger both handlers.
  it("does not hide the rail on bare Cmd+B (collapse only)", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(screen.queryByTestId("sidebar-reveal-button")).not.toBeInTheDocument();
    // The rail collapsed instead.
    expect(screen.getByLabelText("Expand sidebar")).toBeInTheDocument();
  });

  it("does not collapse the rail on Cmd+Shift+B (hide only)", () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    fireEvent.keyDown(document, { key: "B", metaKey: true, shiftKey: true });
    // Still expanded (collapse label unchanged), just hidden.
    expect(screen.getByLabelText("Collapse sidebar")).toBeInTheDocument();
    expect(screen.getByTestId("sidebar-reveal-button")).toBeInTheDocument();
  });

  it("ignores Cmd+Shift+B when focus is in an input element", () => {
    render(
      <Wrap>
        <DashboardLayout>
          <input data-testid="test-input" />
        </DashboardLayout>
      </Wrap>,
    );
    const input = screen.getByTestId("test-input");
    fireEvent.keyDown(input, {
      key: "B",
      metaKey: true,
      shiftKey: true,
      bubbles: true,
    });
    expect(screen.queryByTestId("sidebar-reveal-button")).not.toBeInTheDocument();
  });

  // a11y (WCAG 2.4.3): the Hide button and reveal hamburger mount exclusively, so
  // activating one unmounts it — focus must hop to the control that takes over,
  // not drop to <body>.
  it("moves focus to the reveal hamburger after hiding", async () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    const hide = screen.getByLabelText("Hide sidebar");
    hide.focus();
    await userEvent.click(hide);
    expect(screen.getByTestId("sidebar-reveal-button")).toHaveFocus();
  });

  it("moves focus back to the Hide button after revealing", async () => {
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    await userEvent.click(screen.getByLabelText("Hide sidebar"));
    await userEvent.click(screen.getByTestId("sidebar-reveal-button"));
    expect(screen.getByLabelText("Hide sidebar")).toHaveFocus();
  });

  // The focus hop must fire ONLY on a user toggle — a persisted-hidden session
  // hydrates to hidden post-mount, and that must not yank focus to the hamburger.
  it("does not steal focus on a persisted-hidden first paint", () => {
    localStorage.setItem(HIDDEN_KEY, "1");
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    expect(screen.getByTestId("sidebar-reveal-button")).not.toHaveFocus();
  });

  it("marks the reveal hamburger as a collapsed disclosure (aria-expanded=false)", () => {
    localStorage.setItem(HIDDEN_KEY, "1");
    render(<Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>);
    expect(screen.getByTestId("sidebar-reveal-button")).toHaveAttribute(
      "aria-expanded",
      "false",
    );
  });

  // Double-click-the-bar-to-close. matchMedia must report desktop (the global
  // stub reports matches:false / mobile, where the gesture is intentionally off).
  const stubDesktop = () =>
    vi.stubGlobal("matchMedia", () => ({
      matches: true,
      addEventListener: () => {},
      removeEventListener: () => {},
    }));

  it("hides the rail on a double-click of the bar body (desktop)", () => {
    stubDesktop();
    const { container } = render(
      <Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>,
    );
    fireEvent.doubleClick(getAside(container));
    expect(getAside(container).className).toContain("md:w-0");
    expect(screen.getByTestId("sidebar-reveal-button")).toBeInTheDocument();
  });

  it("does NOT hide when a nav link is double-clicked (interactive-target guard)", () => {
    stubDesktop();
    const { container } = render(
      <Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>,
    );
    fireEvent.doubleClick(screen.getByRole("link", { name: "Knowledge Base" }));
    expect(getAside(container).className).not.toContain("md:w-0");
    expect(screen.queryByTestId("sidebar-reveal-button")).not.toBeInTheDocument();
  });

  it("does NOT hide on a bar double-click on mobile (gesture is desktop-only)", () => {
    // Global stub already reports matches:false (mobile).
    const { container } = render(
      <Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>,
    );
    fireEvent.doubleClick(getAside(container));
    expect(getAside(container).className).not.toContain("md:w-0");
  });

  it("renders a left-edge reveal strip when hidden, and clicking it restores the rail", async () => {
    localStorage.setItem(HIDDEN_KEY, "1");
    const { container } = render(
      <Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>,
    );
    const edge = screen.getByTestId("sidebar-reveal-edge");
    expect(edge).toBeInTheDocument();
    await userEvent.click(edge);
    expect(getAside(container).className).toContain("md:w-56");
    expect(screen.queryByTestId("sidebar-reveal-edge")).not.toBeInTheDocument();
    expect(screen.getByLabelText("Hide sidebar")).toBeInTheDocument();
  });

  it("washes the whole bar brand-gold while pressed, not grey", () => {
    const { container } = render(
      <Wrap><DashboardLayout><div>content</div></DashboardLayout></Wrap>,
    );
    const aside = getAside(container);
    const overlay = container.querySelector(
      '[data-testid="rail-gold-active-overlay"]',
    ) as HTMLElement;
    expect(overlay).not.toBeNull();
    expect(overlay.className).toContain("pointer-events-none");
    // Idle: brand gold at 0 alpha (invisible).
    expect(overlay.className).toContain("bg-soleur-accent-gold-fill/0");
    expect(overlay.className).not.toContain("bg-soleur-accent-gold-fill/40");

    // Press the bar → the whole-bar gold wash fades in.
    fireEvent.pointerDown(aside);
    expect(overlay.className).toContain("bg-soleur-accent-gold-fill/40");

    // Release → back to transparent.
    fireEvent.pointerUp(aside);
    expect(overlay.className).toContain("bg-soleur-accent-gold-fill/0");
    expect(overlay.className).not.toContain("bg-soleur-accent-gold-fill/40");
  });
});
