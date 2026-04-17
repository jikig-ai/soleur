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
  PdfPreview: () => <div data-testid="pdf-preview" />,
}));

beforeEach(() => {
  vi.clearAllMocks();
});

function renderWithSuspense(ui: React.ReactNode) {
  return render(<Suspense fallback={<div>Loading...</div>}>{ui}</Suspense>);
}

function mock410(body: unknown) {
  const headers = new Map([["content-type", "application/json"]]);
  global.fetch = vi.fn(() =>
    Promise.resolve({
      ok: false,
      status: 410,
      headers: {
        get: (name: string) => headers.get(name.toLowerCase()) ?? null,
      },
      json: () =>
        body === "INVALID"
          ? Promise.reject(new Error("bad json"))
          : Promise.resolve(body),
    }),
  ) as unknown as typeof fetch;
}

describe("SharedDocumentPage — 410 content-changed variant", () => {
  it("renders the content-changed copy when body code is content-changed", async () => {
    mock410({ error: "...", code: "content-changed" });

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { container } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "t-cc" })} />,
      ),
    );

    await waitFor(() => {
      expect(container.textContent).toContain("The shared file was modified");
    });
    expect(container.textContent).not.toContain("This link has been disabled");
  });

  it("renders legacy-null-hash as the content-changed copy (same user-facing state)", async () => {
    mock410({ error: "...", code: "legacy-null-hash" });

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { container } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "t-legacy" })} />,
      ),
    );

    await waitFor(() => {
      expect(container.textContent).toContain("The shared file was modified");
    });
  });

  it("falls back to the revoked copy when the 410 body lacks a code field", async () => {
    mock410({ error: "This link has been disabled" });

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { container } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "t-old" })} />,
      ),
    );

    await waitFor(() => {
      expect(container.textContent).toContain("This link has been disabled");
    });
  });

  it("falls back to the revoked copy when the 410 body is not parseable JSON", async () => {
    mock410("INVALID");

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { container } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "t-bad" })} />,
      ),
    );

    await waitFor(() => {
      expect(container.textContent).toContain("This link has been disabled");
    });
  });
});
