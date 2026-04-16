"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Document, Page, pdfjs } from "react-pdf";

pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  "pdfjs-dist/build/pdf.worker.min.mjs",
  import.meta.url,
).toString();

interface PdfPreviewProps {
  src: string;
  filename: string;
  /**
   * Show the internal filename + Download row above the PDF viewer.
   * Default `true` is required by `app/shared/[token]/page.tsx`, which
   * renders `PdfPreview` directly with no external Download chrome.
   * The dashboard opts out via `showDownload={false}` because it renders its
   * own Download button in the outer page header.
   */
  showDownload?: boolean;
}

export function PdfPreview({ src, filename, showDownload = true }: PdfPreviewProps) {
  const [numPages, setNumPages] = useState(0);
  const [pageNumber, setPageNumber] = useState(1);
  const [error, setError] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const [containerWidth, setContainerWidth] = useState<number>();
  const [containerHeight, setContainerHeight] = useState<number>();
  const [pageDims, setPageDims] = useState<{ width: number; height: number } | null>(null);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const observer = new ResizeObserver(([entry]) => {
      setContainerWidth(entry.contentRect.width);
      setContainerHeight(entry.contentRect.height);
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  // Size the page to fit within the container without scrolling.
  // When the container is wide (sidebars collapsed), a full-width page
  // would be taller than the container. Constrain width so the rendered
  // height stays within bounds.
  const effectiveWidth = useMemo(() => {
    if (!containerWidth) return undefined;
    if (!containerHeight || !pageDims) return containerWidth;
    const maxWidthFromHeight = containerHeight * (pageDims.width / pageDims.height);
    return Math.min(containerWidth, maxWidthFromHeight);
  }, [containerWidth, containerHeight, pageDims]);

  if (error) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-4 p-8 text-center">
        <p className="text-sm text-neutral-400">Unable to preview this PDF</p>
        <a
          href={src}
          download={filename}
          className="inline-flex items-center gap-2 rounded-lg border border-amber-500/50 px-4 py-2 text-sm font-medium text-amber-400 transition-colors hover:border-amber-400 hover:text-amber-300"
        >
          Download {filename}
        </a>
      </div>
    );
  }

  return (
    <div className="flex min-h-0 h-full flex-col gap-3 p-4">
      {showDownload && (
        <div className="flex items-center justify-between">
          <span className="text-sm text-neutral-400">{filename}</span>
          <a
            href={src}
            download={filename}
            className="rounded-md border border-neutral-700 px-3 py-1 text-xs text-neutral-300 hover:bg-neutral-800"
          >
            Download
          </a>
        </div>
      )}

      <div ref={containerRef} className="min-h-0 flex-1 flex items-center justify-center overflow-auto rounded-lg border border-neutral-800 bg-neutral-900/50">
        <Document
          file={src}
          onLoadSuccess={({ numPages: n }) => setNumPages(n)}
          onLoadError={() => setError(true)}
          className="flex items-center justify-center"
          loading={
            <div className="flex items-center justify-center p-8">
              <div className="h-5 w-5 animate-spin rounded-full border-2 border-neutral-600 border-t-amber-400" />
            </div>
          }
        >
          <Page
            pageNumber={pageNumber}
            width={effectiveWidth}
            renderTextLayer={false}
            renderAnnotationLayer={false}
            onLoadSuccess={(page) => {
              const viewport = page.getViewport({ scale: 1 });
              setPageDims({ width: viewport.width, height: viewport.height });
            }}
          />
        </Document>
      </div>

      {numPages > 1 && (
        <div className="flex items-center justify-center gap-3">
          <button
            onClick={() => setPageNumber((p) => Math.max(p - 1, 1))}
            disabled={pageNumber <= 1}
            className="rounded-md border border-neutral-700 px-3 py-1 text-xs text-neutral-300 hover:bg-neutral-800 disabled:cursor-not-allowed disabled:opacity-40"
          >
            Previous
          </button>
          <span className="text-xs text-neutral-400">
            Page {pageNumber} of {numPages}
          </span>
          <button
            onClick={() => setPageNumber((p) => Math.min(p + 1, numPages))}
            disabled={pageNumber >= numPages}
            className="rounded-md border border-neutral-700 px-3 py-1 text-xs text-neutral-300 hover:bg-neutral-800 disabled:cursor-not-allowed disabled:opacity-40"
          >
            Next
          </button>
        </div>
      )}
    </div>
  );
}
