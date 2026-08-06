import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, act } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { ThemeProvider } from "@/components/theme/theme-provider";
import { RailSlotPortal, useRailCollapsed } from "@/components/dashboard/rail-slot";
import { CHAT_OVERLAY_OPEN_EVENT } from "@/components/chat/kb-chat-fullscreen";
import { NAV_DRAWER_REVEAL_EVENT } from "@/components/dashboard/nav-drawer-reveal-event";

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

// #7326 — a marker in place of the tour overlay, so the layout's TREE SHAPE can
// be asserted. The tour's nav-tab steps now open the drawer on purpose, and
// `<main>` goes `inert` whenever the drawer is open; if TourProvider ever moved
// inside that subtree, the tour card's own buttons would go dead on exactly
// those steps — silently, since `inert` neither throws nor logs.
vi.mock("@/components/tour/tour-provider", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("@/components/tour/tour-provider")>();
  return {
    ...actual,
    TourProvider: ({ children }: { children: React.ReactNode }) => (
      <div data-testid="tour-overlay-root">{children}</div>
    ),
  };
});

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
  // One shape for every endpoint the layout touches. `memberships: []` matters:
  // opening the drawer mounts OrgSwitcher, which indexes the array unguarded.
  vi.stubGlobal(
    "fetch",
    vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ isAdmin: false, memberships: [] }),
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

describe("#7222 — the nav drawer and the chat takeover are mutually exclusive", () => {
  it("closes the open drawer when a chat takeover announces itself", async () => {
    stubViewport(true);
    await renderDashboard("/dashboard/kb");

    const hamburger = screen.getByLabelText(/open (navigation|menu)/i);
    fireEvent.click(hamburger);
    expect(hamburger.getAttribute("aria-expanded")).toBe("true");

    // Both surfaces are `z-50` full-height. Paint order happens to favour the
    // portaled takeover today, but that is a property of DOM structure no test
    // asserts — so the layout makes the exclusivity a state invariant.
    await act(async () => {
      window.dispatchEvent(new Event(CHAT_OVERLAY_OPEN_EVENT));
    });

    expect(hamburger.getAttribute("aria-expanded")).toBe("false");
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

describe("#7326 — the guided tour reveals the nav drawer it talks about", () => {
  /**
   * Is the drawer `aside` translated ON screen?
   *
   * Tests for the ABSENCE of the closed class, not the presence of the open
   * one: the aside also carries an unconditional `md:translate-x-0`, so a
   * naive `includes("translate-x-0")` reports "open" in every state.
   */
  function drawerIsOpen() {
    const aside = document.querySelector("aside") as HTMLElement;
    return !aside.className.includes("-translate-x-full");
  }

  function dispatchReveal(open: boolean) {
    act(() => {
      window.dispatchEvent(
        new CustomEvent(NAV_DRAWER_REVEAL_EVENT, { detail: { open } }),
      );
    });
  }

  it("opens the drawer on a phone so a nav-tab step has something to spotlight", async () => {
    stubViewport(true);
    await renderDashboard("/dashboard");

    expect(drawerIsOpen()).toBe(false);
    dispatchReveal(true);
    expect(drawerIsOpen()).toBe(true);
  });

  it("closes it again when the tour moves off the step", async () => {
    stubViewport(true);
    await renderDashboard("/dashboard");

    dispatchReveal(true);
    dispatchReveal(false);
    expect(drawerIsOpen()).toBe(false);
  });

  it("IGNORES the open at md+ — drawerOpen also drives <main inert>", async () => {
    stubViewport(false);
    await renderDashboard("/dashboard");

    dispatchReveal(true);
    // On desktop the rail is always visible and there is no drawer to reveal;
    // honouring this would freeze the content pane behind an invisible one.
    const main = document.querySelector("main") as HTMLElement;
    expect(main.hasAttribute("inert")).toBe(false);
  });

  it("survives the step's own route change (which normally closes the drawer)", async () => {
    stubViewport(true);
    const { rerender } = await renderDashboard("/dashboard");

    dispatchReveal(true);
    expect(drawerIsOpen()).toBe(true);

    // Nav-tab steps carry BOTH a `route` and this reveal, and TourProvider
    // pushes the route first. Without the reveal guard the auto-close on
    // pathname change would shut the drawer one render after it opened —
    // precisely the frame the spotlight needs it open.
    pathnameRef.current = "/dashboard/inbox";
    const { default: DashboardLayout } = await import("@/app/(dashboard)/layout");
    await act(async () => {
      rerender(
        <ThemeProvider>
          <DashboardLayout>
            <RailSlotPortal>
              <CollapseProbe />
            </RailSlotPortal>
          </DashboardLayout>
        </ThemeProvider>,
      );
    });

    expect(drawerIsOpen()).toBe(true);
  });

  it("resumes closing on route change once the reveal is cleared", async () => {
    stubViewport(true);
    const { rerender } = await renderDashboard("/dashboard");

    dispatchReveal(true);
    dispatchReveal(false);

    pathnameRef.current = "/dashboard/inbox";
    const { default: DashboardLayout } = await import("@/app/(dashboard)/layout");
    await act(async () => {
      rerender(
        <ThemeProvider>
          <DashboardLayout>
            <RailSlotPortal>
              <CollapseProbe />
            </RailSlotPortal>
          </DashboardLayout>
        </ThemeProvider>,
      );
    });

    // The guard must not strand: a stuck flag would suppress the auto-close for
    // the rest of the session.
    expect(drawerIsOpen()).toBe(false);
  });

  it("a chat takeover opening clears the reveal as well as the drawer", async () => {
    stubViewport(true);
    await renderDashboard("/dashboard");

    dispatchReveal(true);
    act(() => {
      window.dispatchEvent(new Event(CHAT_OVERLAY_OPEN_EVENT));
    });
    expect(drawerIsOpen()).toBe(false);
  });
});

describe("#7326 — the tour overlay must stay outside the inert subtree", () => {
  it("mounts TourProvider as a sibling of <main>, never inside it", async () => {
    stubViewport(true);
    await renderDashboard("/dashboard");

    const main = document.querySelector("main") as HTMLElement;
    const tourRoot = screen.getByTestId("tour-overlay-root");
    expect(main.contains(tourRoot)).toBe(false);
  });

  it("keeps the tour reachable while a revealed drawer makes <main> inert", async () => {
    stubViewport(true);
    await renderDashboard("/dashboard");

    act(() => {
      window.dispatchEvent(
        new CustomEvent(NAV_DRAWER_REVEAL_EVENT, { detail: { open: true } }),
      );
    });

    const main = document.querySelector("main") as HTMLElement;
    // The drawer IS inert-ing the content pane — that part is intended.
    expect(main.hasAttribute("inert")).toBe(true);
    // ...and the tour is outside it, so Back/Skip/Next still work.
    expect(main.contains(screen.getByTestId("tour-overlay-root"))).toBe(false);
  });
});
