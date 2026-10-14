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
    lastSync: null,
    needsReconnect: false,
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
    vi.fn(function (this: Record<string, unknown>) {
      return xhrInstance;
    }),
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

  describe("markdown (.md) uploads", () => {
    const pick = (file: File) => {
      const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
      fireEvent.change(fileInput, { target: { files: [file] } });
    };

    it("offers .md in the picker accept list, derived from KB_UPLOAD_EXTENSIONS", async () => {
      const { KB_UPLOAD_EXTENSIONS } = await import("@/lib/kb-constants");
      renderFileTree();
      const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
      const accepted = fileInput.accept.split(",");
      expect(accepted).toContain(".md");
      // Pins the derivation: exactly the shared allowlist (existing csv/docx
      // entries unchanged), nothing duplicated locally.
      expect([...accepted].sort()).toEqual(
        KB_UPLOAD_EXTENSIONS.map((e) => `.${e}`).sort(),
      );
      for (const e of ["png", "jpg", "jpeg", "gif", "webp", "pdf", "csv", "txt", "docx"]) {
        expect(accepted).toContain(`.${e}`);
      }
    });

    it("fires the upload POST for onboarding-notes.md", async () => {
      const xhr = mockXhr(201, { path: "assets/onboarding-notes.md", sha: "a", commitSha: "b" });
      renderFileTree();
      pick(new File(["# notes"], "onboarding-notes.md", { type: "" }));

      await waitFor(() => {
        expect(xhr.open).toHaveBeenCalledWith("POST", "/api/kb/upload");
      });
      const sent = xhr.send.mock.calls[0][0] as FormData;
      expect((sent.get("file") as File).name).toBe("onboarding-notes.md");
      await waitFor(() => expect(mockRefreshTree).toHaveBeenCalled());
    });

    it("accepts an uppercase extension (NOTES.MD) client-side", async () => {
      const xhr = mockXhr(201, { path: "assets/NOTES.md", sha: "a", commitSha: "b" });
      renderFileTree();
      pick(new File(["# notes"], "NOTES.MD", { type: "text/markdown" }));
      await waitFor(() => {
        expect(xhr.open).toHaveBeenCalledWith("POST", "/api/kb/upload");
      });
    });

    it("rejects a .md over 1MB client-side without an XHR", async () => {
      const xhr = mockXhr(201, {});
      renderFileTree();
      const big = new File(["x"], "huge-notes.md", { type: "text/markdown" });
      Object.defineProperty(big, "size", { value: 1024 * 1024 + 1 });
      pick(big);

      await waitFor(() => {
        expect(screen.getByText("Markdown files cannot exceed 1MB")).toBeDefined();
      });
      expect(xhr.open).not.toHaveBeenCalled();
    });

    it("does not apply the 1MB cap to non-markdown files (2MB .txt goes through)", async () => {
      const xhr = mockXhr(201, { path: "assets/big.txt", sha: "a", commitSha: "b" });
      renderFileTree();
      const big = new File(["x"], "big.txt", { type: "text/plain" });
      Object.defineProperty(big, "size", { value: 2 * 1024 * 1024 });
      pick(big);
      await waitFor(() => {
        expect(xhr.open).toHaveBeenCalledWith("POST", "/api/kb/upload");
      });
    });

    it.each(["CLAUDE.md", "agents.md", "Skill.MD", "CLAUDE.local.md", "GEMINI.md"])(
      "refuses reserved instruction file %s client-side",
      async (name) => {
        const xhr = mockXhr(201, {});
        renderFileTree();
        pick(new File(["x"], name, { type: "text/markdown" }));
        await waitFor(() => {
          expect(screen.getByText("Reserved filename")).toBeDefined();
        });
        expect(xhr.open).not.toHaveBeenCalled();
      },
    );

    it.each(["md", ".md"])("rejects a file literally named `%s`", async (name) => {
      const xhr = mockXhr(201, {});
      renderFileTree();
      pick(new File(["x"], name, { type: "text/markdown" }));
      await waitFor(() => {
        expect(screen.getByText("Unsupported file type: .unknown")).toBeDefined();
      });
      expect(xhr.open).not.toHaveBeenCalled();
    });

    it("still rejects .exe", async () => {
      const xhr = mockXhr(201, {});
      renderFileTree();
      pick(new File(["x"], "virus.exe", { type: "application/x-msdownload" }));
      await waitFor(() => {
        expect(screen.getByText("Unsupported file type: .exe")).toBeDefined();
      });
      expect(xhr.open).not.toHaveBeenCalled();
    });

    it("a .md that collides with an authored doc shows the server's reason and NO Replace button", async () => {
      mockXhr(409, {
        error: "A markdown file with this name already exists",
        code: "DUPLICATE_PROTECTED",
        path: "assets/readme.md",
      });
      renderFileTree();
      pick(new File(["# mine"], "readme.md", { type: "text/markdown" }));
      await waitFor(() => {
        expect(screen.getByText("A markdown file with this name already exists")).toBeDefined();
      });
      expect(screen.queryByText("Replace")).toBeNull();
    });
  });
});
