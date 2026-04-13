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

// Need to mock kb-reader for the TreeNode type import (only used as type, but module must resolve)
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

describe("FileTree delete UI", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPathname = "/dashboard/kb";
    mockRefreshTree.mockResolvedValue(undefined);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("shows delete button on hover for attachment files", () => {
    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;

    // The delete button should exist (hidden until hover via CSS opacity)
    const deleteBtn = fileItem.querySelector('[aria-label*="elete"]') as HTMLElement;
    expect(deleteBtn).toBeTruthy();
  });

  it("does NOT show delete button for .md files", () => {
    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const mdLink = screen.getByText("readme.md");
    const mdItem = mdLink.closest("li")!;

    const deleteBtn = mdItem.querySelector('[aria-label*="elete"]');
    expect(deleteBtn).toBeNull();
  });

  it("shows confirmation dialog when delete is clicked", () => {
    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;
    const deleteBtn = fileItem.querySelector('[aria-label*="elete"]') as HTMLElement;

    fireEvent.click(deleteBtn);

    // Confirmation should show Cancel button
    expect(screen.getByRole("button", { name: /cancel/i })).toBeTruthy();
  });

  it("calls API and refreshes tree on confirm", async () => {
    vi.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      status: 200,
      json: () => Promise.resolve({ commitSha: "abc123" }),
    });

    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;
    const deleteBtn = fileItem.querySelector('[aria-label*="elete"]') as HTMLElement;

    fireEvent.click(deleteBtn);

    // Find and click the confirm button
    const confirmBtn = screen.getByRole("button", { name: /^delete$/i });
    fireEvent.click(confirmBtn);

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith(
        "/api/kb/file/overview/screenshot.png",
        expect.objectContaining({ method: "DELETE" }),
      );
    });

    await waitFor(() => {
      expect(mockRefreshTree).toHaveBeenCalled();
    });
  });

  it("returns to idle state when cancel is clicked", () => {
    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;
    const deleteBtn = fileItem.querySelector('[aria-label*="elete"]') as HTMLElement;

    fireEvent.click(deleteBtn);
    expect(screen.getByRole("button", { name: /cancel/i })).toBeTruthy();

    const cancelBtn = screen.getByRole("button", { name: /cancel/i });
    fireEvent.click(cancelBtn);

    // Confirmation should disappear
    expect(screen.queryByRole("button", { name: /cancel/i })).toBeNull();
  });

  it("shows error message on API failure with dismiss button", async () => {
    vi.spyOn(global, "fetch").mockResolvedValue({
      ok: false,
      status: 500,
      json: () => Promise.resolve({ error: "Internal server error" }),
    });

    setupKbMock(makeTree([overviewDir]));
    render(<FileTree />);

    const fileLink = screen.getByText("screenshot.png");
    const fileItem = fileLink.closest("li")!;
    const deleteBtn = fileItem.querySelector('[aria-label*="elete"]') as HTMLElement;

    fireEvent.click(deleteBtn);

    const confirmBtn = screen.getByRole("button", { name: /^delete$/i });
    fireEvent.click(confirmBtn);

    await waitFor(() => {
      const dismissBtn = screen.getByLabelText(/dismiss/i);
      expect(dismissBtn).toBeTruthy();
    });
  });
});
