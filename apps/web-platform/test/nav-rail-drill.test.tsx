import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, within } from "@testing-library/react";

// Stable module-level pathname mock — a fresh object each render would refire
// effects (learning 2026-04-07-userouter-mock-instability). One mutable string.
let mockPathname = "/dashboard";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  usePathname: () => mockPathname,
  useParams: () => ({}),
}));

vi.mock("@/hooks/use-conversations", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("@/hooks/use-conversations")>();
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
      onAuthStateChange: () => ({
        data: { subscription: { unsubscribe: vi.fn() } },
      }),
    },
    from: () => ({
      select: () => ({
        eq: () => ({
          single: () => Promise.resolve({ data: null, error: null }),
        }),
      }),
    }),
  }),
}));

import { createUseTeamNamesMock } from "./mocks/use-team-names";

vi.mock("@/hooks/use-team-names", () => ({
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
  useTeamNames: () => createUseTeamNamesMock(),
}));

import DashboardLayout from "@/app/(dashboard)/layout";
import { ThemeProvider } from "@/components/theme/theme-provider";
import { RailSlotPortal } from "@/components/dashboard/rail-slot";

const stubMatchMedia = () => ({
  matches: false,
  addEventListener: () => {},
  removeEventListener: () => {},
});

function Wrap({ children }: { children: React.ReactNode }) {
  return <ThemeProvider>{children}</ThemeProvider>;
}

