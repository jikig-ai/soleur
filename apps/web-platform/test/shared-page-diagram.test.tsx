import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, waitFor, act } from "@testing-library/react";
import { Suspense } from "react";

// MarkdownRenderer is stubbed so a plain-prose share still has a recognizable
// node, and so we can assert the diagram branch does NOT fall back to it.
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

// The public diagram render path mounts the inline C4Diagram (read-only),
// NEVER the full C4Workspace (which embeds the owner-only Concierge + Code
// editor). Stub it so we can assert the props the share page threads through.
vi.mock("@/components/kb/c4-diagram", () => ({
  default: ({
    viewId,
    fetchUrl,
    readOnly,
  }: {
    viewId: string;
    fetchUrl?: string;
    readOnly?: boolean;
  }) => (
    <div
      data-testid="c4-diagram"
      data-viewid={viewId}
      data-fetchurl={fetchUrl}
      data-readonly={String(!!readOnly)}
    />
  ),
}));

// If the share page ever imported C4Workspace, this stub makes its presence
// detectable. Its absence in the rendered tree is the negative-space proof.
vi.mock("@/components/kb/c4-workspace", () => ({
  default: () => <div data-testid="c4-workspace" />,
}));

beforeEach(() => {
  vi.clearAllMocks();
});

function renderWithSuspense(ui: React.ReactNode) {
  return render(<Suspense fallback={<div>Loading...</div>}>{ui}</Suspense>);
}

function mockMarkdownFetch(content: string) {
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
      json: () => Promise.resolve({ content, path: "engineering/architecture/diagrams/c4-model.md" }),
    }),
  ) as unknown as typeof fetch;
}

const DIAGRAM_DOC = [
  "# Soleur Platform — C4 Model",
  "",
  "```likec4-view",
  "context",
  "```",
  "",
  "Some prose explaining the architecture.",
].join("\n");

describe("SharedDocumentPage — LikeC4 diagram render", () => {
  it("renders the read-only inline C4Diagram (token-scoped fetch) for a diagram doc", async () => {
    mockMarkdownFetch(DIAGRAM_DOC);

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { getByTestId } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "diag-1" })} />,
      ),
    );

    await waitFor(() => {
      const diagram = getByTestId("c4-diagram");
      expect(diagram.getAttribute("data-viewid")).toBe("context");
      expect(diagram.getAttribute("data-fetchurl")).toBe(
        "/api/shared/diag-1/c4",
      );
      // Public viewers get the read-only variant — no Code tab / save path.
      expect(diagram.getAttribute("data-readonly")).toBe("true");
    });
  });

  it("never mounts the owner-only C4Workspace (Concierge + Code editor)", async () => {
    mockMarkdownFetch(DIAGRAM_DOC);

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { queryByTestId } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "diag-2" })} />,
      ),
    );

    await waitFor(() => {
      expect(queryByTestId("c4-diagram")).toBeTruthy();
    });
    expect(queryByTestId("c4-workspace")).toBeNull();
  });

  it("renders plain MarkdownRenderer (no diagram) for a doc with no likec4-view embed", async () => {
    mockMarkdownFetch("# Just prose\n\nNo diagram here.");

    const { default: SharedDocumentPage } = await import(
      "@/app/shared/[token]/page"
    );

    const { getByTestId, queryByTestId } = await act(() =>
      renderWithSuspense(
        <SharedDocumentPage params={Promise.resolve({ token: "plain-1" })} />,
      ),
    );

    await waitFor(() => {
      expect(getByTestId("markdown")).toBeTruthy();
    });
    expect(queryByTestId("c4-diagram")).toBeNull();
  });
});
