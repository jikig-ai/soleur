import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, within } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { ThemeProvider } from "@/components/theme/theme-provider";

// Integration coverage for feat-inbox-attention-badge: the badge is wired onto
// the Inbox nav item (only), and its real SWR + fetch path reads the active
// /api/inbox/emails feed. The component's zero/error/cap honesty contract is
// unit-tested in inbox-nav-badge.test.tsx (useSWR mocked); here we exercise the
// real fetcher end-to-end through the layout's <SWRConfig>.

const stubMatchMedia = () => ({
  matches: false,
  addEventListener: () => {},
  removeEventListener: () => {},
});

function Wrap({ children }: { children: React.ReactNode }) {
  return <ThemeProvider>{children}</ThemeProvider>;
}

const { pathnameRef, pushMock } = vi.hoisted(() => ({
  pathnameRef: { current: "/dashboard" as string },
  pushMock: vi.fn(),
}));

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
    removeAllChannels: vi.fn(() => Promise.resolve(["ok"])),
  }),
}));

vi.mock("@/hooks/use-team-names", () => ({
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
  useTeamNames: () => createUseTeamNamesMock(),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
}));

// The workspace context band (OrgSwitcher + LiveRepoBadge) runs its own async
// membership fetch that is orthogonal to this test; stub it so its data needs
// don't perturb the badge assertions. The badge lives in the nav map, not the
// band, so this does not remove anything under test.
vi.mock("@/components/dashboard/workspace-context-band", () => ({
  WorkspaceContextBand: () => null,
}));

function makeItems(n: number): Array<{ id: string }> {
  return Array.from({ length: n }, (_, i) => ({ id: `item-${i}` }));
}

// URL-routing fetch mock: inbox feed returns 4 active items; everything else
// (admin check, banners' self-gating probes) returns a benign empty body.
const fetchMock = vi.fn((input: RequestInfo | URL) => {
  const url = typeof input === "string" ? input : input.toString();
  if (url.startsWith("/api/inbox/emails")) {
    return Promise.resolve({
      ok: true,
      json: () => Promise.resolve({ items: makeItems(4) }),
    } as Response);
  }
  if (url.startsWith("/api/admin/check")) {
    return Promise.resolve({
      ok: true,
      json: () => Promise.resolve({ isAdmin: false }),
    } as Response);
  }
  return Promise.resolve({
    ok: true,
    json: () => Promise.resolve({}),
  } as Response);
});

beforeEach(() => {
  pathnameRef.current = "/dashboard";
  vi.stubGlobal("fetch", fetchMock);
  vi.stubGlobal("matchMedia", stubMatchMedia);
  try {
    localStorage.removeItem("soleur:sidebar.main.collapsed");
  } catch {
    // no-op
  }
});

afterEach(() => {
  vi.unstubAllGlobals();
  cleanup();
});

async function renderLayout() {
  const { default: DashboardLayout } = await import("@/app/(dashboard)/layout");
  return render(
    <Wrap>
      <DashboardLayout>
        <div data-testid="page">page</div>
      </DashboardLayout>
    </Wrap>,
  );
}

describe("DashboardLayout — Inbox attention badge", () => {
  it("renders the active-count badge inside the Inbox nav link (FR2)", async () => {
    await renderLayout();
    const inboxLink = screen.getByRole("link", { name: /inbox/i });
    const badge = await within(inboxLink).findByTestId("inbox-nav-badge");
    expect(badge).toHaveTextContent("4");
  });

  it("puts the badge on the Inbox item only — exactly one in the rail (NG2)", async () => {
    await renderLayout();
    // Wait for the shared fetch to resolve so a single-badge count is a real
    // result, not a not-yet-fetched race.
    const inboxLink = screen.getByRole("link", { name: /inbox/i });
    await within(inboxLink).findByTestId("inbox-nav-badge");
    // Exactly one badge across the whole nav rail, and it is the Inbox link's.
    const badges = screen.getAllByTestId("inbox-nav-badge");
    expect(badges).toHaveLength(1);
    expect(inboxLink).toContainElement(badges[0]!);
  });
});
