import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, within } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { ThemeProvider } from "@/components/theme/theme-provider";

// Integration coverage for the nav attention badges: each badge (Inbox,
// Dashboard/conversations, Workstream) is wired onto its own nav item and its
// real SWR + fetch/count path runs through the layout's <SWRConfig>. The
// per-component honesty/predicate contracts are unit-tested in
// inbox-nav-badge / conversations-nav-badge / workstream-nav-badge tests
// (useSWR mocked); here we exercise the real fetchers end-to-end.

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

vi.mock("@/lib/supabase/client", () => {
  // Universal chainable query builder: supports both `.eq().single()` (layout's
  // subscription_status read) and the conversations count query
  // `.select(...).eq().eq().is().in()` (awaited → { count, error }).
  const makeChain = () => {
    const chain: Record<string, unknown> = {};
    for (const m of ["select", "eq", "is", "in"]) chain[m] = () => chain;
    chain.single = () => Promise.resolve({ data: null, error: null });
    chain.maybeSingle = () => Promise.resolve({ data: null, error: null });
    // Awaitable tail → the conversations attention count.
    chain.then = (resolve: (r: { count: number; error: null }) => void) =>
      resolve({ count: 3, error: null });
    return chain;
  };
  return {
    createClient: () => ({
      auth: {
        getSession: () =>
          Promise.resolve({ data: { session: null }, error: null }),
        // A real user id so the conversations count fetcher proceeds.
        getUser: () =>
          Promise.resolve({ data: { user: { id: "user-1" } }, error: null }),
        signOut: vi.fn(() => Promise.resolve({ error: null })),
        onAuthStateChange: () => ({
          data: { subscription: { unsubscribe: vi.fn() } },
        }),
      },
      from: () => makeChain(),
      channel: () => ({
        on: vi.fn().mockReturnThis(),
        subscribe: vi.fn().mockReturnThis(),
      }),
      removeChannel: vi.fn(),
      removeAllChannels: vi.fn(() => Promise.resolve(["ok"])),
    }),
  };
});

vi.mock("@/hooks/use-team-names", () => ({
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
  useTeamNames: () => createUseTeamNamesMock(),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
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
  if (url.startsWith("/api/workspace/active-repo")) {
    return Promise.resolve({
      ok: true,
      json: () =>
        Promise.resolve({
          repoUrl: "https://github.com/acme/repo",
          workspaceId: "ws-1",
        }),
    } as Response);
  }
  if (url.startsWith("/api/workstream/issues")) {
    // 2 attention items (blocked + ceo-assigned) among 3.
    return Promise.resolve({
      ok: true,
      json: () =>
        Promise.resolve({
          issues: [
            { id: "1", status: "blocked", assigneeRole: null },
            { id: "2", status: "todo", assigneeRole: "ceo" },
            { id: "3", status: "in_progress", assigneeRole: "cto" },
          ],
        }),
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
    // The count fetch fires exactly once — the badge does not double-fetch
    // /api/inbox/emails (it reuses the shared active-feed request; TR3).
    const inboxFetches = fetchMock.mock.calls.filter((c) =>
      String(c[0]).startsWith("/api/inbox/emails"),
    );
    expect(inboxFetches).toHaveLength(1);
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

describe("DashboardLayout — all three nav attention badges", () => {
  it("wires each badge to its own nav item (Inbox=4, Dashboard=3, Workstream=2)", async () => {
    await renderLayout();

    const inboxLink = screen.getByRole("link", { name: /inbox/i });
    const inboxBadge = await within(inboxLink).findByTestId("inbox-nav-badge");
    expect(inboxBadge).toHaveTextContent("4");

    // Dashboard nav item — the conversations attention count (supabase mock → 3).
    const dashLink = screen.getByRole("link", { name: /^dashboard/i });
    const dashBadge = await within(dashLink).findByTestId("dashboard-nav-badge");
    expect(dashBadge).toHaveTextContent("3");

    // Workstream nav item — 2 attention items (blocked + ceo) of 3.
    const wsLink = screen.getByRole("link", { name: /workstream/i });
    const wsBadge = await within(wsLink).findByTestId("workstream-nav-badge");
    expect(wsBadge).toHaveTextContent("2");

    // Each testid appears exactly once, on its own link.
    expect(screen.getAllByTestId("inbox-nav-badge")).toHaveLength(1);
    expect(screen.getAllByTestId("dashboard-nav-badge")).toHaveLength(1);
    expect(screen.getAllByTestId("workstream-nav-badge")).toHaveLength(1);
  });
});
