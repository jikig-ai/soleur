"use client";

/**
 * Download-only viewer for KB files that cannot or should not render inline
 * (archives, office docs, or any file whose inline render is gated out — see
 * `TextPreview`'s size fallback and `FilePreview`'s `"download"` branch).
 *
 * Shared between the owner viewer and the shared-link viewer so a visual
 * tweak to the card lands in both places.
 */
export function DownloadPreview({ src, filename }: { src: string; filename: string }) {
  const ext = filename.split(".").pop()?.toUpperCase() || "FILE";

  return (
    <div className="flex h-full items-center justify-center p-8">
      <div className="flex flex-col items-center gap-4 text-center">
        <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="text-soleur-text-muted">
            <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M14 2v6h6" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        <div>
          <p className="mb-1 text-sm font-medium text-soleur-text-secondary">{filename}</p>
          <p className="text-xs text-soleur-text-muted">{ext} file</p>
        </div>
        <a
          href={src}
          download={filename}
          className="inline-flex items-center gap-2 rounded-lg border border-soleur-border-emphasized px-4 py-2 text-sm font-medium text-soleur-accent-gold-fg transition-colors hover:border-amber-400 hover:text-soleur-accent-gold-text"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" strokeLinecap="round" strokeLinejoin="round" />
            <polyline points="7 10 12 15 17 10" strokeLinecap="round" strokeLinejoin="round" />
            <line x1="12" y1="15" x2="12" y2="3" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          Download
        </a>
      </div>
    </div>
  );
}
