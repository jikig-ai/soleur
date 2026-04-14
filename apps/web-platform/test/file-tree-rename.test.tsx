import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import type { TreeNode } from "@/server/kb-reader";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted for use in vi.mock factories
// ---------------------------------------------------------------------------

const { mockRefreshTree, mockUseKb } = vi.hoisted(() => ({
  mockRefreshTree: vi.fn(),
  mockUseKb: vi.fn(),
}));

let mockPathname = "/dashboard/kb";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), back: vi.fn(), forward: vi.fn(), refresh: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
  usePathname: () => mockPathname,
}));

vi.mock("@/components/kb/kb-context", () => ({
  useKb: mockUseKb,
}));

vi.mock("@/server/kb-reader", () => ({
  readContent: vi.fn(),
  KbNotFoundError: class extends Error {},
  KbAccessDeniedError: class extends Error {},
  KbValidationError: class extends Error {},
}));

import { FileTree } from "@/components/kb/file-tree";

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const pngFile: TreeNode = {
  name: "screenshot.png",
  type: "file",
  path: "overview/screenshot.png",
  extension: ".png",
  modifiedAt: new Date().toISOString(),
};

const mdFile: TreeNode = {
  name: "readme.md",
  type: "file",
  path: "overview/readme.md",
  extension: ".md",
  modifiedAt: new Date().toISOString(),
};

const overviewDir: TreeNode = {
  name: "overview",
  type: "directory",
  path: "overview",
  children: [pngFile, mdFile],
};

function makeTree(children: TreeNode[]): TreeNode {
  return {
    name: "root",
    type: "directory",
    path: "",
    children,
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function setupKbMock(tree: TreeNode) {
  mockUseKb.mockReturnValue({
    tree,
    loading: false,
    error: null,
    expanded: new Set(["overview"]),
    toggleExpanded: vi.fn(),
    refreshTree: mockRefreshTree,
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("FileTree rename UI", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPathname = "/dashboard/kb";
    mockRefreshTree.mockResolvedValue(undefined);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("shows rename (pencil) button on hover for attachment files", () => {
    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;

    const renameBtn = fileItem.querySelector('[aria-label*="ename"]') as HTMLElement;
    expect(renameBtn).toBeTruthy();
  });

  it("does NOT show rename button for .md files", () => {
    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const mdLink = screen.getByText("readme.md");
    const mdItem = mdLink.closest("li")!;

    const renameBtn = mdItem.querySelector('[aria-label*="ename"]');
    expect(renameBtn).toBeNull();
  });

  it("enters edit mode when pencil icon is clicked, showing input with basename", () => {
    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;
    const renameBtn = fileItem.querySelector('[aria-label*="ename"]') as HTMLElement;

    fireEvent.click(renameBtn);

    const input = fileItem.querySelector("input[type='text']") as HTMLInputElement;
    expect(input).toBeTruthy();
    expect(input.value).toBe("screenshot");
  });

  it("displays extension as static suffix next to input in edit mode", () => {
    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;
    const renameBtn = fileItem.querySelector('[aria-label*="ename"]') as HTMLElement;

    fireEvent.click(renameBtn);

    // Extension should be visible as text after the input
    expect(fileItem.textContent).toContain(".png");
  });

  it("calls PATCH with new name on Enter and refreshes tree", async () => {
    vi.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      status: 200,
      json: () => Promise.resolve({ oldPath: "knowledge-base/overview/screenshot.png", newPath: "knowledge-base/overview/renamed.png", commitSha: "abc123" }),
    } as unknown as Response);

    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;
    const renameBtn = fileItem.querySelector('[aria-label*="ename"]') as HTMLElement;

    fireEvent.click(renameBtn);

    const input = fileItem.querySelector("input[type='text']") as HTMLInputElement;
    fireEvent.change(input, { target: { value: "renamed" } });
    fireEvent.keyDown(input, { key: "Enter" });

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith(
        "/api/kb/file/overview/screenshot.png",
        expect.objectContaining({
          method: "PATCH",
          body: JSON.stringify({ newName: "renamed.png" }),
        }),
      );
    });

    await waitFor(() => {
      expect(mockRefreshTree).toHaveBeenCalled();
    });
  });

  it("cancels edit mode on Escape without making API call", () => {
    const fetchSpy = vi.spyOn(global, "fetch");

    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;
    const renameBtn = fileItem.querySelector('[aria-label*="ename"]') as HTMLElement;

    fireEvent.click(renameBtn);

    const input = fileItem.querySelector("input[type='text']") as HTMLInputElement;
    fireEvent.change(input, { target: { value: "something-else" } });
    fireEvent.keyDown(input, { key: "Escape" });

    // Input should be gone
    expect(fileItem.querySelector("input[type='text']")).toBeNull();
    // No fetch call
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("confirms rename on blur", async () => {
    vi.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      status: 200,
      json: () => Promise.resolve({ oldPath: "a", newPath: "b", commitSha: "c" }),
    } as unknown as Response);

    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;
    const renameBtn = fileItem.querySelector('[aria-label*="ename"]') as HTMLElement;

    fireEvent.click(renameBtn);

    const input = fileItem.querySelector("input[type='text']") as HTMLInputElement;
    fireEvent.change(input, { target: { value: "blurred" } });
    fireEvent.blur(input);

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith(
        "/api/kb/file/overview/screenshot.png",
        expect.objectContaining({
          method: "PATCH",
          body: JSON.stringify({ newName: "blurred.png" }),
        }),
      );
    });
  });

  it("shows inline error on API failure", async () => {
    vi.spyOn(global, "fetch").mockResolvedValue({
      ok: false,
      status: 409,
      json: () => Promise.resolve({ error: "A file with that name already exists" }),
    } as unknown as Response);

    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;
    const renameBtn = fileItem.querySelector('[aria-label*="ename"]') as HTMLElement;

    fireEvent.click(renameBtn);

    const input = fileItem.querySelector("input[type='text']") as HTMLInputElement;
    fireEvent.change(input, { target: { value: "duplicate" } });
    fireEvent.keyDown(input, { key: "Enter" });

    await waitFor(() => {
      const dismissBtn = screen.getByLabelText(/dismiss/i);
      expect(dismissBtn).toBeTruthy();
    });
  });

  it("shows 'Renaming...' loading state during API call", async () => {
    // Never-resolving fetch to keep loading state
    vi.spyOn(global, "fetch").mockReturnValue(new Promise(() => {}));

    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;
    const renameBtn = fileItem.querySelector('[aria-label*="ename"]') as HTMLElement;

    fireEvent.click(renameBtn);

    const input = fileItem.querySelector("input[type='text']") as HTMLInputElement;
    fireEvent.change(input, { target: { value: "pending" } });
    fireEvent.keyDown(input, { key: "Enter" });

    await waitFor(() => {
      expect(fileItem.textContent).toContain("Renaming");
    });
  });
});
