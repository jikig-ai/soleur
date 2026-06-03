import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";

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
    // Top-level chrome IS present at the top level (complements the drilled
    // absence assertion below — the Bug 1 fix must not hide it everywhere).
    expect(screen.getByText("Soleur")).toBeInTheDocument();
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
      // `Soleur` wordmark, the ThemeToggle, and the footer (Sign out) — must
      // NOT be in the drilled DOM. They render OUTSIDE the drill swap on the
      // buggy code (RED); the render-conditional fix removes them (GREEN).
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
});

// Widenable KB rail (amendment): the resize handle renders ONLY in the
// `drill === "kb" && !collapsed` branch (AC13 KB-only, AC12 collapse-precedence).
describe("KB rail resize handle gating (AC12/AC13)", () => {
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

  it("does NOT render the handle on Settings or Chat drills (KB-only, AC13)", () => {
    for (const path of ["/dashboard/settings", "/dashboard/chat/x"]) {
      mockPathname = path;
      const { unmount } = render(
        <Wrap>
          <DashboardLayout>
            <div>content</div>
          </DashboardLayout>
        </Wrap>,
      );
      expect(
        screen.queryByTestId("kb-rail-resize-handle"),
      ).not.toBeInTheDocument();
      unmount();
    }
  });

  it("does NOT render the handle when the rail is collapsed, even on KB (collapse precedence, AC12)", async () => {
    localStorage.setItem("soleur:sidebar.main.collapsed", "1");
    mockPathname = "/dashboard/kb";
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    // useSidebarCollapse hydrates collapse in a post-mount effect; wait for the
    // handle to disappear once collapsed=true settles.
    await waitFor(() =>
      expect(
        screen.queryByTestId("kb-rail-resize-handle"),
      ).not.toBeInTheDocument(),
    );
  });
});
