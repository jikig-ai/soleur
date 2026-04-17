import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, waitFor, act } from "@testing-library/react";
import { Suspense } from "react";

vi.mock("@/components/ui/markdown-renderer", () => ({
  MarkdownRenderer: ({ content }: { content: string }) => (
    <div data-testid="markdown">{content}</div>
  ),
}));

vi.mock("@/components/shared/cta-banner", () => ({
  CtaBanner: () => <div data-testid="cta-banner" />,
}));

vi.mock("@/components/kb/pdf-preview", () => ({
  PdfPreview: ({ src, filename }: { src: string; filename: string }) => (
    <div data-testid="pdf-preview" data-src={src} data-filename={filename} />
  ),
}));

beforeEach(() => {
  vi.clearAllMocks();
});

function renderWithSuspense(ui: React.ReactNode) {
  return render(<Suspense fallback={<div>Loading...</div>}>{ui}</Suspense>);
}

type SharedKind = "markdown" | "pdf" | "image" | "download";

function mockFetchJson(body: object) {
  const headers = new Map([
    ["content-type", "application/json"],
    ["x-soleur-kind", "markdown"],
  ]);
  global.fetch = vi.fn(() =>
    Promise.resolve({
      ok: true,
      status: 200,
      headers: {
        get: (name: string) => headers.get(name.toLowerCase()) ?? null,
      },
      json: () => Promise.resolve(body),
    }),
  ) as unknown as typeof fetch;
}

function mockFetchBinary(
  kind: Exclude<SharedKind, "markdown">,
  contentType: string,
  disposition: string,
) {
  const headers = new Map([
    ["content-type", contentType],
    ["content-disposition", disposition],
    ["x-soleur-kind", kind],
  ]);
  global.fetch = vi.fn(() =>
    Promise.resolve({
      ok: true,
      status: 200,
      headers: {
        get: (name: string) => headers.get(name.toLowerCase()) ?? null,
      },
    }),
  ) as unknown as typeof fetch;
}

describe("SharedDocumentPage — server-declared kind branching", () => {
  it("renders MarkdownRenderer when X-Soleur-Kind is markdown", async () => {
    mockFetchJson({ content: "# Hi", path: "note.md" });

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { getByTestId } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "t1" })} />,
      ),
    );

    await waitFor(() => {
      expect(getByTestId("markdown").textContent).toBe("# Hi");
    });
  });

  it("renders PdfPreview when X-Soleur-Kind is pdf", async () => {
    mockFetchBinary(
      "pdf",
      "application/pdf",
      'inline; filename="report.pdf"',
    );

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { getByTestId } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "tok-pdf" })} />,
      ),
    );

    await waitFor(() => {
      const preview = getByTestId("pdf-preview");
      expect(preview.getAttribute("data-src")).toBe("/api/shared/tok-pdf");
      expect(preview.getAttribute("data-filename")).toBe("report.pdf");
    });
  });

  it("renders inline <img> when X-Soleur-Kind is image", async () => {
    mockFetchBinary("image", "image/png", 'inline; filename="logo.png"');

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { container } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "tok-png" })} />,
      ),
    );

    await waitFor(() => {
      const img = container.querySelector("img[data-testid='shared-image']");
      expect(img).toBeTruthy();
      expect(img?.getAttribute("src")).toBe("/api/shared/tok-png");
    });
  });

  it("renders download link when X-Soleur-Kind is download", async () => {
    mockFetchBinary(
      "download",
      "application/octet-stream",
      'attachment; filename="data.bin"',
    );

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { container } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "tok-bin" })} />,
      ),
    );

    await waitFor(() => {
      const a = container.querySelector("a[data-testid='shared-download']");
      expect(a).toBeTruthy();
      expect(a?.getAttribute("href")).toBe("/api/shared/tok-bin");
    });
  });

  it("ignores content-type when X-Soleur-Kind is absent (shows unknown error)", async () => {
    // Server responded 200 but omitted X-Soleur-Kind. The viewer refuses
    // to sniff content-type and surfaces the unknown-error branch instead
    // of silently defaulting to "download".
    const headers = new Map([["content-type", "application/pdf"]]);
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        status: 200,
        headers: {
          get: (name: string) => headers.get(name.toLowerCase()) ?? null,
        },
      }),
    ) as unknown as typeof fetch;

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { findByText } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "tok-nokind" })} />,
      ),
    );

    await findByText("Something went wrong");
  });

  it("decodes RFC 5987 filename* for non-ASCII filenames", async () => {
    mockFetchBinary(
      "pdf",
      "application/pdf",
      "inline; filename=\"report.pdf\"; filename*=UTF-8''%E6%96%87%E6%A1%A3.pdf",
    );

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { getByTestId } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "tok-utf" })} />,
      ),
    );

    await waitFor(() => {
      expect(getByTestId("pdf-preview").getAttribute("data-filename")).toBe(
        "文档.pdf",
      );
    });
  });

  it("falls back to a token-derived label when Content-Disposition is absent", async () => {
    // No Content-Disposition header — the viewer must not render the
    // literal string "file"; use a stable token-derived label instead
    // so screen readers hear something meaningful.
    const headers = new Map([
      ["content-type", "image/png"],
      ["x-soleur-kind", "image"],
    ]);
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        status: 200,
        headers: {
          get: (name: string) => headers.get(name.toLowerCase()) ?? null,
        },
      }),
    ) as unknown as typeof fetch;

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { container } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "img42" })} />,
      ),
    );

    await waitFor(() => {
      const img = container.querySelector("img[data-testid='shared-image']");
      expect(img).toBeTruthy();
      expect(img?.getAttribute("alt")).toBe("shared-img42");
      expect(img?.getAttribute("alt")).not.toBe("file");
    });
  });
});
