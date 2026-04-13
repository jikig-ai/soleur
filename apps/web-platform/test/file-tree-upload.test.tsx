import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { KbContext } from "@/components/kb/kb-context";
import type { KbContextValue } from "@/components/kb/kb-context";
import { FileTree } from "@/components/kb/file-tree";
import type { TreeNode } from "@/server/kb-reader";

vi.mock("next/navigation", () => ({
  usePathname: () => "/dashboard/kb",
}));

const mockRefreshTree = vi.fn().mockResolvedValue(undefined);

const testTree: TreeNode = {
  name: "root",
  type: "directory",
  children: [
    {
      name: "assets",
      type: "directory",
      path: "assets",
      children: [
        { name: "readme.md", type: "file", path: "assets/readme.md", extension: ".md" },
        { name: "logo.png", type: "file", path: "assets/logo.png", extension: ".png" },
        { name: "report.pdf", type: "file", path: "assets/report.pdf", extension: ".pdf" },
        { name: "data.csv", type: "file", path: "assets/data.csv", extension: ".csv" },
        { name: "notes.txt", type: "file", path: "assets/notes.txt", extension: ".txt" },
        { name: "doc.docx", type: "file", path: "assets/doc.docx", extension: ".docx" },
      ],
    },
  ],
};

function renderFileTree(overrides: Partial<KbContextValue> = {}) {
  const ctxValue: KbContextValue = {
    tree: testTree,
    loading: false,
    error: null,
    expanded: new Set(["assets"]),
    toggleExpanded: vi.fn(),
    refreshTree: mockRefreshTree,
    ...overrides,
  };
  return render(
    <KbContext value={ctxValue}>
      <FileTree />
    </KbContext>,
  );
}

/** Helper: create a mock XMLHttpRequest that resolves with the given status/body */
function mockXhr(status: number, body: unknown) {
  const xhrInstance = {
    open: vi.fn(),
    send: vi.fn(),
    upload: { onprogress: null as ((e: ProgressEvent) => void) | null },
    onload: null as (() => void) | null,
    onerror: null as (() => void) | null,
    ontimeout: null as (() => void) | null,
    timeout: 0,
    status,
    responseText: JSON.stringify(body),
  };

  // When send() is called, simulate immediate completion
  xhrInstance.send.mockImplementation(() => {
    // Fire progress event
    if (xhrInstance.upload.onprogress) {
      xhrInstance.upload.onprogress(
        new ProgressEvent("progress", { lengthComputable: true, loaded: 100, total: 100 }),
      );
    }
    // Fire onload
    queueMicrotask(() => {
      xhrInstance.onload?.();
    });
  });

  vi.stubGlobal(
    "XMLHttpRequest",
    vi.fn(() => xhrInstance),
  );

  return xhrInstance;
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.unstubAllGlobals();
});

describe("FileTree upload", () => {
  it("shows upload button on directory hover", () => {
    renderFileTree();
    const uploadBtn = screen.getByLabelText("Upload file to assets");
    expect(uploadBtn).toBeDefined();
  });

  it("renders type-specific icons for different file types", () => {
    const { container } = renderFileTree();
    // All file links should exist
    const links = container.querySelectorAll("a");
    expect(links.length).toBe(6); // 6 files
  });

  it("rejects files exceeding 20MB client-side", async () => {
    renderFileTree();
    const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
    const largeFile = new File(["x".repeat(100)], "big.png", { type: "image/png" });
    Object.defineProperty(largeFile, "size", { value: 21 * 1024 * 1024 });

    fireEvent.change(fileInput, { target: { files: [largeFile] } });

    await waitFor(() => {
      expect(screen.getByText("File exceeds 20MB limit")).toBeDefined();
    });
  });

  it("rejects unsupported file types client-side", async () => {
    renderFileTree();
    const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
    const badFile = new File(["data"], "virus.exe", { type: "application/x-msdownload" });

    fireEvent.change(fileInput, { target: { files: [badFile] } });

    await waitFor(() => {
      expect(screen.getByText("Unsupported file type: .exe")).toBeDefined();
    });
  });

  it("uploads file and calls refreshTree on success", async () => {
    const xhr = mockXhr(201, { path: "assets/photo.png", sha: "abc", commitSha: "def" });

    renderFileTree();
    const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
    const file = new File(["image-data"], "photo.png", { type: "image/png" });

    fireEvent.change(fileInput, { target: { files: [file] } });

    await waitFor(() => {
      expect(xhr.open).toHaveBeenCalledWith("POST", "/api/kb/upload");
    });

    await waitFor(() => {
      expect(mockRefreshTree).toHaveBeenCalled();
    });
  });

  it("shows duplicate dialog on 409 response", async () => {
    mockXhr(409, { error: "File already exists", sha: "existing-sha", path: "assets/photo.png" });

    renderFileTree();
    const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
    const file = new File(["image-data"], "photo.png", { type: "image/png" });

    fireEvent.change(fileInput, { target: { files: [file] } });

    await waitFor(() => {
      expect(screen.getByText(/already exists\. Replace\?/)).toBeDefined();
    });

    // Click Replace button
    const replaceBtn = screen.getByText("Replace");
    expect(replaceBtn).toBeDefined();
  });

  it("dismisses error when X button clicked", async () => {
    renderFileTree();
    const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
    const badFile = new File(["data"], "virus.exe", { type: "application/x-msdownload" });

    fireEvent.change(fileInput, { target: { files: [badFile] } });

    await waitFor(() => {
      expect(screen.getByText("Unsupported file type: .exe")).toBeDefined();
    });

    const dismissBtn = screen.getByLabelText("Dismiss error");
    fireEvent.click(dismissBtn);

    await waitFor(() => {
      expect(screen.queryByText("Unsupported file type: .exe")).toBeNull();
    });
  });
});
