import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { ThemeProvider } from "@/components/theme/theme-provider";
import { RailSlotPortal, useRailCollapsed } from "@/components/dashboard/rail-slot";

// #7222 — collapse must not leak below `md`.
//
// The regression this file pins is invisible to every existing rail test,
// because those run at happy-dom's default 1024px where the leak is CORRECT
// behaviour. It only appears when BOTH of these hold at once:
//   1. `soleur:sidebar.main.collapsed` is "1" (a persisted DESKTOP preference), and
//   2. the viewport is below `md`, where the `aside` is the full-width drawer.
// So every test here seeds localStorage explicitly. Without that seeding the
// assertions pass vacuously — `collapsed` is already false and nothing is
// being discriminated.

const COLLAPSE_KEY = "soleur:sidebar.main.collapsed";

/**
 * Query-aware matchMedia. The layout asks two OPPOSITE questions —
 * `useIsMobile` asks "(max-width: 767px)" and the drawer/expand effects ask
 * "(min-width: 768px)" — so a flat `matches: false` stub would answer "desktop"
 * to one and "desktop" to the other, and never model a phone.
 */
function stubViewport(mobile: boolean) {
  vi.stubGlobal("matchMedia", (query: string) => ({
    matches: query.includes("max-width") ? mobile : !mobile,
    media: query,
    addEventListener: () => {},
    removeEventListener: () => {},
  }));
}

const { pathnameRef } = vi.hoisted(() => ({
  pathnameRef: { current: "/dashboard" as string },
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  usePathname: () => pathnameRef.current,
  useParams: () => ({}),
}));

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
          maybeSingle: () => Promise.resolve({ data: null, error: null }),
        }),
      }),
    }),
    channel: () => ({
      on: vi.fn().mockReturnThis(),
      subscribe: vi.fn().mockReturnThis(),
    }),
    removeChannel: vi.fn(),
    removeAllChannels: vi.fn(() => Promise.resolve(["ok"])),
  }),
}));

vi.mock("@/hooks/use-team-names", () => ({
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
  useTeamNames: () => createUseTeamNamesMock(),
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

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
}));

/**
 * Reads the value the layout publishes on `RailCollapsedProvider` from INSIDE
 * the rail slot — i.e. exactly where the Settings sub-nav and the Conversations
 * rail read it. Asserting the published value rather than one consumer's
 * rendered output covers every consumer at once, including future ones.
 */
function CollapseProbe() {
  const collapsed = useRailCollapsed();
  return <span data-testid="collapse-probe">{String(collapsed)}</span>;
}

async function renderDashboard(pathname: string) {
  pathnameRef.current = pathname;
  const { default: DashboardLayout } = await import("@/app/(dashboard)/layout");
  return render(
    <ThemeProvider>
      <DashboardLayout>
        <RailSlotPortal>
          <CollapseProbe />
        </RailSlotPortal>
      </DashboardLayout>
    </ThemeProvider>,
  );
}

beforeEach(() => {
  localStorage.clear();
  vi.stubGlobal(
    "fetch",
    vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ isAdmin: false }),
      } as Response),
    ),
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
  localStorage.clear();
  cleanup();
});

describe("#7222 — rail collapse is a desktop-only concept", () => {
  it("publishes collapsed=false to the rail slot on mobile even when the preference is set", async () => {
    localStorage.setItem(COLLAPSE_KEY, "1");
    stubViewport(true);
    await renderDashboard("/dashboard/settings");

    expect(screen.getByTestId("collapse-probe")).toHaveTextContent("false");
  });

  it("still publishes collapsed=true on desktop with the same preference", async () => {
    localStorage.setItem(COLLAPSE_KEY, "1");
    stubViewport(false);
    await renderDashboard("/dashboard/settings");

    // The discriminator for the test above: if this asserted "false" too, the
    // mobile assertion would prove nothing about the breakpoint.
    expect(screen.getByTestId("collapse-probe")).toHaveTextContent("true");
  });

  it("keeps the three-segment theme selector on mobile with the preference set", async () => {
    localStorage.setItem(COLLAPSE_KEY, "1");
    stubViewport(true);
    await renderDashboard("/dashboard");

    // Collapsed renders the icon-only cycle button instead of the segmented
    // control — the exact swap the operator flagged in the drawer.
    expect(screen.queryByTestId("theme-cycle-button")).toBeNull();
    expect(screen.getByRole("group", { name: /theme/i })).toBeInTheDocument();
  });

  it("degrades the theme control to the cycle button on a collapsed DESKTOP rail", async () => {
    localStorage.setItem(COLLAPSE_KEY, "1");
    stubViewport(false);
    await renderDashboard("/dashboard");

    expect(screen.getByTestId("theme-cycle-button")).toBeInTheDocument();
  });

  it("does not clobber the persisted desktop preference from a mobile session", async () => {
    localStorage.setItem(COLLAPSE_KEY, "1");
    stubViewport(true);
    await renderDashboard("/dashboard/settings");

    // The fix gates the DERIVED value, not the stored one: a phone must not
    // silently expand the user's desktop rail on their next laptop visit.
    expect(localStorage.getItem(COLLAPSE_KEY)).toBe("1");
  });
});

describe("#7222 — the drawer 'Back to menu' keeps the brand-gold treatment", () => {
  it("renders drawer-back-to-menu in accent gold, not muted grey", async () => {
    stubViewport(true);
    await renderDashboard("/dashboard/settings");

    const back = screen.getByTestId("drawer-back-to-menu");
    // The colour IS the requirement here (#6915 lifted this affordance out of
    // the rail band and dropped its gold), so the token is the assertion.
    expect(back.className).toContain("text-soleur-accent-gold-fg");
    expect(back.className).not.toContain("text-soleur-text-muted");
  });
});
