import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, within } from "@testing-library/react";
import { RailSlotHarness } from "./helpers/rail-slot-harness";
import { SwrTestProvider } from "./helpers/swr-wrapper";

// Stable mock references (avoid useEffect re-fires)
const mockPush = vi.fn();
const mockRouter = { push: mockPush, back: vi.fn(), forward: vi.fn(), refresh: vi.fn(), replace: vi.fn(), prefetch: vi.fn() };
let mockPathname = "/dashboard/kb";
// #7186 — the ONE breakpoint authority for the KB layout. happy-dom has no real
// media queries, so the viewport axis of the AC2 host table is driven here.
// Defaults to desktop so every pre-existing case in this file is unaffected.
let mockIsDesktop = true;

vi.mock("@/hooks/use-media-query", () => ({
  useMediaQuery: () => mockIsDesktop,
}));

vi.mock("@/components/feature-flags/provider", () => ({
  FeatureFlagProvider: ({ children }: { children: React.ReactNode }) => children,
  useFeatureFlag: () => true,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => mockRouter,
  usePathname: () => mockPathname,
}));

// Mock fetch for /api/kb/tree
const mockTree = {
  tree: {
    name: "root",
    type: "directory",
    path: "",
    children: [
      {
        name: "engineering",
        type: "directory",
        path: "engineering",
        children: [
          {
            name: "specs",
            type: "directory",
            path: "engineering/specs",
            children: [
              { name: "file.md", type: "file", path: "engineering/specs/file.md" },
            ],
          },
        ],
      },
      { name: "INDEX.md", type: "file", path: "INDEX.md" },
    ],
  },
};

const emptyTree = { tree: { name: "root", type: "directory", path: "", children: [] } };

beforeEach(() => {
  vi.clearAllMocks();
  mockPathname = "/dashboard/kb";
  mockIsDesktop = true;
  global.fetch = vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: () => Promise.resolve(mockTree),
  });
});

