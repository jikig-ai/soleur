import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, within } from "@testing-library/react";
import { RailSlotHarness } from "./helpers/rail-slot-harness";
import { SwrTestProvider } from "./helpers/swr-wrapper";

// Stable mock references (avoid useEffect re-fires)
const mockPush = vi.fn();
const mockRouter = { push: mockPush, back: vi.fn(), forward: vi.fn(), refresh: vi.fn(), replace: vi.fn(), prefetch: vi.fn() };
let mockPathname = "/dashboard/kb";

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

beforeEach(() => {
  vi.clearAllMocks();
  mockPathname = "/dashboard/kb";
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
