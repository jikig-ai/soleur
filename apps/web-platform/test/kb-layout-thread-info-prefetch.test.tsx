import { describe, it, expect, vi, beforeEach } from "vitest";
import { act, render, waitFor } from "@testing-library/react";

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

vi.mock("@/hooks/use-media-query", () => ({ useMediaQuery: () => true }));

const { React: MockReact } = vi.hoisted(() => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  return { React: require("react") };
});

vi.mock("react-resizable-panels", () => ({
  Group: MockReact.forwardRef(function G(p: Record<string, unknown>, r: unknown) {
    return MockReact.createElement("div", { "data-testid": "panel-group", ref: r }, p.children);
  }),
  Panel: MockReact.forwardRef(function P(p: Record<string, unknown>, r: unknown) {
    return MockReact.createElement("div", { "data-testid": "panel", ref: r }, p.children);
  }),
  Separator: () => MockReact.createElement("div", { "data-testid": "panel-separator" }),
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
    messages: [], startSession: vi.fn(), resumeSession: vi.fn(), sendMessage: vi.fn(),
    sendReviewGateResponse: vi.fn(), status: "connected", disconnectReason: undefined,
    lastError: null, reconnect: vi.fn(), routeSource: null, activeLeaderIds: [],
    sessionConfirmed: true, usageData: null, realConversationId: null, resumedFrom: null,
  }),
}));

vi.mock("@/lib/analytics-client", () => ({ track: vi.fn() }));

// Capture thread-info fetch calls separately from tree/flags fetches.
const threadInfoCalls: string[] = [];
const threadInfoResponses = new Map<string, number>();

beforeEach(() => {
  vi.clearAllMocks();
  mockPathname = "/dashboard/kb/knowledge-base/product/roadmap.md";
  threadInfoCalls.length = 0;
  threadInfoResponses.clear();
  sessionStorage.clear();
  global.fetch = vi.fn().mockImplementation((url: string) => {
    if (url === "/api/flags") {
      return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({ "kb-chat-sidebar": true }) });
    }
    if (url.startsWith("/api/chat/thread-info")) {
      threadInfoCalls.push(url);
      const cp = new URL(url, "http://localhost").searchParams.get("contextPath") ?? "";
      const mc = threadInfoResponses.get(cp) ?? 0;
      return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({ messageCount: mc }) });
    }
    return Promise.resolve({
      ok: true, status: 200, json: () => Promise.resolve({
        tree: { name: "root", type: "directory", path: "", children: [
          { name: "roadmap.md", type: "file", path: "knowledge-base/product/roadmap.md" },
          { name: "vision.md", type: "file", path: "knowledge-base/product/vision.md" },
        ]},
      }),
    });
  });
});

describe("KbLayout — thread-info prefetch", () => {
  async function loadLayout() {
    const mod = await import("@/app/(dashboard)/dashboard/kb/layout");
    return mod.default;
  }

  it("fetches thread-info for the initial contextPath", async () => {
    threadInfoResponses.set("knowledge-base/product/roadmap.md", 7);
    const KbLayout = await loadLayout();
    render(<KbLayout><div>c</div></KbLayout>);
    await waitFor(() => {
      expect(threadInfoCalls.some((u) => u.includes("knowledge-base%2Fproduct%2Froadmap.md"))).toBe(true);
    });
  });

  it("re-fetches thread-info when the document changes", async () => {
    threadInfoResponses.set("knowledge-base/product/roadmap.md", 5);
    threadInfoResponses.set("knowledge-base/product/vision.md", 0);
    const KbLayout = await loadLayout();
    const { rerender } = render(<KbLayout><div>c</div></KbLayout>);
    await waitFor(() => {
      expect(threadInfoCalls.some((u) => u.includes("roadmap.md"))).toBe(true);
    });

    await act(async () => {
      mockPathname = "/dashboard/kb/knowledge-base/product/vision.md";
      rerender(<KbLayout><div>c</div></KbLayout>);
    });

    await waitFor(() => {
      expect(threadInfoCalls.some((u) => u.includes("vision.md"))).toBe(true);
    });
  });

  it("does not fetch thread-info when contextPath is null (KB root)", async () => {
    mockPathname = "/dashboard/kb";
    const KbLayout = await loadLayout();
    render(<KbLayout><div>c</div></KbLayout>);
    // Give effects a chance to run.
    await waitFor(() => {
      expect((global.fetch as ReturnType<typeof vi.fn>).mock.calls.length).toBeGreaterThan(0);
    });
    expect(threadInfoCalls.length).toBe(0);
  });
});
