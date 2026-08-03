// #7186 — mobile drill-in navigation for the Knowledge Base.
//
// Written against the LAYOUT (app/(dashboard)/dashboard/kb/layout.tsx) with the
// breakpoint hook mocked, not against a not-yet-existing component, so the RED
// run fails on a missing `kb-browse-tree` query rather than a module-resolution
// error.

import {
  describe,
  it,
  expect,
  beforeEach,
  afterEach,
  vi,
} from "vitest";
import { render, screen, within, waitFor } from "@testing-library/react";
import { RailSlotHarness } from "./helpers/rail-slot-harness";

let mockPathname = "/dashboard/kb";
let mockIsDesktop = false;
// Flips the mocked FileTree into a throwing component so KbErrorBoundary
// coverage can be asserted at BOTH hosts from one file (vi.mock is file-scoped).
let fileTreeThrows = false;

vi.mock("@/hooks/use-media-query", () => ({
  useMediaQuery: () => mockIsDesktop,
}));

vi.mock("next/navigation", () => ({
  usePathname: () => mockPathname,
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn(), prefetch: vi.fn() }),
}));

vi.mock("@/components/feature-flags/provider", () => ({
  FeatureFlagProvider: ({ children }: { children: React.ReactNode }) => children,
  useFeatureFlag: () => false,
}));

vi.mock("@/hooks/use-active-repo", () => ({
  useActiveRepo: () => ({
    data: {
      workspaceId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      repoUrl: null,
      repoName: null,
      repoStatus: "ready",
      fellBackToSolo: false,
    },
  }),
}));

// Keeps the real <nav aria-label="Knowledge base file tree"> contract (the AC2
// containment anchor) while staying cheap and throw-controllable.
vi.mock("@/components/kb/file-tree", () => ({
  FileTree: () => {
    if (fileTreeThrows) throw new Error("file tree exploded");
    return (
      <nav aria-label="Knowledge base file tree" data-testid="file-tree">
        file tree
      </nav>
    );
  },
}));

const POPULATED = {
  tree: {
    name: "root",
    type: "directory",
    path: "",
    children: [{ name: "INDEX.md", type: "file", path: "INDEX.md" }],
  },
};
const EMPTY = { tree: { name: "root", type: "directory", path: "", children: [] } };

let treeFixture: typeof POPULATED | typeof EMPTY = POPULATED;
// The five members of the `fullWidth` set. AC3's viewport-invariance claim
// quantifies over ALL of them; pinning only "empty" let a `loading && !isDesktop`
// leak survive the whole suite (found by mutation, not by reading).
type FullWidthState = "loading" | "workspace-not-ready" | "not-found" | "unknown" | "empty";
let treeStatus: number | "pending" = 200;
const searchResults: { path: string; kind: string; matches: [] }[] = [];

const originalFetch = globalThis.fetch;

beforeEach(() => {
  mockPathname = "/dashboard/kb";
  mockIsDesktop = false;
  fileTreeThrows = false;
  treeFixture = POPULATED;
  treeStatus = 200;
  sessionStorage.clear();
  globalThis.fetch = vi.fn((input: RequestInfo | URL) => {
    const url = String(input);
    if (url.startsWith("/api/kb/tree")) {
      // "pending" models the FIRST paint: loading === true, which is the state
      // the D1 hydration argument rests on and which nothing asserted.
      if (treeStatus === "pending") return new Promise(() => {});
      if (treeStatus !== 200) {
        return Promise.resolve({
          ok: false,
          status: treeStatus,
          json: () => Promise.resolve({}),
        });
      }
      return Promise.resolve({
        ok: true,
        status: 200,
        json: () => Promise.resolve(treeFixture),
      });
    }
    if (url.startsWith("/api/kb/search")) {
      return Promise.resolve({
        ok: true,
        status: 200,
        json: () => Promise.resolve({ results: searchResults }),
      });
    }
    return Promise.resolve({
      ok: true,
      status: 200,
      json: () => Promise.resolve({}),
    });
  }) as unknown as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  sessionStorage.clear();
  vi.useRealTimers();
});