describe("KbLayout", () => {
  it("renders FileTree in sidebar when viewing a content file", async () => {
    mockPathname = "/dashboard/kb/engineering/specs/file.md";

    const { default: KbLayout } = await import(
      "@/app/(dashboard)/dashboard/kb/layout"
    );

    render(
      <RailSlotHarness>
        <KbLayout>
          <div data-testid="content-page">File content here</div>
        </KbLayout>
      </RailSlotHarness>,
    );

    // Tree is portaled into the rail slot (ADR-047)
    const nav = await screen.findByRole("navigation", {
      name: /knowledge base file tree/i,
    });
    expect(nav).toBeInTheDocument();

    // Content should also render
    expect(screen.getByTestId("content-page")).toBeInTheDocument();
  });

  it("renders search overlay in sidebar when viewing a content file", async () => {
    mockPathname = "/dashboard/kb/engineering/specs/file.md";

    const { default: KbLayout } = await import(
      "@/app/(dashboard)/dashboard/kb/layout"
    );

    render(
      <RailSlotHarness>
        <KbLayout>
          <div>content</div>
        </KbLayout>
      </RailSlotHarness>,
    );

    // Wait for tree to load, then check search input is present
    await screen.findByRole("navigation", {
      name: /knowledge base file tree/i,
    });
    expect(screen.getByPlaceholderText("Search files...")).toBeInTheDocument();
  });

  it("renders the reconnect banner over an EMPTY tree when needsReconnect", async () => {
    mockPathname = "/dashboard/kb";
    // Ready workspace, NULL install id, EMPTY knowledge-base/ dir: the full-
    // width EmptyState branch renders (no tree children) — the banner must
    // still surface (#4712).
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          tree: { name: "root", type: "directory", path: "", children: [] },
          needsReconnect: true,
        }),
    });

    const { default: KbLayout } = await import(
      "@/app/(dashboard)/dashboard/kb/layout"
    );

    render(
      <SwrTestProvider>
        <KbLayout>
          <div>content</div>
        </KbLayout>
      </SwrTestProvider>,
    );

    expect(await screen.findByText(/can't sync/i)).toBeInTheDocument();
  });

  it("does NOT render the banner over an empty tree while needsReconnect is false", async () => {
    mockPathname = "/dashboard/kb";
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          tree: { name: "root", type: "directory", path: "", children: [] },
          needsReconnect: false,
        }),
    });

    const { default: KbLayout } = await import(
      "@/app/(dashboard)/dashboard/kb/layout"
    );

    render(
      <SwrTestProvider>
        <KbLayout>
          <div>content</div>
        </KbLayout>
      </SwrTestProvider>,
    );

    // Let the tree resolve (EmptyState renders) before asserting absence.
    await screen.findByText(/nothing here yet/i);
    expect(screen.queryByText(/can't sync/i)).not.toBeInTheDocument();
  });

  const EMPTY_TREE_FETCH = () =>
    vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () =>
        Promise.resolve({
          tree: { name: "root", type: "directory", path: "", children: [] },
          needsReconnect: false,
        }),
    });

  it("Phase 4 (#4915): the fullWidth page header shows the title; on the KB LANDING it OMITS the back (the persistent band owns it — one back per state)", async () => {
    mockPathname = "/dashboard/kb";
    global.fetch = EMPTY_TREE_FETCH();

    const { default: KbLayout } = await import(
      "@/app/(dashboard)/dashboard/kb/layout"
    );

    render(
      <SwrTestProvider>
        <KbLayout>
          <div>content</div>
        </KbLayout>
      </SwrTestProvider>,
    );

    // EmptyState (a fullWidth sub-state) has rendered.
    await screen.findByText(/nothing here yet/i);
    const header = screen.getByTestId("kb-page-mobile-header");
    // Title is always present (P0-1 / P2-4)…
    expect(within(header).getByText("Knowledge Base")).toBeInTheDocument();
    // …but on the landing the header must NOT duplicate the band's "Back to
    // menu" (the band's back is NOT suppressed on the landing path).
    expect(
      within(header).queryByRole("link", { name: /back to menu/i }),
    ).toBeNull();
  });

  it("Phase 4 (#4915): the fullWidth page header shows its OWN back in the KB DOC VIEW (where the band back is suppressed)", async () => {
    mockPathname = "/dashboard/kb/engineering/specs/file.md";
    global.fetch = EMPTY_TREE_FETCH();

    const { default: KbLayout } = await import(
      "@/app/(dashboard)/dashboard/kb/layout"
    );

    render(
      <SwrTestProvider>
        <KbLayout>
          <div>content</div>
        </KbLayout>
      </SwrTestProvider>,
    );

    await screen.findByText(/nothing here yet/i);
    const header = screen.getByTestId("kb-page-mobile-header");
    expect(within(header).getByText("Knowledge Base")).toBeInTheDocument();
    // In the doc view the band suppresses its back, so the page header owns it.
    expect(
      within(header).getByRole("link", { name: /back to menu/i }),
    ).toHaveAttribute("href", "/dashboard");
  });

  it("does not render FileTree twice at root path", async () => {
    mockPathname = "/dashboard/kb";

    const { default: KbLayout } = await import(
      "@/app/(dashboard)/dashboard/kb/layout"
    );

    render(
      <RailSlotHarness>
        <KbLayout>
          <div data-testid="page-content">page content</div>
        </KbLayout>
      </RailSlotHarness>,
    );

    await screen.findByRole("navigation", {
      name: /knowledge base file tree/i,
    });

    // Should only have one navigation element (tree portaled once into the slot)
    const navs = screen.getAllByRole("navigation", {
      name: /knowledge base file tree/i,
    });
    expect(navs).toHaveLength(1);
  });
});

