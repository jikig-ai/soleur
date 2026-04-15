"use client";

import { useEffect, useRef, useState } from "react";
import { Document, Page, pdfjs } from "react-pdf";

pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  "pdfjs-dist/build/pdf.worker.min.mjs",
  import.meta.url,
).toString();

interface PdfPreviewProps {
  src: string;
  filename: string;
}

export function PdfPreview({ src, filename }: PdfPreviewProps) {
  const [numPages, setNumPages] = useState(0);
  const [pageNumber, setPageNumber] = useState(1);
  const [error, setError] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const [containerWidth, setContainerWidth] = useState<number>();

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const observer = new ResizeObserver(([entry]) => {
      setContainerWidth(entry.contentRect.width);
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

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
    <div className="flex h-full flex-col gap-3 p-4">
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

      <div ref={containerRef} className="flex-1 overflow-auto rounded-lg border border-neutral-800 bg-neutral-900/50">
        <Document
          file={src}
          onLoadSuccess={({ numPages: n }) => setNumPages(n)}
          onLoadError={() => setError(true)}
          loading={
            <div className="flex items-center justify-center p-8">
              <div className="h-5 w-5 animate-spin rounded-full border-2 border-neutral-600 border-t-amber-400" />
            </div>
          }
        >
          <Page
            pageNumber={pageNumber}
            width={containerWidth}
            renderTextLayer={false}
            renderAnnotationLayer={false}
            className="mx-auto"
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
