import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import React from "react";
import { FilePreview } from "@/components/kb/file-preview";

// Mock next/dynamic — use React.lazy + Suspense so the async import resolves via React's scheduler
vi.mock("next/dynamic", () => ({
  __esModule: true,
  default: (loader: () => Promise<any>, _opts?: any) => {
    const LazyComponent = React.lazy(() =>
      loader().then((mod: any) => ({
        default:
          typeof mod === "function"
            ? mod
            : mod.default || (Object.values(mod)[0] as any),
      })),
    );
    return function MockDynamic(props: any) {
      return (
        <React.Suspense fallback={null}>
          <LazyComponent {...props} />
        </React.Suspense>
      );
    };
  },
}));

// Mock react-pdf — happy-dom lacks canvas
vi.mock("react-pdf", async () => {
  const { useEffect } = await import("react");
  return {
    Document: ({ children, onLoadSuccess }: any) => {
      useEffect(() => {
        onLoadSuccess?.({ numPages: 3 });
      }, [onLoadSuccess]);
      return <div data-testid="pdf-document">{children}</div>;
    },
    Page: ({ pageNumber }: any) => (
      <div data-testid="pdf-page">Page {pageNumber}</div>
    ),
    pdfjs: { GlobalWorkerOptions: { workerSrc: "" } },
  };
});

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
  usePathname: () => "/dashboard/kb",
}));

beforeEach(() => {
  vi.clearAllMocks();
});

describe("FilePreview", () => {
  it("renders image preview for .png files", () => {
    const { container } = render(<FilePreview path="assets/logo.png" extension=".png" />);
    const img = container.querySelector("img");
    expect(img).not.toBeNull();
    expect(img?.getAttribute("src")).toBe("/api/kb/content/assets/logo.png");
    expect(img?.getAttribute("alt")).toBe("logo.png");
  });

  it("renders image preview for .jpg files", () => {
    const { container } = render(<FilePreview path="assets/photo.jpg" extension=".jpg" />);
    const img = container.querySelector("img");
    expect(img).not.toBeNull();
  });

  it("renders PDF preview with react-pdf for .pdf files", async () => {
    const { container } = render(<FilePreview path="docs/report.pdf" extension=".pdf" />);
    await waitFor(() => {
      const pdfDoc = container.querySelector('[data-testid="pdf-document"]');
      expect(pdfDoc).not.toBeNull();
    });
    const pdfPage = container.querySelector('[data-testid="pdf-page"]');
    expect(pdfPage).not.toBeNull();
    expect(pdfPage?.textContent).toBe("Page 1");
  });

  it("renders download button for PDF files", async () => {
    const { container } = render(<FilePreview path="docs/report.pdf" extension=".pdf" />);
    await waitFor(() => {
      const downloadLink = container.querySelector('a[download]');
      expect(downloadLink).not.toBeNull();
    });
    const downloadLink = container.querySelector('a[download]');
    expect(downloadLink?.getAttribute("href")).toBe("/api/kb/content/docs/report.pdf");
  });

  it("renders page navigation for multi-page PDFs", async () => {
    render(<FilePreview path="docs/report.pdf" extension=".pdf" />);
    await waitFor(() => {
      expect(screen.getByText("Page 1 of 3")).toBeDefined();
    });
    expect(screen.getByText("Previous")).toBeDefined();
    expect(screen.getByText("Next")).toBeDefined();
  });

  it("navigates to next page when Next is clicked", async () => {
    render(<FilePreview path="docs/report.pdf" extension=".pdf" />);
    await waitFor(() => {
      expect(screen.getByText("Next")).toBeDefined();
    });
    const nextBtn = screen.getByText("Next");
    fireEvent.click(nextBtn);
    expect(screen.getByText("Page 2 of 3")).toBeDefined();
  });

  it("disables Previous button on first page", async () => {
    render(<FilePreview path="docs/report.pdf" extension=".pdf" />);
    await waitFor(() => {
      expect(screen.getByText("Previous")).toBeDefined();
    });
    const prevBtn = screen.getByText("Previous");
    expect(prevBtn.hasAttribute("disabled")).toBe(true);
  });

  it("disables Next button on last page", async () => {
    render(<FilePreview path="docs/report.pdf" extension=".pdf" />);
    await waitFor(() => {
      expect(screen.getByText("Next")).toBeDefined();
    });
    const nextBtn = screen.getByText("Next");
    // Navigate to last page (page 3)
    fireEvent.click(nextBtn);
    fireEvent.click(nextBtn);
    expect(screen.getByText("Page 3 of 3")).toBeDefined();
    expect(nextBtn.hasAttribute("disabled")).toBe(true);
  });

  it("renders download link for .docx files", () => {
    const { container } = render(<FilePreview path="docs/contract.docx" extension=".docx" />);
    const downloadLink = container.querySelector('a[download]');
    expect(downloadLink).not.toBeNull();
    expect(downloadLink?.getAttribute("href")).toBe("/api/kb/content/docs/contract.docx");
  });

  it("renders download link for .csv files", () => {
    const { container } = render(<FilePreview path="data/report.csv" extension=".csv" />);
    const downloadLink = container.querySelector('a[download]');
    expect(downloadLink).not.toBeNull();
  });

  it("fetches and renders text for .txt files", async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      text: () => Promise.resolve("Hello world content"),
    });

    render(<FilePreview path="notes/readme.txt" extension=".txt" />);

    await waitFor(() => {
      expect(screen.getByText("Hello world content")).toBeDefined();
    });
  });

  it("shows download fallback when .txt fetch fails", async () => {
    global.fetch = vi.fn().mockRejectedValue(new Error("Network error"));

    const { container } = render(<FilePreview path="notes/broken.txt" extension=".txt" />);

    await waitFor(() => {
      const downloadLink = container.querySelector('a[download]');
      expect(downloadLink).not.toBeNull();
    });
  });

  it("opens lightbox when image is clicked", async () => {
    const { container } = render(<FilePreview path="assets/logo.png" extension=".png" />);

    const button = container.querySelector("button");
    expect(button).not.toBeNull();
    fireEvent.click(button!);

    await waitFor(() => {
      const dialog = container.querySelector('[role="dialog"]');
      expect(dialog).not.toBeNull();
    });
  });

  it("closes lightbox when close button is clicked", async () => {
    const { container } = render(<FilePreview path="assets/logo.png" extension=".png" />);

    // Open lightbox
    const openBtn = container.querySelector("button");
    fireEvent.click(openBtn!);

    await waitFor(() => {
      expect(container.querySelector('[role="dialog"]')).not.toBeNull();
    });

    // Close lightbox
    const closeBtn = screen.getByLabelText("Close lightbox");
    fireEvent.click(closeBtn);

    await waitFor(() => {
      expect(container.querySelector('[role="dialog"]')).toBeNull();
    });
  });
});
