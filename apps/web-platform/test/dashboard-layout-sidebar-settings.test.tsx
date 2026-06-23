import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { ThemeProvider } from "@/components/theme/theme-provider";

const stubMatchMedia = () => ({
  matches: false,
  addEventListener: () => {},
  removeEventListener: () => {},
});

function Wrap({ children }: { children: React.ReactNode }) {
  return <ThemeProvider>{children}</ThemeProvider>;
}

const { pathnameRef, pushMock, signOutMock, removeAllChannelsMock } =
  vi.hoisted(() => ({
    pathnameRef: { current: "/dashboard" as string },
    pushMock: vi.fn(),
    signOutMock: vi.fn(
      (): Promise<{ error: Error | null }> => Promise.resolve({ error: null }),
    ),
    removeAllChannelsMock: vi.fn(() => Promise.resolve(["ok"])),
  }));

function setPathname(next: string) {
  pathnameRef.current = next;
}

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, refresh: vi.fn() }),
  usePathname: () => pathnameRef.current,
  useParams: () => ({}),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getSession: () =>
        Promise.resolve({ data: { session: null }, error: null }),
      getUser: () => Promise.resolve({ data: { user: null }, error: null }),
      signOut: signOutMock,
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
    removeAllChannels: removeAllChannelsMock,
  }),
}));

vi.mock("@/hooks/use-team-names", () => ({
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
  useTeamNames: () => createUseTeamNamesMock(),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
}));

const fetchMock = vi.fn(() =>
  Promise.resolve({
    ok: true,
    json: () => Promise.resolve({ isAdmin: false }),
  } as Response),
);

beforeEach(() => {
  setPathname("/dashboard");
  vi.stubGlobal("fetch", fetchMock);
  vi.stubGlobal("matchMedia", stubMatchMedia);
  fetchMock.mockClear();
  pushMock.mockClear();
  signOutMock.mockClear();
  removeAllChannelsMock.mockClear();
});

afterEach(() => {
  vi.unstubAllGlobals();
  cleanup();
});

async function renderDashboard() {
  const { default: DashboardLayout } = await import(
    "@/app/(dashboard)/layout"
  );
  return render(
    <Wrap>
      <DashboardLayout>
        <div data-testid="page">page</div>
      </DashboardLayout>
    </Wrap>,
  );
}

describe("DashboardLayout — Settings sidebar relocation", () => {
  it("renders exactly one Settings link, and it lives in the footer (not the top nav)", async () => {
    await renderDashboard();

    const settingsLinks = screen.getAllByRole("link", { name: /^settings$/i });
    expect(settingsLinks).toHaveLength(1);

    const status = screen.getByRole("link", { name: /^status$/i });
    // The single Settings link is a footer sibling of Status — i.e. the top
    // nav no longer renders a Settings entry. compareDocumentPosition with
    // DOCUMENT_POSITION_FOLLOWING is set when the argument node comes AFTER
    // the receiver; Status sits at the top of the footer, so Settings must
    // follow it.
    expect(
      status.compareDocumentPosition(settingsLinks[0]!) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  it("renders the sidebar footer in order: Status → Settings → Sign out", async () => {
    await renderDashboard();

    const status = screen.getByRole("link", { name: /^status$/i });
    const settings = screen.getByRole("link", { name: /^settings$/i });
    const signOut = screen.getByRole("button", { name: /^sign out$/i });

    expect(
      status.compareDocumentPosition(settings) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(
      settings.compareDocumentPosition(signOut) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  // ADR-047: on a /dashboard/settings route the rail now DRILLS — the primary
  // nav + footer (incl. this Settings link) are replaced by the Settings
  // sub-nav in the slot. The footer Settings link therefore only exists at the
  // top level (where it is never "active"); its drilled active-state moved to
  // the lifted sub-nav (settings-sidebar-collapse.test.tsx). The footer-order
  // tests above still exercise the top-level state.
});

describe("DashboardLayout — resizable rail mounts in all expanded drill states", () => {
  beforeEach(() => {
    // Expanded by default (no collapse seeded).
    try {
      localStorage.removeItem("soleur:sidebar.main.collapsed");
    } catch {
      // no-op
    }
  });

  it("mounts the resize grip on the NON-KB Dashboard rail, labeled generically (AC1, AC5)", async () => {
    setPathname("/dashboard");
    await renderDashboard();
    const grip = screen.getByTestId("kb-rail-resize-handle");
    expect(grip).toBeInTheDocument();
    expect(grip).toHaveAttribute("aria-label", "Resize sidebar");
  });

  it("mounts the resize grip on the Settings rail (AC1)", async () => {
    setPathname("/dashboard/settings");
    await renderDashboard();
    expect(screen.getByTestId("kb-rail-resize-handle")).toHaveAttribute(
      "aria-label",
      "Resize sidebar",
    );
  });

  it("drives the non-KB rail width via data-main-rail-width, not the fixed md:w-56 (AC2)", async () => {
    setPathname("/dashboard");
    const { container } = await renderDashboard();
    const aside = container.querySelector("aside");
    expect(aside).not.toBeNull();
    expect(aside).toHaveAttribute("data-main-rail-width");
    expect(aside).not.toHaveAttribute("data-kb-rail-width");
  });

  it("renders the grip as a SIBLING of the secondary slot, not nested inside it (AC7)", async () => {
    // Use a drilled route (Settings) so the overflow-y-auto secondary slot renders.
    setPathname("/dashboard/settings");
    await renderDashboard();
    const slot = screen.getByTestId("rail-secondary-slot");
    const grip = screen.getByTestId("kb-rail-resize-handle");
    expect(slot.contains(grip)).toBe(false);
  });

  it("DOES mount the grip when the rail is collapsed (sole expand affordance)", async () => {
    // useSidebarCollapse persists the collapsed state as the literal "1".
    try {
      localStorage.setItem("soleur:sidebar.main.collapsed", "1");
    } catch {
      // no-op
    }
    setPathname("/dashboard");
    await renderDashboard();
    // The dedicated ▢ collapse button was removed; the slider must stay mounted
    // even when collapsed so the user can drag/double-click to expand again.
    expect(screen.getByTestId("kb-rail-resize-handle")).toBeInTheDocument();
    try {
      localStorage.removeItem("soleur:sidebar.main.collapsed");
    } catch {
      // no-op
    }
  });

});