describe("Single nav rail — URL-derived drill swap (AC3/AC4c)", () => {
  beforeEach(() => {
    mockPathname = "/dashboard";
    localStorage.clear();
    vi.stubGlobal("matchMedia", stubMatchMedia);
  });
  afterEach(() => {
    localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("shows the PRIMARY nav (and no secondary slot) at the top level", () => {
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    expect(
      screen.getByRole("link", { name: "Knowledge Base" }),
    ).toBeInTheDocument();
    expect(screen.queryByTestId("rail-secondary-slot")).not.toBeInTheDocument();
    // Phase 2 (#4915): the global "Soleur" wordmark is REMOVED entirely — the
    // workspace identity band is the sole orientation anchor now, so the
    // wordmark must be absent even at the top level (D4 borderless direction).
    expect(screen.queryByText("Soleur")).not.toBeInTheDocument();
  });

  it("places the theme toggle at the very BOTTOM of the rail — after the primary nav AND below Sign out (matches the D4 wireframe)", () => {
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    const theme = screen.getByRole("group", { name: /theme/i });
    const navLink = screen.getByRole("link", { name: "Knowledge Base" });
    // The theme control must FOLLOW the primary nav in the DOM (footer region),
    // not precede it (the old top-of-rail placement the wireframe rejects).
    expect(
      navLink.compareDocumentPosition(theme) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    // …and it is the LAST footer affordance — below Sign out (the quietest,
    // lowest-priority control sits at the very bottom of the rail).
    const signOut = screen.getByRole("button", { name: /sign out/i });
    expect(
      signOut.compareDocumentPosition(theme) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  it("KEEPS the primary nav on /dashboard/admin/analytics (allowlist, RQ6)", () => {
    mockPathname = "/dashboard/admin/analytics";
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    expect(
      screen.getByRole("link", { name: "Knowledge Base" }),
    ).toBeInTheDocument();
    expect(screen.queryByTestId("rail-secondary-slot")).not.toBeInTheDocument();
  });

  it.each(["/dashboard/kb", "/dashboard/settings/members", "/dashboard/chat/x"])(
    "swaps to the secondary slot (primary nav gone) when drilled: %s",
    (pathname) => {
      mockPathname = pathname;
      render(
        <Wrap>
          <DashboardLayout>
            <div>content</div>
          </DashboardLayout>
        </Wrap>,
      );
      expect(screen.getByTestId("rail-secondary-slot")).toBeInTheDocument();
      // primary nav items are replaced by the section's secondary nav
      expect(
        screen.queryByRole("link", { name: "Knowledge Base" }),
      ).not.toBeInTheDocument();

      // Bug 1 (DOM-presence half, jsdom-catchable): top-level chrome — the
      // ThemeToggle and the footer (Sign out) — must NOT be in the drilled DOM
      // (they render inside the `drill === null` swap). The "Soleur" wordmark is
      // removed entirely in Phase 2 (#4915), so it is absent in every state.
      expect(screen.queryByText("Soleur")).not.toBeInTheDocument();
      expect(
        screen.queryByRole("group", { name: "Theme" }),
      ).not.toBeInTheDocument();
      expect(
        screen.queryByRole("button", { name: /sign out/i }),
      ).not.toBeInTheDocument();
      // …but the workspace identity band still mounts when drilled (ADR-047).
      expect(
        screen.getAllByTestId("workspace-context-band").length,
      ).toBeGreaterThan(0);
    },
  );

  it("routes children through RailSlotProvider — a section can portal into the slot when drilled", () => {
    mockPathname = "/dashboard/settings";
    render(
      <Wrap>
        <DashboardLayout>
          <RailSlotPortal>
            <div data-testid="portaled-nav">section nav</div>
          </RailSlotPortal>
        </DashboardLayout>
      </Wrap>,
    );
    expect(screen.getByTestId("portaled-nav")).toBeInTheDocument();
    // and it lands inside the slot, not loose in the content
    const slot = screen.getByTestId("rail-secondary-slot");
    expect(slot).toContainElement(screen.getByTestId("portaled-nav"));
  });

  it("RQ1/AC1: renders BOTH a mobile-top-bar band and a rail band (CSS-placed, single importer)", () => {
    // Placement is CSS-driven (mobile bar is `md:hidden`, rail band is
    // `hidden md:block`) so identity + back chevron paint on the first frame
    // on every breakpoint — no JS viewport gate, no SSR/hydration identity gap.
    mockPathname = "/dashboard";
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    const variants = screen
      .getAllByTestId("workspace-context-band")
      .map((el) => el.getAttribute("data-variant"))
      .sort();
    expect(variants).toEqual(["mobile", "rail"]);
  });

  it("does NOT render portal content at the top level (slot absent)", () => {
    mockPathname = "/dashboard";
    render(
      <Wrap>
        <DashboardLayout>
          <RailSlotPortal>
            <div data-testid="portaled-nav">section nav</div>
          </RailSlotPortal>
        </DashboardLayout>
      </Wrap>,
    );
    expect(screen.queryByTestId("portaled-nav")).not.toBeInTheDocument();
  });

  // Phase 3 (#4915): one back control per state. In the mobile KB DOC VIEW the
  // kb-content-header owns the only back ("Back to file tree"), so the layout
  // passes suppressBack to the MOBILE band only — the desktop rail band keeps its
  // "Back to menu" (kb-content-header's back is md:hidden there, so no double).
  function bandsByVariant() {
    const map: Record<string, HTMLElement> = {};
    for (const el of screen.getAllByTestId("workspace-context-band")) {
      map[el.getAttribute("data-variant") ?? "?"] = el;
    }
    return map;
  }

  it("KB doc view: mobile band suppresses 'Back to menu'; rail band keeps it (one back per state)", () => {
    mockPathname = "/dashboard/kb/engineering/x.md";
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    const { mobile, rail } = bandsByVariant();
    expect(
      within(mobile).queryByTestId("nav-back-chevron"),
    ).not.toBeInTheDocument();
    expect(within(rail).getByTestId("nav-back-chevron")).toBeInTheDocument();
  });

  it("KB landing: mobile band back is suppressed — 'Back to menu' moved into the hamburger drawer", () => {
    // The mobile band no longer renders its own back in any drilled state; the
    // drilled drawer branch owns a single mobile-only "Back to menu" link, and
    // the desktop rail band keeps its back affordance.
    mockPathname = "/dashboard/kb";
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    const { mobile, rail } = bandsByVariant();
    expect(
      within(mobile).queryByTestId("nav-back-chevron"),
    ).not.toBeInTheDocument();
    expect(within(rail).getByTestId("nav-back-chevron")).toBeInTheDocument();
    // The drilled drawer branch owns a mobile-only "Back to menu" link.
    expect(screen.getByTestId("drawer-back-to-menu")).toBeInTheDocument();
  });

  // Phase 4 (#4915): on mobile KB the page body owns the "Knowledge Base" title,
  // so the layout suppresses the MOBILE band's section title; the desktop rail
  // band keeps it. Settings/Chat are unaffected (suppression is KB-scoped).
  it("KB: mobile band section title is suppressed (page body owns it); rail band keeps it", () => {
    mockPathname = "/dashboard/kb";
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    const { mobile, rail } = bandsByVariant();
    expect(
      within(mobile).queryByTestId("nav-section-title"),
    ).not.toBeInTheDocument();
    expect(within(rail).getByTestId("nav-section-title")).toBeInTheDocument();
  });

  it("Settings: the mobile band is switcher-only — no section title in any state (page body owns it); rail band keeps it", () => {
    // The mobile band moved into the hamburger drawer as a workspace-switcher-
    // only band (suppressBack + suppressSectionTitle), so it no longer carries a
    // section title for ANY drill; the page body's own title provides context.
    mockPathname = "/dashboard/settings";
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    const { mobile, rail } = bandsByVariant();
    expect(
      within(mobile).queryByTestId("nav-section-title"),
    ).not.toBeInTheDocument();
    expect(within(rail).getByTestId("nav-section-title")).toBeInTheDocument();
  });
});

// Widenable rail: the resize handle renders in EVERY state — every drill
// (KB / Settings / Chat / Dashboard) AND when collapsed (it is one of the two
// collapse/expand affordances, alongside the « toggle button). On non-KB rails
// the grip carries the generic "Resize sidebar" accessible name.
describe("rail resize handle gating (renders in every state)", () => {
  beforeEach(() => {
    mockPathname = "/dashboard";
    localStorage.clear();
    vi.stubGlobal("matchMedia", stubMatchMedia);
  });
  afterEach(() => {
    localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("renders the resize handle when drilled into KB and expanded", () => {
    mockPathname = "/dashboard/kb";
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    expect(screen.getByTestId("kb-rail-resize-handle")).toBeInTheDocument();
  });

  it("DOES render the handle on Settings and Chat drills, labeled generically", () => {
    for (const path of ["/dashboard/settings", "/dashboard/chat/x"]) {
      mockPathname = path;
      const { unmount } = render(
        <Wrap>
          <DashboardLayout>
            <div>content</div>
          </DashboardLayout>
        </Wrap>,
      );
      const handle = screen.getByTestId("kb-rail-resize-handle");
      expect(handle).toBeInTheDocument();
      expect(handle).toHaveAttribute("aria-label", "Resize sidebar");
      unmount();
    }
  });

  it("DOES render the handle when the rail is collapsed (one of two expand affordances)", () => {
    localStorage.setItem("soleur:sidebar.main.collapsed", "1");
    mockPathname = "/dashboard/kb";
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    // Even collapsed, the slider mounts so the user can drag/double-click to
    // expand again (the « toggle button is the other expand affordance).
    expect(screen.getByTestId("kb-rail-resize-handle")).toBeInTheDocument();
  });
});
