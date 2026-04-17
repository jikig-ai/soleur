import { describe, it, expect, vi, beforeEach } from "vitest";
import { act, render, screen, waitFor } from "@testing-library/react";

const mockPush = vi.fn();
let mockPathname = "/dashboard/kb/knowledge-base/product/roadmap.md";
const stableRouter = {
  push: mockPush,
  back: vi.fn(),
  forward: vi.fn(),
  refresh: vi.fn(),
  replace: vi.fn(),
  prefetch: vi.fn(),
};

const mockSearchParams = new URLSearchParams();
vi.mock("next/navigation", () => ({
  useRouter: () => stableRouter,
  usePathname: () => mockPathname,
  useSearchParams: () => mockSearchParams,
}));

let mockIsDesktop = true;
vi.mock("@/hooks/use-media-query", () => ({
  useMediaQuery: () => mockIsDesktop,
}));

const mockTree = {
  tree: {
    name: "root",
    type: "directory",
    path: "",
    children: [
      { name: "roadmap.md", type: "file", path: "knowledge-base/product/roadmap.md" },
      { name: "vision.md", type: "file", path: "knowledge-base/product/vision.md" },
    ],
  },
};

const { React: MockReact } = vi.hoisted(() => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  return { React: require("react") };
});

vi.mock("react-resizable-panels", () => ({
  Group: MockReact.forwardRef(function MockGroup(props: Record<string, unknown>, ref: unknown) {
    return MockReact.createElement("div", { "data-testid": "panel-group", ref }, props.children);
  }),
  Panel: MockReact.forwardRef(function MockPanel(props: Record<string, unknown>, ref: unknown) {
    return MockReact.createElement(
      "div",
      {
        "data-testid": "panel",
        "data-default-size": props.defaultSize,
        ref,
      },
      props.children,
    );
  }),
  Separator: function MockSeparator() {
    return MockReact.createElement("div", { "data-testid": "panel-separator" });
  },
  usePanelRef: () => ({ current: { collapse: vi.fn(), expand: vi.fn(), isCollapsed: () => false } }),
  useGroupRef: () => ({ current: null }),
  useDefaultLayout: () => ({ defaultLayout: undefined, onLayoutChanged: vi.fn() }),
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => ({ names: {}, getDisplayName: (id: string) => id, getIconPath: () => null, loading: false }),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => ({
    messages: [],
    startSession: vi.fn(),
    resumeSession: vi.fn(),
    sendMessage: vi.fn(),
    sendReviewGateResponse: vi.fn(),
    status: "connected",
    disconnectReason: undefined,
    lastError: null,
    reconnect: vi.fn(),
    routeSource: null,
    activeLeaderIds: [],
    sessionConfirmed: true,
    usageData: null,
    realConversationId: null,
    resumedFrom: null,
  }),
}));

vi.mock("@/lib/analytics-client", () => ({ track: vi.fn() }));

beforeEach(() => {
  vi.clearAllMocks();
  mockPathname = "/dashboard/kb/knowledge-base/product/roadmap.md";
  mockIsDesktop = true;
  sessionStorage.clear();
  sessionStorage.setItem("kb.chat.sidebarOpen", "1");
  global.fetch = vi.fn().mockImplementation((url: string) => {
    if (url === "/api/flags") {
      return Promise.resolve({
        ok: true,
        status: 200,
        json: () => Promise.resolve({ "kb-chat-sidebar": true }),
      });
    }
    return Promise.resolve({
      ok: true,
      status: 200,
      json: () => Promise.resolve(mockTree),
    });
  });
});

describe("KbLayout — chat panel closes when switching documents", () => {
  async function loadLayout() {
    const mod = await import("@/app/(dashboard)/dashboard/kb/layout");
    return mod.default;
  }

  it("renders chat panel on initial mount when sidebarOpen is persisted", async () => {
    const KbLayout = await loadLayout();
    render(
      <KbLayout>
        <div data-testid="content-page">File content</div>
      </KbLayout>,
    );
    await waitFor(() => {
      expect(screen.getAllByTestId("panel").length).toBe(3);
    });
  });

  it("closes chat panel when the current document path changes", async () => {
    const KbLayout = await loadLayout();
    const { rerender } = render(
      <KbLayout>
        <div data-testid="content-page">File content</div>
      </KbLayout>,
    );
    await waitFor(() => {
      expect(screen.getAllByTestId("panel").length).toBe(3);
    });

    // Simulate user clicking a different file in the KB tree — pathname changes.
    await act(async () => {
      mockPathname = "/dashboard/kb/knowledge-base/product/vision.md";
      rerender(
        <KbLayout>
          <div data-testid="content-page">File content</div>
        </KbLayout>,
      );
    });

    await waitFor(() => {
      // Chat panel should have closed — only sidebar + doc viewer remain.
      expect(screen.getAllByTestId("panel").length).toBe(2);
      expect(screen.getAllByTestId("panel-separator").length).toBe(1);
    });
    // Persisted flag should also be cleared so a reload doesn't re-open stale chat.
    expect(sessionStorage.getItem("kb.chat.sidebarOpen")).toBe("0");
  });

  it("does not close chat when rerendering with the same document path", async () => {
    const KbLayout = await loadLayout();
    const { rerender } = render(
      <KbLayout>
        <div data-testid="content-page">File content</div>
      </KbLayout>,
    );
    await waitFor(() => {
      expect(screen.getAllByTestId("panel").length).toBe(3);
    });

    // Same path, force a rerender.
    await act(async () => {
      rerender(
        <KbLayout>
          <div data-testid="content-page">File content</div>
        </KbLayout>,
      );
    });

    await waitFor(() => {
      expect(screen.getAllByTestId("panel").length).toBe(3);
    });
  });
});
