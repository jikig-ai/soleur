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

type CallRecord = { method: string; url: string };

function installFetchSequence(
  responses: Array<{
    headers?: Record<string, string>;
    status?: number;
    json?: unknown;
  }>,
): CallRecord[] {
  const calls: CallRecord[] = [];
  let i = 0;
  global.fetch = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input.toString();
    calls.push({ method: init?.method ?? "GET", url });
    const r = responses[Math.min(i++, responses.length - 1)];
    const headers = new Map(
      Object.entries(r.headers ?? {}).map(([k, v]) => [k.toLowerCase(), v]),
    );
    return Promise.resolve({
      ok: (r.status ?? 200) >= 200 && (r.status ?? 200) < 300,
      status: r.status ?? 200,
      headers: {
        get: (name: string) => headers.get(name.toLowerCase()) ?? null,
      },
      json: () => Promise.resolve(r.json ?? null),
    }) as unknown as Promise<Response>;
  }) as unknown as typeof fetch;
  return calls;
}

function renderWithSuspense(ui: React.ReactNode) {
  return render(<Suspense fallback={<div>Loading...</div>}>{ui}</Suspense>);
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("SharedDocumentPage — HEAD-first fetch discipline", () => {
  it("PDF: issues exactly ONE HEAD; the embed <src> is the single GET", async () => {
    const calls = installFetchSequence([
      {
        headers: {
          "content-type": "application/pdf",
          "content-disposition": 'inline; filename="report.pdf"',
          "x-soleur-kind": "pdf",
        },
        status: 200,
      },
    ]);

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );
    const { getByTestId } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "tok-pdf" })} />,
      ),
    );

    await waitFor(() => {
      expect(getByTestId("pdf-preview").getAttribute("data-filename")).toBe(
        "report.pdf",
      );
    });

    // The page itself issues exactly one HEAD. The embed (mocked) does not
    // fire a real GET in this harness, so total page-initiated calls === 1.
    expect(calls.length).toBe(1);
    expect(calls[0].method).toBe("HEAD");
    expect(calls[0].url).toBe("/api/shared/tok-pdf");
  });

  it("Markdown: HEAD + GET (JSON body)", async () => {
    const calls = installFetchSequence([
      {
        headers: {
          "content-type": "application/json",
          "x-soleur-kind": "markdown",
        },
        status: 200,
      },
      {
        headers: {
          "content-type": "application/json",
          "x-soleur-kind": "markdown",
        },
        status: 200,
        json: { content: "# Hi", path: "note.md" },
      },
    ]);

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );
    const { getByTestId } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "tm" })} />,
      ),
    );

    await waitFor(() => {
      expect(getByTestId("markdown").textContent).toBe("# Hi");
    });

    expect(calls.map((c) => c.method)).toEqual(["HEAD", "GET"]);
    expect(calls[0].url).toBe("/api/shared/tm");
    expect(calls[1].url).toBe("/api/shared/tm");
  });

  it("404: HEAD only, no follow-up GET", async () => {
    const calls = installFetchSequence([{ status: 404 }]);

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );
    const { container } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "missing" })} />,
      ),
    );

    await waitFor(() => {
      expect(container.textContent).toContain("Document not found");
    });
    expect(calls.length).toBe(1);
    expect(calls[0].method).toBe("HEAD");
  });

  it("410 content-changed: HEAD + GET (to read JSON `code`)", async () => {
    const calls = installFetchSequence([
      { status: 410 },
      { status: 410, json: { code: "content-changed" } },
    ]);

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );
    const { container } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "cm" })} />,
      ),
    );

    await waitFor(() => {
      expect(container.textContent).toContain("The shared file was modified");
    });
    expect(calls.map((c) => c.method)).toEqual(["HEAD", "GET"]);
  });

  it("410 revoked: HEAD + GET (no code → revoked copy)", async () => {
    const calls = installFetchSequence([
      { status: 410 },
      { status: 410, json: { code: "revoked" } },
    ]);

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );
    const { container } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "rv" })} />,
      ),
    );

    await waitFor(() => {
      expect(container.textContent).toContain("This link has been disabled");
    });
    expect(calls.map((c) => c.method)).toEqual(["HEAD", "GET"]);
  });
});
