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
}));

vi.mock("@/components/kb/share-popover", () => ({
  SharePopover: () => <button data-testid="share">Share</button>,
}));

vi.mock("@/components/kb/file-preview", () => ({
  FilePreview: ({ path, extension }: { path: string; extension: string }) => (
    <div data-testid="file-preview" data-path={path} data-extension={extension} />
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
      expect(preview.getAttribute("data-extension")).toBe(".png");
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
      expect(preview.getAttribute("data-extension")).toBe(".pdf");
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
});
