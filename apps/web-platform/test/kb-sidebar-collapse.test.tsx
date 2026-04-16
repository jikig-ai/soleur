import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

let mockPathname = "/dashboard/kb";

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

  it("Cmd+B toggles KB sidebar on /dashboard/kb routes", async () => {
    render(<KbLayout><div>content</div></KbLayout>);
    await screen.findByTestId("file-tree");
    fireEvent.keyDown(document, { key: "b", metaKey: true });
    expect(screen.getByLabelText("Expand file tree")).toBeInTheDocument();
  });

  it("Ctrl+B toggles KB sidebar", async () => {
    render(<KbLayout><div>content</div></KbLayout>);
    await screen.findByTestId("file-tree");
    fireEvent.keyDown(document, { key: "b", ctrlKey: true });
    expect(screen.getByLabelText("Expand file tree")).toBeInTheDocument();
  });

  it("ignores Cmd+B when focus is in an input", async () => {
    mockPathname = "/dashboard/kb/somefile";
    render(
      <KbLayout>
        <input data-testid="test-input" />
      </KbLayout>,
    );
    await screen.findByTestId("file-tree");
    const input = screen.getByTestId("test-input");
    fireEvent.keyDown(input, { key: "b", metaKey: true, bubbles: true });
    expect(screen.getByLabelText("Collapse file tree")).toBeInTheDocument();
  });

  it("preserves mobile class-swap behavior", async () => {
    mockPathname = "/dashboard/kb/somefile";
    render(<KbLayout><div>content</div></KbLayout>);
    await screen.findByTestId("file-tree");
    const aside = screen.getByTestId("file-tree").closest("aside");
    expect(aside).toBeInTheDocument();
    expect(aside!.className).toContain("hidden");
  });
});
