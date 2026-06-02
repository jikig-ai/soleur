import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";
import type { TreeNode } from "@/server/kb-reader";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted for use in vi.mock factories (mirrors file-tree-delete.test.tsx)
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
// Test data — root-LEVEL files and a root-level directory (the bug surface)
// ---------------------------------------------------------------------------

// INDEX.md: .md root file → isAttachment=false → strict no-edit-affordance case.
const rootMdFile: TreeNode = {
  name: "INDEX.md",
  type: "file",
  path: "INDEX.md",
  extension: ".md",
  modifiedAt: new Date().toISOString(),
};

// kb-tags.txt: .txt root file → isAttachment=true → still a FILE (a <Link>), even
// though it renders rename/delete affordances. Keying "is a file" on edit-button
// absence would be wrong; we key on the <Link> / absence-of-aria-expanded instead.
const rootTxtFile: TreeNode = {
  name: "kb-tags.txt",
  type: "file",
  path: "kb-tags.txt",
  extension: ".txt",
  modifiedAt: new Date().toISOString(),
};

const rootDir: TreeNode = {
  name: "engineering",
  type: "directory",
  path: "engineering",
  modifiedAt: new Date().toISOString(),
  children: [],
};

function makeTree(children: TreeNode[]): TreeNode {
  return { name: "root", type: "directory", path: "", children };
}

function setupKbMock(tree: TreeNode) {
  mockUseKb.mockReturnValue({
    tree,
    loading: false,
    error: null,
    expanded: new Set<string>(),
    toggleExpanded: vi.fn(),
    refreshTree: mockRefreshTree,
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("FileTree root-level file rendering", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPathname = "/dashboard/kb";
    mockRefreshTree.mockResolvedValue(undefined);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("renders a root-level .md file as a file link, not a directory", () => {
    setupKbMock(makeTree([rootMdFile]));
    const { container } = render(<FileTree />);

    // FileNode renders an <a href="/dashboard/kb/INDEX.md"> — the file shape.
    const link = screen.getByRole("link", { name: /INDEX\.md/ });
    expect(link.getAttribute("href")).toBe("/dashboard/kb/INDEX.md");

    // Directory affordances must be absent: no expand toggle, no upload button.
    expect(container.querySelector("[aria-expanded]")).toBeNull();
    expect(screen.queryByRole("button", { name: /Upload file to/i })).toBeNull();
  });

  it("renders a root-level .txt file as a file link even though it has edit affordances", () => {
    setupKbMock(makeTree([rootTxtFile]));
    const { container } = render(<FileTree />);

    const link = screen.getByRole("link", { name: /kb-tags\.txt/ });
    expect(link.getAttribute("href")).toBe("/dashboard/kb/kb-tags.txt");
    // Still a file: no directory expand toggle.
    expect(container.querySelector("[aria-expanded]")).toBeNull();
  });

  it("still renders a root-level directory as an expandable TreeItem", () => {
    setupKbMock(makeTree([rootDir]));
    render(<FileTree />);

    // Directory renders a button carrying aria-expanded.
    const dirButton = screen.getByRole("button", { expanded: false });
    expect(dirButton).toBeTruthy();
    // And it is NOT a link.
    expect(screen.queryByRole("link", { name: /engineering/ })).toBeNull();
  });

  it("renders mixed root-level files and directories correctly", () => {
    setupKbMock(makeTree([rootDir, rootMdFile, rootTxtFile]));
    const { container } = render(<FileTree />);

    // Exactly one expandable directory.
    expect(container.querySelectorAll("[aria-expanded]").length).toBe(1);
    // Both root files render as links.
    expect(screen.getByRole("link", { name: /INDEX\.md/ })).toBeTruthy();
    expect(screen.getByRole("link", { name: /kb-tags\.txt/ })).toBeTruthy();
  });
});
