import { describe, test, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import { KbContext, type KbContextValue } from "@/components/kb/kb-context";
import type { UseKbLayoutStateResult } from "@/hooks/use-kb-layout-state";

// ---------------------------------------------------------------------------
// Mocks — keep the heavy KB shells out of the render so the test focuses on
// the reconnect banner gating + callback wiring.
// ---------------------------------------------------------------------------

vi.mock("@/components/kb/kb-sidebar-shell", () => ({
  KbSidebarShell: () => <div data-testid="sidebar-shell" />,
}));
vi.mock("@/components/kb/kb-doc-shell", () => ({
  KbDocShell: ({ children }: { children: React.ReactNode }) => (
    <div data-testid="doc-shell">{children}</div>
  ),
}));

const { mockUseReconnect } = vi.hoisted(() => ({
  mockUseReconnect: vi.fn((_onReconnected: () => void) => ({
    reconnect: vi.fn(),
    isPending: false,
  })),
}));
vi.mock("@/components/repo/use-reconnect", () => ({
  useReconnect: mockUseReconnect,
}));

import { KbDesktopLayout } from "@/components/kb/kb-desktop-layout";
import { KbMobileLayout } from "@/components/kb/kb-mobile-layout";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function makeCtx(overrides: Partial<KbContextValue> = {}): KbContextValue {
  return {
    tree: { name: "knowledge-base", path: "", type: "directory", children: [] },
    loading: false,
    error: null,
    expanded: new Set(),
    toggleExpanded: vi.fn(),
    refreshTree: vi.fn(async () => {}),
    lastSync: null,
    needsReconnect: false,
    ...overrides,
  };
}

// Minimal layout-state stub — the layouts destructure these fields.
function makeState(): UseKbLayoutStateResult {
  return {
    ctxValue: makeCtx(),
    chatCtxValue: {
      open: false,
      openSidebar: vi.fn(),
      closeSidebar: vi.fn(),
      contextPath: null,
      enabled: false,
      messageCount: 0,
      setMessageCount: vi.fn(),
    },
    isDesktop: true,
    isContentView: true,
    pathname: "/dashboard/kb",
    loading: false,
    error: null,
    hasTreeContent: true,
    kbCollapsed: false,
    toggleKbCollapsed: vi.fn(),
    contextPath: null,
    showChat: false,
    openSidebar: vi.fn(),
    closeSidebar: vi.fn(),
    chatPanelRef: { current: null } as unknown as UseKbLayoutStateResult["chatPanelRef"],
  };
}

function renderInCtx(
  ui: React.ReactElement,
  ctx: KbContextValue,
) {
  return render(<KbContext value={ctx}>{ui}</KbContext>);
}

describe.each([
  ["desktop", KbDesktopLayout],
  ["mobile", KbMobileLayout],
] as const)("KB reconnect banner — %s layout", (_name, Layout) => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockUseReconnect.mockReturnValue({ reconnect: vi.fn(), isPending: false });
  });

  test("does NOT render the banner when needsReconnect is false", () => {
    renderInCtx(
      <Layout state={makeState()}>content</Layout>,
      makeCtx({ needsReconnect: false }),
    );
    expect(screen.queryByText(/can't sync/i)).not.toBeInTheDocument();
  });

  test("renders the banner when needsReconnect is true", () => {
    renderInCtx(
      <Layout state={makeState()}>content</Layout>,
      makeCtx({ needsReconnect: true }),
    );
    expect(screen.getByText(/can't sync/i)).toBeInTheDocument();
  });

  test("wires refreshTree (not router.refresh) as onReconnected", () => {
    const refreshTree = vi.fn(async () => {});
    renderInCtx(
      <Layout state={makeState()}>content</Layout>,
      makeCtx({ needsReconnect: true, refreshTree }),
    );
    // ReconnectNotice forwards onReconnected → useReconnect(onReconnected).
    expect(mockUseReconnect).toHaveBeenCalled();
    const passed = mockUseReconnect.mock.calls.at(-1)?.[0];
    expect(passed).toBe(refreshTree);
  });
});
