// #7186 — the ONE browse surface (`KbSidebarShell`) can be hosted in the nav
// rail (default, ADR-047) or in the mobile content column (`host="content"`).
// This suite is the RED for the `host` guard specifically, and it bisects the
// layout suite: a red host-table cell in kb-layout.test.tsx otherwise has ~5
// candidate causes.
//
// The collapsed case is the load-bearing one. `RailCollapsedProvider` wraps
// <main> in app/(dashboard)/layout.tsx — NOT just the rail — so a
// content-column host reads the SAME collapse context. Without the guard, a
// user who collapsed the desktop rail and then opens the KB on a phone gets a
// 56px two-icon strip as their entire browse view.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, within } from "@testing-library/react";
import { RailSlotHarness } from "./helpers/rail-slot-harness";

vi.mock("next/navigation", () => ({
  usePathname: () => "/dashboard/kb",
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
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

vi.mock("@/components/kb/file-tree", () => ({
  FileTree: () => <div data-testid="file-tree">file tree</div>,
}));

vi.mock("@/components/kb/search-overlay", () => ({
  SearchOverlay: () => <div data-testid="search-overlay">search</div>,
}));

import { KbSidebarShell } from "@/components/kb/kb-sidebar-shell";
import { KbContext, type KbContextValue } from "@/components/kb/kb-context";
import type { TreeNode } from "@/server/kb-reader";

const POPULATED_TREE = {
  name: "knowledge-base",
  path: "",
  type: "dir",
  children: [{ name: "overview", path: "overview", type: "dir", children: [] }],
} as unknown as TreeNode;

function ctx(overrides: Partial<KbContextValue> = {}): KbContextValue {
  return {
    tree: POPULATED_TREE,
    loading: false,
    error: null,
    expanded: new Set<string>(),
    toggleExpanded: vi.fn(),
    refreshTree: vi.fn(async () => {}),
    lastSync: null,
    needsReconnect: false,
    ...overrides,
  };
}

function renderShell(
  props: { host?: "rail" | "content" },
  { collapsed = false }: { collapsed?: boolean } = {},
) {
  return render(
    <RailSlotHarness collapsed={collapsed}>
      <KbContext.Provider value={ctx()}>
        <KbSidebarShell {...props} />
      </KbContext.Provider>
    </RailSlotHarness>,
  );
}

const originalFetch = globalThis.fetch;
beforeEach(() => {
  globalThis.fetch = vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: () => Promise.resolve({}),
  }) as unknown as typeof fetch;
});
afterEach(() => {
  globalThis.fetch = originalFetch;
});

describe("KbSidebarShell — host guard (#7186)", () => {
  it("default host renders the rail wrapper", () => {
    renderShell({});
    expect(screen.getByTestId("kb-rail-tree")).toBeInTheDocument();
    expect(screen.queryByTestId("kb-browse-tree")).not.toBeInTheDocument();
    expect(screen.getByTestId("file-tree")).toBeInTheDocument();
  });

  it("host='content' renders the browse wrapper instead of the rail wrapper", () => {
    renderShell({ host: "content" });
    const browse = screen.getByTestId("kb-browse-tree");
    expect(screen.queryByTestId("kb-rail-tree")).not.toBeInTheDocument();
    expect(within(browse).getByTestId("file-tree")).toBeInTheDocument();
    expect(within(browse).getByTestId("search-overlay")).toBeInTheDocument();
  });

  it("default host still honours rail collapse (56px icon strip)", () => {
    renderShell({}, { collapsed: true });
    expect(screen.getByTestId("kb-rail-collapsed-expand")).toBeInTheDocument();
    expect(screen.queryByTestId("file-tree")).not.toBeInTheDocument();
    expect(screen.queryByTestId("search-overlay")).not.toBeInTheDocument();
  });

  it("host='content' IGNORES rail collapse — a collapsed desktop rail must not shrink the mobile browse view", () => {
    renderShell({ host: "content" }, { collapsed: true });
    const browse = screen.getByTestId("kb-browse-tree");
    expect(within(browse).getByTestId("file-tree")).toBeInTheDocument();
    expect(within(browse).getByTestId("search-overlay")).toBeInTheDocument();
    expect(
      screen.queryByTestId("kb-rail-collapsed-expand"),
    ).not.toBeInTheDocument();
  });

  it("carries the tour anchor on whichever wrapper is hosting the tree", () => {
    const { unmount } = renderShell({});
    expect(screen.getByTestId("kb-rail-tree")).toHaveAttribute(
      "data-tour-id",
      "action:kb-tree",
    );
    unmount();
    renderShell({ host: "content" });
    expect(screen.getByTestId("kb-browse-tree")).toHaveAttribute(
      "data-tour-id",
      "action:kb-tree",
    );
  });
});
