// @vitest-environment happy-dom
/**
 * KB tree scrollport restore (#4826 AC5).
 * Instruments scrollTop on the scrollport and asserts restore after mount.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, waitFor, act, fireEvent } from "@testing-library/react";
import { resumeKey } from "@/lib/nav-resume";

const WS = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";

vi.mock("next/navigation", () => ({
  usePathname: () => "/dashboard/kb/foo.md",
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
}));

vi.mock("@/hooks/use-active-repo", () => ({
  useActiveRepo: () => ({
    data: {
      workspaceId: WS,
      repoUrl: null,
      repoName: null,
      repoStatus: "ready",
      fellBackToSolo: false,
    },
  }),
}));

vi.mock("@/components/dashboard/rail-slot", () => ({
  useRailCollapsed: () => false,
  RAIL_EXPAND_EVENT: "soleur:rail-expand",
}));

vi.mock("@/components/kb/search-overlay", () => ({
  SearchOverlay: () => <div data-testid="search-overlay" />,
}));

vi.mock("@/components/kb/file-tree", () => ({
  FileTree: () => (
    <div style={{ height: 2000 }} data-testid="file-tree-tall">
      tall tree
    </div>
  ),
}));

vi.mock("@/components/kb/kb-sync-status", () => ({
  KbSyncStatus: () => null,
}));

vi.mock("@/components/dashboard/rail-empty-state", () => ({
  RailEmptyState: () => null,
}));

const mockTree = {
  name: "knowledge-base",
  path: "knowledge-base",
  type: "dir" as const,
  children: [
    {
      name: "foo.md",
      path: "knowledge-base/foo.md",
      type: "file" as const,
    },
  ],
};

vi.mock("@/components/kb/kb-context", () => ({
  useKb: () => ({
    tree: mockTree,
    loading: false,
    lastSync: null,
    refreshTree: vi.fn(),
    error: null,
    expanded: new Set(),
    toggleExpanded: vi.fn(),
    needsReconnect: false,
  }),
}));

import { KbSidebarShell } from "@/components/kb/kb-sidebar-shell";

describe("kb-tree-scroll-resume", () => {
  beforeEach(() => {
    sessionStorage.clear();
    sessionStorage.setItem(resumeKey(WS, "kb", "scrollTop"), "400");
  });

  afterEach(() => {
    sessionStorage.clear();
  });

  it("AC5: restores saved scrollTop once after tree mount", async () => {
    await act(async () => {
      render(
        <div style={{ height: 200 }}>
          <KbSidebarShell />
        </div>,
      );
    });

    const port = document.querySelector(
      '[data-testid="kb-tree-scrollport"]',
    ) as HTMLDivElement | null;
    expect(port).not.toBeNull();

    // happy-dom may not compute real scrollHeight from child height styles.
    // Force scroll metrics so the restore effect's gate can pass.
    Object.defineProperty(port!, "clientHeight", {
      configurable: true,
      get: () => 200,
    });
    Object.defineProperty(port!, "scrollHeight", {
      configurable: true,
      get: () => 2000,
    });
    // Trigger re-apply by dispatching a synthetic layout pass: remount effect
    // already scheduled rAF; flush timers + rAF.
    await act(async () => {
      await new Promise((r) => requestAnimationFrame(() => r(null)));
      await new Promise((r) => requestAnimationFrame(() => r(null)));
    });

    await waitFor(() => {
      expect(port!.scrollTop).toBe(400);
    });
  });

  it("persists scrollTop on scroll (rAF-coalesced)", async () => {
    // Start without a restored value so the restore effect does not fight us.
    sessionStorage.removeItem(resumeKey(WS, "kb", "scrollTop"));
    await act(async () => {
      render(
        <div style={{ height: 200 }}>
          <KbSidebarShell />
        </div>,
      );
    });
    const port = document.querySelector(
      '[data-testid="kb-tree-scrollport"]',
    ) as HTMLDivElement;
    Object.defineProperty(port, "clientHeight", {
      configurable: true,
      get: () => 200,
    });
    Object.defineProperty(port, "scrollHeight", {
      configurable: true,
      get: () => 2000,
    });

    // Define scrollTop as a real writable property (happy-dom sometimes no-ops).
    let top = 0;
    Object.defineProperty(port, "scrollTop", {
      configurable: true,
      get: () => top,
      set: (v: number) => {
        top = Number(v) || 0;
      },
    });
    top = 250;

    await act(async () => {
      fireEvent.scroll(port);
      await new Promise((r) => requestAnimationFrame(() => r(null)));
      await new Promise((r) => requestAnimationFrame(() => r(null)));
    });

    await waitFor(() => {
      expect(sessionStorage.getItem(resumeKey(WS, "kb", "scrollTop"))).toBe(
        "250",
      );
    });
  });
});
