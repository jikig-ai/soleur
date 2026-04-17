import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, waitFor, act } from "@testing-library/react";
import { Suspense } from "react";
import { SHARED_CONTENT_KIND_HEADER } from "@/lib/shared-kind";

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
  vi.resetModules();
  vi.clearAllMocks();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

function renderWithSuspense(ui: React.ReactNode) {
  return render(<Suspense fallback={<div>Loading...</div>}>{ui}</Suspense>);
}

function mockFetchImage(disposition: string | null) {
  const headers = new Map<string, string>([
    ["content-type", "image/png"],
    [SHARED_CONTENT_KIND_HEADER.toLowerCase(), "image"],
  ]);
  if (disposition) headers.set("content-disposition", disposition);
  vi.stubGlobal(
    "fetch",
    vi.fn(() =>
      Promise.resolve({
        ok: true,
        status: 200,
        headers: {
          get: (name: string) => headers.get(name.toLowerCase()) ?? null,
        },
      }),
    ),
  );
}

describe("SharedDocumentPage — image a11y", () => {
  it('uses alt="Shared image" instead of the filename', async () => {
    mockFetchImage('inline; filename="photo_001.jpg"');

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { container } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "tok-img" })} />,
      ),
    );

    await waitFor(() => {
      const img = container.querySelector<HTMLImageElement>(
        "img[data-testid='shared-image']",
      );
      expect(img).toBeTruthy();
      expect(img?.getAttribute("alt")).toBe("Shared image");
      expect(img?.getAttribute("title")).toBe("photo_001.jpg");
    });
  });

  it('uses alt="Shared image" with no title when Content-Disposition is missing', async () => {
    mockFetchImage(null);

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { container } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "tok-nofn" })} />,
      ),
    );

    await waitFor(() => {
      const img = container.querySelector<HTMLImageElement>(
        "img[data-testid='shared-image']",
      );
      expect(img).toBeTruthy();
      expect(img?.getAttribute("alt")).toBe("Shared image");
      expect(img?.getAttribute("alt")).not.toBe("file");
      expect(img?.hasAttribute("title")).toBe(false);
    });
  });
});