async function renderLayout() {
  const { default: KbLayout } = await import(
    "@/app/(dashboard)/dashboard/kb/layout"
  );
  // A FRESH element per rerender: React bails out of re-rendering a subtree
  // whose element is referentially identical to the previous one, which would
  // make a pathname flip a no-op and the case vacuously green.
  const makeTree = () => (
    <RailSlotHarness>
      <KbLayout>
        <div data-testid="doc-content">document body</div>
      </KbLayout>
    </RailSlotHarness>
  );
  return { ...render(makeTree()), makeTree };
}

describe("#7186 — mobile KB drill-in", () => {
  it("mobile + populated + landing: the tree fills the content column and the rail slot holds no tree (AC1/AC6)", async () => {
    await renderLayout();

    const browse = await screen.findByTestId("kb-browse-tree");
    expect(
      within(browse).getByRole("navigation", {
        name: /knowledge base file tree/i,
      }),
    ).toBeInTheDocument();

    const slot = screen.getByTestId("rail-slot-harness");
    expect(
      within(slot).queryByRole("navigation", {
        name: /knowledge base file tree/i,
      }),
    ).toBeNull();
  });

  it("mobile + populated + document route: the document fills the content column and the tree is back in the rail", async () => {
    mockPathname = "/dashboard/kb/INDEX.md";
    await renderLayout();

    expect(await screen.findByTestId("doc-content")).toBeInTheDocument();
    const slot = screen.getByTestId("rail-slot-harness");
    await waitFor(() =>
      expect(
        within(slot).getByRole("navigation", {
          name: /knowledge base file tree/i,
        }),
      ).toBeInTheDocument(),
    );
    expect(screen.queryByTestId("kb-browse-tree")).not.toBeInTheDocument();
  });

  it("mobile + empty tree: the fullWidth body is unchanged and the tree stays in the rail", async () => {
    treeFixture = EMPTY;
    await renderLayout();

    expect(await screen.findByTestId("kb-page-mobile-header")).toBeInTheDocument();
    const slot = screen.getByTestId("rail-slot-harness");
    expect(within(slot).getByTestId("kb-rail-tree")).toBeInTheDocument();
    expect(screen.queryByTestId("kb-browse-tree")).not.toBeInTheDocument();
  });

  // AC3, behavioural form: no viewport-derived value may reach the fullWidth
  // block. Parameterised over ALL FIVE fullWidth sub-states — pinning only
  // `empty` (as the first draft did) let a `loading && !isDesktop` leak survive
  // every one of the 49 tests.
  const FULL_WIDTH_STATES: { name: FullWidthState; arrange: () => void }[] = [
    { name: "loading", arrange: () => { treeStatus = "pending"; } },
    { name: "workspace-not-ready", arrange: () => { treeStatus = 503; } },
    { name: "not-found", arrange: () => { treeStatus = 404; } },
    { name: "unknown", arrange: () => { treeStatus = 500; } },
    { name: "empty", arrange: () => { treeFixture = EMPTY; } },
  ];

  it.each(FULL_WIDTH_STATES)(
    "the fullWidth block is viewport-invariant in the $name sub-state (AC3)",
    async ({ arrange }) => {
      arrange();
      const arranged = { treeStatus, treeFixture };

      mockIsDesktop = true;
      const desktop = await renderLayout();
      const desktopHtml = (
        await screen.findByTestId("kb-page-mobile-header")
      ).parentElement!.innerHTML;
      desktop.unmount();

      // beforeEach does not re-run between the two halves of one case.
      treeStatus = arranged.treeStatus;
      treeFixture = arranged.treeFixture;
      mockIsDesktop = false;
      await renderLayout();
      const mobileHtml = (
        await screen.findByTestId("kb-page-mobile-header")
      ).parentElement!.innerHTML;

      expect(mobileHtml).toBe(desktopHtml);
    },
  );

  // The `loading` term of `fullWidth` had NO assertion behind it: mutating it to
  // `loading ? false : (...)` left all 49 tests green, while on a real phone it
  // renders the browse view — a viewport-derived branch at first paint, which is
  // exactly the hydration class D1 exists to exclude.
  it("holds the fullWidth block while the tree fetch is pending, at BOTH viewports (D1 reason 1)", async () => {
    for (const isDesktop of [true, false]) {
      treeStatus = "pending";
      mockIsDesktop = isDesktop;
      const r = await renderLayout();
      expect(
        await screen.findByTestId("kb-page-mobile-header"),
      ).toBeInTheDocument();
      expect(screen.queryByTestId("kb-browse-tree")).not.toBeInTheDocument();
      expect(screen.queryByTestId("doc-content")).not.toBeInTheDocument();
      r.unmount();
    }
  });

  it("the #6917 stopgap is gone from the mobile landing (AC7b)", async () => {
    await renderLayout();
    await screen.findByTestId("kb-browse-tree");
    expect(screen.queryByText(/open a file to see it here/i)).toBeNull();
    expect(screen.queryByRole("button", { name: /browse files/i })).toBeNull();
  });

  it("desktop landing still renders the passive DesktopPlaceholder (AC7b)", async () => {
    mockIsDesktop = true;
    await renderLayout();
    await waitFor(() =>
      expect(screen.getByText(/select a file to view/i)).toBeInTheDocument(),
    );
    expect(screen.queryByText(/open a file to see it here/i)).toBeNull();
  });

  it("KbErrorBoundary catches a throwing tree at BOTH hosts (AC7b)", async () => {
    fileTreeThrows = true;
    // React logs the caught error; silence it so the run output stays readable.
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    try {
      // Content-column host (mobile landing).
      const mobile = await renderLayout();
      await waitFor(() =>
        expect(
          screen.getByText(/something went wrong loading this content/i),
        ).toBeInTheDocument(),
      );
      mobile.unmount();

      // Rail host (desktop landing).
      mockIsDesktop = true;
      await renderLayout();
      await waitFor(() =>
        expect(
          screen.getByText(/something went wrong loading this content/i),
        ).toBeInTheDocument(),
      );
    } finally {
      errSpy.mockRestore();
    }
  });

  // AC5a — the query is lifted out of SearchOverlay's local state so it
  // survives the drill-in round trip. rerender() on the SAME tree is what a
  // client-side nav does; a fresh render() would pass for the wrong reason.
  it("the search query survives browse → document → back (AC5a)", async () => {
    const { rerender, makeTree } = await renderLayout();
    await screen.findByTestId("kb-browse-tree");

    const input = screen.getByPlaceholderText(/search files/i);
    const { fireEvent } = await import("@testing-library/react");
    fireEvent.change(input, { target: { value: "roadmap" } });
    await waitFor(() =>
      expect(screen.getByDisplayValue("roadmap")).toBeInTheDocument(),
    );

    mockPathname = "/dashboard/kb/INDEX.md";
    rerender(makeTree());
    await screen.findByTestId("doc-content");

    mockPathname = "/dashboard/kb";
    rerender(makeTree());

    expect(await screen.findByDisplayValue("roadmap")).toBeInTheDocument();
  });

  // DC1 option (a), operator-approved 2026-08-03: the populated browse view
  // owns exactly one back affordance, pointing at /dashboard.
  it("the populated mobile browse view renders exactly one back affordance to /dashboard (DC1)", async () => {
    await renderLayout();
    await screen.findByTestId("kb-browse-tree");

    // Scoped to KbLayout: DashboardLayout (and its `drawer-back-to-menu`) is
    // not mounted here, so this counts the KB's OWN backs only — it is NOT the
    // composition-wide count. That one lives in the 390x844 e2e arm.
    const backs = screen.getAllByRole("link", { name: /back to menu/i });
    expect(backs).toHaveLength(1);
    expect(backs[0]).toHaveAttribute("href", "/dashboard");
  });

  it("does NOT render a back affordance on the mobile DOCUMENT route (the doc header owns that back)", async () => {
    mockPathname = "/dashboard/kb/INDEX.md";
    await renderLayout();
    await screen.findByTestId("doc-content");
    expect(screen.queryByRole("link", { name: /back to menu/i })).toBeNull();
  });
});
