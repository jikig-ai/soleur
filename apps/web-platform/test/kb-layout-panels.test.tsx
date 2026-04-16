import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";

// --- Mocks ---------------------------------------------------------------

const mockPush = vi.fn();
let mockPathname = "/dashboard/kb/knowledge-base/product/roadmap.md";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush, back: vi.fn(), forward: vi.fn(), refresh: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
  usePathname: () => mockPathname,
}));

let mockIsDesktop = true;
vi.mock("@/hooks/use-media-query", () => ({
  useMediaQuery: () => mockIsDesktop,
}));

// Mock fetch: /api/kb/tree succeeds, /api/flags returns kb-chat-sidebar=true
const mockTree = {
  tree: {
    name: "root",
    type: "directory",
    path: "",
    children: [{ name: "roadmap.md", type: "file", path: "knowledge-base/product/roadmap.md" }],
  },
};

// Track Panel/Group props for structural assertions
const capturedGroupProps: Record<string, unknown>[] = [];
const capturedPanelProps: Record<string, unknown>[] = [];
const capturedSeparatorProps: Record<string, unknown>[] = [];

vi.mock("react-resizable-panels", () => {
  const React = require("react");
  return {
    Group: React.forwardRef(function MockGroup(props: Record<string, unknown>, ref: unknown) {
      capturedGroupProps.push(props);
      return React.createElement("div", { "data-testid": "panel-group", ref }, props.children);
    }),
    Panel: React.forwardRef(function MockPanel(props: Record<string, unknown>, ref: unknown) {
      capturedPanelProps.push(props);
      return React.createElement("div", { "data-testid": "panel", "data-default-size": props.defaultSize, ref }, props.children);
    }),
    Separator: function MockSeparator(props: Record<string, unknown>) {
      capturedSeparatorProps.push(props);
      return React.createElement("div", { "data-testid": "panel-separator" });
    },
    usePanelRef: () => ({ current: { collapse: vi.fn(), expand: vi.fn(), isCollapsed: () => false } }),
    useGroupRef: () => ({ current: null }),
    useDefaultLayout: () => ({ defaultLayout: undefined, onLayoutChanged: vi.fn() }),
  };
});

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
  capturedGroupProps.length = 0;
  capturedPanelProps.length = 0;
  capturedSeparatorProps.length = 0;
  mockPathname = "/dashboard/kb/knowledge-base/product/roadmap.md";
  mockIsDesktop = true;
  sessionStorage.clear();
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

describe("KbLayout — resizable panels", () => {
  async function renderLayout() {
    const { default: KbLayout } = await import(
      "@/app/(dashboard)/dashboard/kb/layout"
    );
    return render(
      <KbLayout>
        <div data-testid="content-page">File content</div>
      </KbLayout>,
    );
  }

  it("renders a PanelGroup (Group) on desktop", async () => {
    await renderLayout();
    await waitFor(() => {
      expect(screen.getByTestId("panel-group")).toBeInTheDocument();
    });
  });

  it("renders three Panels: sidebar, doc viewer, chat", async () => {
    await renderLayout();
    await waitFor(() => {
      const panels = screen.getAllByTestId("panel");
      expect(panels.length).toBe(3);
    });
  });

  it("renders two Separators between panels", async () => {
    await renderLayout();
    await waitFor(() => {
      const separators = screen.getAllByTestId("panel-separator");
      expect(separators.length).toBe(2);
    });
  });

  it("Group has onLayoutChanged for persistence", async () => {
    await renderLayout();
    await waitFor(() => {
      expect(capturedGroupProps.some((p) => typeof p.onLayoutChanged === "function")).toBe(true);
    });
  });

  it("sidebar Panel has defaultSize=18, minSize=10, maxSize=25", async () => {
    await renderLayout();
    await waitFor(() => {
      const sidebar = capturedPanelProps.find(
        (p) => p.defaultSize === 18 && p.minSize === 10 && p.maxSize === 25,
      );
      expect(sidebar).toBeTruthy();
    });
  });

  it("chat Panel has defaultSize=22, minSize=20, maxSize=40, collapsible", async () => {
    await renderLayout();
    await waitFor(() => {
      const chat = capturedPanelProps.find(
        (p) => p.defaultSize === 22 && p.minSize === 20 && p.maxSize === 40 && p.collapsible,
      );
      expect(chat).toBeTruthy();
    });
  });

  it("all Panel children have min-w-0 class", async () => {
    await renderLayout();
    await waitFor(() => {
      const panels = screen.getAllByTestId("panel");
      for (const panel of panels) {
        // Each Panel's direct child div should have min-w-0
        const child = panel.firstElementChild;
        if (child) {
          expect(child.className).toContain("min-w-0");
        }
      }
    });
  });

  it("chat panel collapses at KB root (no document selected)", async () => {
    mockPathname = "/dashboard/kb";
    await renderLayout();
    await waitFor(() => {
      // At KB root, contextPath is null, so chat panel should not render
      // (or should collapse). With the plan's approach, chat Panel is always
      // present but collapsed. Since we can't test imperative collapse in
      // happy-dom, verify chat content is not rendered.
      expect(screen.queryByText("Close panel")).toBeNull();
    });
  });

  it("does not render Sheet (role=dialog) on desktop layout", async () => {
    await renderLayout();
    await waitFor(() => {
      expect(screen.getByTestId("panel-group")).toBeInTheDocument();
    });
    // Desktop uses PanelGroup, not Sheet — no dialog element should exist
    expect(screen.queryByRole("dialog")).toBeNull();
  });
});
