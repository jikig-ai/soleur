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

  it("applies the active-state classes when on a /dashboard/settings route", async () => {
    setPathname("/dashboard/settings/billing");
    await renderDashboard();

    const settings = screen.getByRole("link", { name: /^settings$/i });

    expect(settings).toHaveAttribute("aria-current", "page");
    expect(settings.className).toContain("bg-soleur-bg-surface-2");
    expect(settings.className).toContain("text-soleur-text-primary");
  });
});
