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

function mockFetchJson(body: object) {
  const headers = new Map([["content-type", "application/json"]]);
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

function mockFetchBinary(contentType: string, disposition: string) {
  const headers = new Map([
    ["content-type", contentType],
    ["content-disposition", disposition],
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

describe("SharedDocumentPage — content-type branching", () => {
  it("renders MarkdownRenderer when API returns application/json", async () => {
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

  it("renders PdfPreview when API returns application/pdf", async () => {
    mockFetchBinary(
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

  it("renders inline <img> when API returns image/png", async () => {
    mockFetchBinary("image/png", 'inline; filename="logo.png"');

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

  it("renders download link for other binary types", async () => {
    mockFetchBinary(
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
});