// #7186 AC2 — the ONE file tree's HOST is a function of (viewport, route,
// fixture). Asserted by CONTAINMENT of the role="navigation" node, never by a
// wrapper testid: `kb-rail-tree` renders even when the tree is DOM-removed
// (kb-sidebar-shell.tsx wraps the collapsed branch too), so a testid the shell
// emits about its own placement agrees with a mis-placement bug.
describe("#7186 — file-tree host table (exactly one tree, in the named host)", () => {
  interface Cell {
    label: string;
    isDesktop: boolean;
    pathname: string;
    fixture: "populated" | "empty";
    expectedHost: "rail" | "content";
  }

  // Six cells, not eight: {desktop,doc,empty} and {mobile,doc,empty} are
  // redundant with their landing rows — in a fullWidth (empty) state the host
  // does not depend on the route.
  const CELLS: Cell[] = [
    { label: "desktop / landing / populated", isDesktop: true, pathname: "/dashboard/kb", fixture: "populated", expectedHost: "rail" },
    { label: "desktop / doc / populated", isDesktop: true, pathname: "/dashboard/kb/INDEX.md", fixture: "populated", expectedHost: "rail" },
    { label: "desktop / landing / empty", isDesktop: true, pathname: "/dashboard/kb", fixture: "empty", expectedHost: "rail" },
    { label: "mobile / landing / populated", isDesktop: false, pathname: "/dashboard/kb", fixture: "populated", expectedHost: "content" },
    { label: "mobile / doc / populated", isDesktop: false, pathname: "/dashboard/kb/INDEX.md", fixture: "populated", expectedHost: "rail" },
    { label: "mobile / landing / empty", isDesktop: false, pathname: "/dashboard/kb", fixture: "empty", expectedHost: "rail" },
  ];

  it.each(CELLS)(
    "$label → the tree is hosted in the $expectedHost",
    async ({ isDesktop, pathname, fixture, expectedHost }) => {
      mockIsDesktop = isDesktop;
      mockPathname = pathname;
      global.fetch = vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () =>
          Promise.resolve(fixture === "populated" ? mockTree : emptyTree),
      });

      const { default: KbLayout } = await import(
        "@/app/(dashboard)/dashboard/kb/layout"
      );
      render(
        <RailSlotHarness>
          <KbLayout>
            <div data-testid="page-content">page content</div>
          </KbLayout>
        </RailSlotHarness>,
      );

      const slot = await screen.findByTestId("rail-slot-harness");

      if (fixture === "empty") {
        // An empty tree renders RailEmptyState in place of FileTree, so the
        // correct nav count here is ZERO — asserting 1 would demand a tree that
        // must not exist. The invariant that still holds: the shell stays in
        // the rail and the content column never grows a browse host.
        await within(slot).findByTestId("kb-rail-empty");
        expect(within(slot).getByTestId("kb-rail-tree")).toBeInTheDocument();
        expect(
          screen.queryAllByRole("navigation", {
            name: /knowledge base file tree/i,
          }),
        ).toHaveLength(0);
        expect(screen.queryByTestId("kb-browse-tree")).not.toBeInTheDocument();
        return;
      }

      const navs = await screen.findAllByRole("navigation", {
        name: /knowledge base file tree/i,
      });
      expect(navs).toHaveLength(1);
      const nav = navs[0];

      if (expectedHost === "rail") {
        expect(slot).toContainElement(nav);
        expect(screen.queryByTestId("kb-browse-tree")).not.toBeInTheDocument();
      } else {
        expect(slot).not.toContainElement(nav);
        expect(screen.getByTestId("kb-browse-tree")).toContainElement(nav);
      }
    },
  );

  // The flip is driven by rerender() on the SAME tree: a fresh render() cannot
  // have a stale portal, which is the only failure mode this case exists to
  // catch (a portal that fails to unmount when the host changes).
  it("moves the single tree between hosts on a desktop↔mobile flip (no double mount)", async () => {
    mockIsDesktop = true;
    mockPathname = "/dashboard/kb";

    const { default: KbLayout } = await import(
      "@/app/(dashboard)/dashboard/kb/layout"
    );
    // A FRESH element per rerender: React bails out of re-rendering a subtree
    // whose element is referentially identical to the previous one, so reusing
    // one `tree` object makes the flip a no-op and the case vacuously green.
    const makeTree = () => (
      <RailSlotHarness>
        <KbLayout>
          <div data-testid="page-content">page content</div>
        </KbLayout>
      </RailSlotHarness>
    );
    const { rerender } = render(makeTree());

    const slot = await screen.findByTestId("rail-slot-harness");
    let navs = await screen.findAllByRole("navigation", {
      name: /knowledge base file tree/i,
    });
    expect(navs).toHaveLength(1);
    expect(slot).toContainElement(navs[0]);

    mockIsDesktop = false;
    rerender(makeTree());

    navs = await screen.findAllByRole("navigation", {
      name: /knowledge base file tree/i,
    });
    expect(navs).toHaveLength(1);
    expect(screen.getByTestId("rail-slot-harness")).not.toContainElement(
      navs[0],
    );
    expect(screen.getByTestId("kb-browse-tree")).toContainElement(navs[0]);

    mockIsDesktop = true;
    rerender(makeTree());

    navs = await screen.findAllByRole("navigation", {
      name: /knowledge base file tree/i,
    });
    expect(navs).toHaveLength(1);
    expect(screen.getByTestId("rail-slot-harness")).toContainElement(navs[0]);
    expect(screen.queryByTestId("kb-browse-tree")).not.toBeInTheDocument();
  });
});
