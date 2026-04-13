import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { FilePreview } from "@/components/kb/file-preview";

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

  it("renders embed for .pdf files", () => {
    const { container } = render(<FilePreview path="docs/report.pdf" extension=".pdf" />);
    const embed = container.querySelector("embed");
    expect(embed).not.toBeNull();
    expect(embed?.getAttribute("src")).toBe("/api/kb/content/docs/report.pdf");
    expect(embed?.getAttribute("type")).toBe("application/pdf");
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
