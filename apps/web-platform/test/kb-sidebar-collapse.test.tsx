import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

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

describe("KB sidebar collapse", () => {
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

  it("renders a collapse toggle button for KB sidebar", async () => {
    render(<KbLayout><div>content</div></KbLayout>);
    await screen.findByTestId("file-tree");
    expect(screen.getByLabelText("Collapse file tree")).toBeInTheDocument();
  });

  it("toggles KB sidebar on click", async () => {
    render(<KbLayout><div>content</div></KbLayout>);
    await screen.findByTestId("file-tree");
    const toggle = screen.getByLabelText("Collapse file tree");
    await userEvent.click(toggle);
    expect(screen.getByLabelText("Expand file tree")).toBeInTheDocument();
  });

  // ⌘B is now owned solely by (dashboard)/layout.tsx (AC5); the KB file tree
  // no longer registers its own keydown handler. ⌘B behavior is covered in
  // dashboard-sidebar-collapse.test.tsx. Click-driven collapse (above) stays.

  it("preserves mobile class-swap behavior", async () => {
    mockPathname = "/dashboard/kb/somefile";
    render(<KbLayout><div>content</div></KbLayout>);
    await screen.findByTestId("file-tree");
    const aside = screen.getByTestId("file-tree").closest("aside");
    expect(aside).toBeInTheDocument();
    expect(aside!.className).toContain("hidden");
  });

  it("KB header row uses py-5 + min-h-7 to match main sidebar brand row height", async () => {
    render(<KbLayout><div>content</div></KbLayout>);
    await screen.findByTestId("file-tree");
    const collapseBtn = screen.getByLabelText("Collapse file tree");
    const headerRow = collapseBtn.closest("header");
    expect(headerRow).not.toBeNull();
    expect(headerRow?.className).toMatch(/\bpy-5\b/);
    expect(headerRow?.className).toMatch(/\bmin-h-7\b/);
    expect(headerRow?.className).toMatch(/\bflex\b/);
    expect(headerRow?.className).toMatch(/\bitems-center\b/);
    expect(headerRow?.className).toMatch(/\bjustify-between\b/);
    expect(headerRow?.className).not.toMatch(/\bpt-4\b/);
    expect(headerRow?.className).not.toMatch(/\bpb-3\b/);
  });
});
