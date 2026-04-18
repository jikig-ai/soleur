import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, waitFor, act } from "@testing-library/react";
import { Suspense } from "react";

const mockReplace = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: mockReplace, back: vi.fn(), forward: vi.fn(), refresh: vi.fn(), prefetch: vi.fn() }),
  usePathname: () => "/dashboard/kb/test.md",
}));

// Mock heavy child components to isolate page routing logic
vi.mock("@/components/ui/markdown-renderer", () => ({
  MarkdownRenderer: ({ content }: { content: string }) => <div data-testid="markdown">{content}</div>,
}));

vi.mock("@/components/kb/kb-breadcrumb", () => ({
  KbBreadcrumb: ({ path }: { path: string }) => <span data-testid="breadcrumb">{path}</span>,
  safeDecode: (s: string) => {
    try {
      return decodeURIComponent(s);
    } catch {
      return s;
    }
  },
}));

vi.mock("@/components/kb/share-popover", () => ({
  SharePopover: () => <button data-testid="share">Share</button>,
}));

vi.mock("@/components/kb/file-preview", () => ({
  FilePreview: ({
    path,
    kind,
    showDownload,
  }: {
    path: string;
    kind: string;
    showDownload?: boolean;
  }) => (
    <div
      data-testid="file-preview"
      data-path={path}
      data-kind={kind}
      data-show-download={showDownload === undefined ? "unset" : String(showDownload)}
    />
  ),
}));

beforeEach(() => {
  vi.clearAllMocks();
  sessionStorage.clear();
});

function renderWithSuspense(ui: React.ReactNode) {
  return render(<Suspense fallback={<div>Loading...</div>}>{ui}</Suspense>);
}

describe("KbContentPage routing", () => {
  it("renders FilePreview for .png files instead of redirecting", async () => {
    const { default: KbContentPage } = await import(
      "@/app/(dashboard)/dashboard/kb/[...path]/page"
    );

    const { getByTestId } = await act(() =>
      renderWithSuspense(
        <KbContentPage params={Promise.resolve({ path: ["assets", "logo.png"] })} />,
      ),
    );

    // Should NOT redirect to /dashboard/kb
    expect(mockReplace).not.toHaveBeenCalledWith("/dashboard/kb");

    // Should render FilePreview component
    await waitFor(() => {
      const preview = getByTestId("file-preview");
      expect(preview.getAttribute("data-path")).toBe("assets/logo.png");
      expect(preview.getAttribute("data-kind")).toBe("image");
    });
  });

  it("renders FilePreview for .pdf files", async () => {
    const { default: KbContentPage } = await import(
      "@/app/(dashboard)/dashboard/kb/[...path]/page"
    );

    const { getByTestId } = await act(() =>
      renderWithSuspense(
        <KbContentPage params={Promise.resolve({ path: ["docs", "report.pdf"] })} />,
      ),
    );

    expect(mockReplace).not.toHaveBeenCalledWith("/dashboard/kb");

    await waitFor(() => {
      const preview = getByTestId("file-preview");
      expect(preview.getAttribute("data-kind")).toBe("pdf");
    });
  });

  it("shows breadcrumb for non-markdown files", async () => {
    const { default: KbContentPage } = await import(
      "@/app/(dashboard)/dashboard/kb/[...path]/page"
    );

    const { getByTestId } = await act(() =>
      renderWithSuspense(
        <KbContentPage params={Promise.resolve({ path: ["assets", "logo.png"] })} />,
      ),
    );

    await waitFor(() => {
      expect(getByTestId("breadcrumb").textContent).toBe("assets/logo.png");
    });
  });

  it("renders Share button on .pdf branch", async () => {
    const { default: KbContentPage } = await import(
      "@/app/(dashboard)/dashboard/kb/[...path]/page"
    );

    const { getByTestId } = await act(() =>
      renderWithSuspense(
        <KbContentPage params={Promise.resolve({ path: ["docs", "report.pdf"] })} />,
      ),
    );

    await waitFor(() => {
      expect(getByTestId("share")).toBeTruthy();
    });
  });

  it("renders Share button on .png branch", async () => {
    const { default: KbContentPage } = await import(
      "@/app/(dashboard)/dashboard/kb/[...path]/page"
    );

    const { getByTestId } = await act(() =>
      renderWithSuspense(
        <KbContentPage params={Promise.resolve({ path: ["assets", "logo.png"] })} />,
      ),
    );

    await waitFor(() => {
      expect(getByTestId("share")).toBeTruthy();
    });
  });

  it("renders Download/Share/Chat in header for non-markdown files (order preserved)", async () => {
    const { default: KbContentPage } = await import(
      "@/app/(dashboard)/dashboard/kb/[...path]/page"
    );

    const { container, getByTestId } = await act(() =>
      renderWithSuspense(
        <KbContentPage params={Promise.resolve({ path: ["docs", "report.pdf"] })} />,
      ),
    );

    const header = await waitFor(() => {
      const el = container.querySelector("header");
      if (!el) throw new Error("header not found");
      return el;
    });

    const downloadAnchor = header.querySelector('a[download]');
    expect(downloadAnchor).not.toBeNull();
    expect(downloadAnchor?.getAttribute("href")).toBe("/api/kb/content/docs/report.pdf");
    expect(downloadAnchor?.getAttribute("download")).toBe("report.pdf");

    const share = getByTestId("share");
    const chatLink = header.querySelector('a[href^="/dashboard/chat/new"]');
    expect(chatLink).not.toBeNull();

    // Order: Download -> Share -> Chat
    expect(
      downloadAnchor!.compareDocumentPosition(share) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(
      share.compareDocumentPosition(chatLink!) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  it("passes showDownload={false} to FilePreview on non-markdown branch", async () => {
    const { default: KbContentPage } = await import(
      "@/app/(dashboard)/dashboard/kb/[...path]/page"
    );

    const { getByTestId } = await act(() =>
      renderWithSuspense(
        <KbContentPage params={Promise.resolve({ path: ["docs", "report.pdf"] })} />,
      ),
    );

    await waitFor(() => {
      expect(getByTestId("file-preview").getAttribute("data-show-download")).toBe("false");
    });
  });
});
