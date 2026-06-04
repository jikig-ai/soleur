import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, within } from "@testing-library/react";
import { RailSlotHarness } from "./helpers/rail-slot-harness";

let mockPathname = "/dashboard/kb";

vi.mock("@/components/feature-flags/provider", () => ({
  FeatureFlagProvider: ({ children }: { children: React.ReactNode }) => children,
  useFeatureFlag: () => true,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  usePathname: () => mockPathname,
}));

vi.mock("next/dynamic", () => ({
  __esModule: true,
  default: () => () => null,
}));

vi.mock("@/components/kb/file-tree", () => ({
  FileTree: () => <div data-testid="file-tree">file tree</div>,
}));

vi.mock("@/components/kb/search-overlay", () => ({
  SearchOverlay: () => <div data-testid="search-overlay">search</div>,
}));

vi.mock("@/components/kb", () => ({
  DesktopPlaceholder: () => null,
  EmptyState: () => null,
  KbErrorBoundary: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  LoadingSkeleton: () => null,
  NoProjectState: () => null,
  UnknownError: () => null,
  WorkspaceNotReady: () => null,
}));

vi.mock("@/components/kb/get-ancestor-paths", () => ({
  getAncestorPaths: () => [],
}));

// Force mobile layout for sidebar collapse tests (desktop uses PanelGroup)
vi.mock("@/hooks/use-media-query", () => ({
  useMediaQuery: () => false,
}));

import KbLayout from "@/app/(dashboard)/dashboard/kb/layout";

describe("KB file tree lifts into the single nav rail slot (ADR-047)", () => {
  beforeEach(() => {
    mockPathname = "/dashboard/kb";
    localStorage.clear();
    vi.stubGlobal("fetch", vi.fn((url: string) => {
      if (url === "/api/kb/tree") {
        return Promise.resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve({ tree: { name: "root", children: [{ name: "file.md", children: [] }] } }),
        });
      }
      if (url === "/api/flags") {
        return Promise.resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve({}),
        });
      }
      return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({}) });
    }));
  });

  afterEach(() => {
    localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("portals the file tree + search overlay into the rail slot", async () => {
    render(
      <RailSlotHarness>
        <KbLayout>
          <div>content</div>
        </KbLayout>
      </RailSlotHarness>,
    );
    const slot = await screen.findByTestId("rail-slot-harness");
    expect(await within(slot).findByTestId("file-tree")).toBeInTheDocument();
    expect(within(slot).getByTestId("search-overlay")).toBeInTheDocument();
  });

  it("renders NO in-shell collapse button — collapse is owned by the unified rail (⌘B)", async () => {
    render(
      <RailSlotHarness>
        <KbLayout>
          <div>content</div>
        </KbLayout>
      </RailSlotHarness>,
    );
    await screen.findByTestId("file-tree");
    expect(screen.queryByLabelText("Collapse file tree")).not.toBeInTheDocument();
    expect(screen.queryByLabelText("Expand file tree")).not.toBeInTheDocument();
  });

  it("shows a labeled empty-state CTA in the rail when the KB has no docs (AC6)", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn((url: string) => {
        if (url === "/api/kb/tree") {
          return Promise.resolve({
            ok: true,
            status: 200,
            json: () =>
              Promise.resolve({ tree: { name: "root", children: [] } }),
          });
        }
        return Promise.resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve({}),
        });
      }),
    );
    render(
      <RailSlotHarness>
        <KbLayout>
          <div>content</div>
        </KbLayout>
      </RailSlotHarness>,
    );
    const slot = await screen.findByTestId("rail-slot-harness");
    const empty = await within(slot).findByTestId("kb-rail-empty");
    expect(empty).toHaveTextContent(/no documents yet/i);
    expect(
      within(empty).getByRole("link", { name: /connect a repo or add docs/i }),
    ).toBeInTheDocument();
  });

  it("renders nothing into the rail when there is no slot (top-level / no drill)", async () => {
    // No RailSlotProvider → the portal has no target and the tree no-ops.
    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );
    expect(screen.queryByTestId("file-tree")).not.toBeInTheDocument();
  });

  // AC6.3 (Sidebar-UX Issue 6) — collapsed: the search overlay + nested file tree
  // are still DOM-removed (a nested tree has no coherent 56px-safe icon-only form),
  // but the collapsed rail is NO LONGER empty — it renders a compact icon-only
  // affordance ("Browse files" to expand + "Sync now"). The stable `kb-rail-tree`
  // wrapper survives so the present/absent assertions are anchored.
  it("renders a collapsed icon-only affordance, tree DOM-removed (AC6.3)", async () => {
    render(
      <RailSlotHarness collapsed>
        <KbLayout>
          <div>content</div>
        </KbLayout>
      </RailSlotHarness>,
    );
    const slot = await screen.findByTestId("rail-slot-harness");
    expect(within(slot).getByTestId("kb-rail-tree")).toBeInTheDocument();
    // Nested tree + search are still removed (would clip at 56px) ...
    expect(within(slot).queryByTestId("file-tree")).not.toBeInTheDocument();
    expect(within(slot).queryByTestId("search-overlay")).not.toBeInTheDocument();
    // ... but the collapsed rail is meaningful, not blank.
    expect(
      within(slot).getByTestId("kb-rail-collapsed-expand"),
    ).toHaveAccessibleName(/browse files/i);
    // The second affordance is a tree REFRESH (not the repo "Sync now") — its
    // label must say so, so it is not confused with KbSyncStatus's POST sync.
    expect(
      within(slot).getByTestId("kb-rail-collapsed-refresh"),
    ).toHaveAccessibleName(/refresh/i);
  });

  it("the collapsed 'Browse files' affordance requests a rail expand (Issue 6)", async () => {
    const onExpand = vi.fn();
    window.addEventListener("soleur:rail-expand", onExpand);
    try {
      render(
        <RailSlotHarness collapsed>
          <KbLayout>
            <div>content</div>
          </KbLayout>
        </RailSlotHarness>,
      );
      const slot = await screen.findByTestId("rail-slot-harness");
      within(slot).getByTestId("kb-rail-collapsed-expand").click();
      expect(onExpand).toHaveBeenCalledTimes(1);
    } finally {
      window.removeEventListener("soleur:rail-expand", onExpand);
    }
  });

  // AC4 — expanded: the same wrapper holds the tree + search (no vacuous AC2).
  it("keeps the search + file tree present when expanded (AC4)", async () => {
    render(
      <RailSlotHarness collapsed={false}>
        <KbLayout>
          <div>content</div>
        </KbLayout>
      </RailSlotHarness>,
    );
    const wrapper = await screen.findByTestId("kb-rail-tree");
    expect(await within(wrapper).findByTestId("file-tree")).toBeInTheDocument();
    expect(within(wrapper).getByTestId("search-overlay")).toBeInTheDocument();
  });
});
