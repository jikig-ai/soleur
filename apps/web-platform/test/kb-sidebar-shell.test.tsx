// Fix A (kb-sync-affordance-reconcile) — the manual "Sync now" affordance must
// be reachable from the always-mounted rail (KbSidebarShell), WITHOUT first
// opening a file, including on the empty-tree ("No documents yet") branch — the
// exact stale/empty landing the incident hit. PR #4810's nav refactor removed
// the only mount (KbContentHeader, file-open route only); this restores it.
//
// Must live under test/**/*.test.tsx (vitest component/happy-dom glob).

import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest";
import {
  act,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";

// next/navigation — FileTree calls usePathname.
vi.mock("next/navigation", () => ({
  usePathname: () => "/dashboard/kb",
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
}));

// #4826 — shell pulls useNavResume → useActiveRepo; stub so the Sync-now
// AC-A3 assertion is not polluted by the active-repo SWR fetch.
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

const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;

beforeEach(() => {
  mockFetch.mockReset();
  globalThis.fetch = mockFetch as unknown as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = originalFetch;
});

import { KbSidebarShell } from "@/components/kb/kb-sidebar-shell";
import { KbContext, type KbContextValue } from "@/components/kb/kb-context";
import type { TreeNode } from "@/server/kb-reader";
import type { KbSyncHistoryRow } from "@/components/kb/kb-sync-status";

const POPULATED_TREE: TreeNode = {
  name: "knowledge-base",
  path: "",
  type: "dir",
  children: [
    { name: "overview", path: "overview", type: "dir", children: [] },
  ],
} as unknown as TreeNode;

function makeCtx(overrides: Partial<KbContextValue> = {}): KbContextValue {
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

function renderShell(ctx: KbContextValue) {
  return render(
    <KbContext.Provider value={ctx}>
      <KbSidebarShell />
    </KbContext.Provider>,
  );
}

describe("KbSidebarShell — manual sync affordance (Fix A)", () => {
  it("AC-A1/AC-A3: renders 'Sync now' with a populated tree", () => {
    renderShell(makeCtx());
    expect(screen.getByRole("button", { name: /sync now/i })).toBeTruthy();
  });

  it("AC-A2: renders 'Sync now' on the empty-tree ('No documents yet') branch", () => {
    renderShell(makeCtx({ tree: null }));
    // The empty-state CTA still renders…
    expect(screen.getByTestId("kb-rail-empty")).toBeTruthy();
    // …AND the sync affordance survives the empty branch.
    expect(screen.getByRole("button", { name: /sync now/i })).toBeTruthy();
  });

  it("AC-A4: renders the desync label from an ok:false lastSync row", () => {
    const desyncRow: KbSyncHistoryRow = {
      at: new Date().toISOString(),
      trigger: "webhook_push",
      ok: false,
      error_class: "non_fast_forward",
      sync_completed_at: Date.now(),
    };
    renderShell(makeCtx({ lastSync: desyncRow }));
    expect(screen.getByText(/out of sync/i)).toBeTruthy();
    expect(screen.getByRole("button", { name: /sync now/i })).toBeTruthy();
  });

  it("AC-A3: clicking 'Sync now' POSTs /api/kb/sync and calls refreshTree on success", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ ok: true, at: new Date().toISOString() }),
    });
    const refreshTree = vi.fn(async () => {});
    renderShell(makeCtx({ refreshTree }));

    const button = screen.getByRole("button", { name: /sync now/i });
    await act(async () => {
      fireEvent.click(button);
    });

    expect(mockFetch).toHaveBeenCalledTimes(1);
    const [url, init] = mockFetch.mock.calls[0];
    expect(url).toBe("/api/kb/sync");
    expect((init as RequestInit).method).toBe("POST");
    await waitFor(() => expect(refreshTree).toHaveBeenCalledTimes(1));
  });
});
