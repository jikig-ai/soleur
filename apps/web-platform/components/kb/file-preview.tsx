"use client";

import { useState } from "react";
import dynamic from "next/dynamic";
import type { FileKind } from "@/lib/kb-file-kind";
import { TextPreview } from "@/components/kb/text-preview";
import { DownloadPreview } from "@/components/kb/download-preview";

const PdfPreview = dynamic(
  () => import("./pdf-preview").then((mod) => mod.PdfPreview),
  {
    ssr: false,
    loading: () => (
      <div className="flex items-center justify-center p-8">
        <div className="h-5 w-5 animate-spin rounded-full border-2 border-soleur-border-default border-t-amber-400" />
      </div>
    ),
  },
);

interface FilePreviewProps {
  path: string;
  kind: FileKind;
  /**
   * Hide the internal filename/Download row (dashboard provides its own).
   * See `PdfPreview` for semantics. Default `true`. Does not affect
   * `DownloadPreview` (which IS the download UI) or `ImagePreview`.
   */
  showDownload?: boolean;
}

export function FilePreview({ path, kind, showDownload = true }: FilePreviewProps) {
  const contentUrl = `/api/kb/content/${path}`;
  const filename = path.split("/").pop() || path;

  switch (kind) {
    case "image":
      return <ImagePreview src={contentUrl} filename={filename} />;
    case "pdf":
      return <PdfPreview src={contentUrl} filename={filename} showDownload={showDownload} />;
    case "text":
      return <TextPreview src={contentUrl} filename={filename} showDownload={showDownload} />;
    case "download":
      return <DownloadPreview src={contentUrl} filename={filename} />;
    case "markdown":
      // Markdown is rendered by MarkdownRenderer on both viewer pages,
      // not through FilePreview. Callers must gate on isMarkdownKbPath
      // before dispatching here — rendering nothing is the safe default.
      return null;
    default: {
      // Exhaustiveness guard — adding a new FileKind without a render
      // branch fails the build here.
      const _exhaustive: never = kind;
      void _exhaustive;
      return null;
    }
  }
}

function ImagePreview({ src, filename }: { src: string; filename: string }) {
  const [lightbox, setLightbox] = useState(false);

  return (
    <div className="flex flex-col items-center gap-4 p-6">
      <button
        onClick={() => setLightbox(true)}
        className="cursor-zoom-in overflow-hidden rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1/50"
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={src}
          alt={filename}
          className="max-h-[60vh] max-w-full object-contain"
          loading="lazy"
        />
      </button>
      <p className="text-xs text-soleur-text-muted">Click to enlarge</p>

      {lightbox && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
          onClick={() => setLightbox(false)}
          role="dialog"
          aria-label={`Preview of ${filename}`}
        >
          <button
            onClick={() => setLightbox(false)}
            className="absolute right-4 top-4 rounded-full p-2 text-soleur-text-secondary hover:text-soleur-text-primary"
            aria-label="Close lightbox"
          >
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={src}
            alt={filename}
            className="max-h-[90vh] max-w-[90vw] object-contain"
            onClick={(e) => e.stopPropagation()}
          />
        </div>
      )}
    </div>
  );
}

