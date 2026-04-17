"use client";

import { useState, useEffect } from "react";

/**
 * Inline text preview. Fetches the text body lazily from `src` and
 * renders it in a scrollable `<pre>`. Falls back to a download link
 * on fetch failure so the recipient still has a recovery path.
 *
 * Shared between the owner viewer (`components/kb/file-preview.tsx`)
 * and the shared viewer (`app/shared/[token]/page.tsx`) — a single
 * component closes the inline-text rendering drift between the two
 * surfaces.
 */
export function TextPreview({
  src,
  filename,
  showDownload = true,
}: {
  src: string;
  filename: string;
  showDownload?: boolean;
}) {
  const [text, setText] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function fetchText() {
      try {
        const res = await fetch(src);
        if (!res.ok) throw new Error("Fetch failed");
        const content = await res.text();
        if (!cancelled) {
          setText(content);
          setLoading(false);
        }
      } catch {
        if (!cancelled) {
          setError(true);
          setLoading(false);
        }
      }
    }
    fetchText();
    return () => {
      cancelled = true;
    };
  }, [src]);

  if (loading) {
    return (
      <div className="flex items-center justify-center p-8">
        <div className="h-5 w-5 animate-spin rounded-full border-2 border-neutral-600 border-t-amber-400" />
      </div>
    );
  }

  if (error || text === null) {
    return <TextDownloadFallback src={src} filename={filename} />;
  }

  return (
    <div className="flex flex-col gap-3 p-4">
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
      <pre className="max-h-[70vh] overflow-auto rounded-lg border border-neutral-800 bg-neutral-900/50 p-4 text-sm text-neutral-300">
        {text}
      </pre>
    </div>
  );
}

function TextDownloadFallback({ src, filename }: { src: string; filename: string }) {
  const ext = filename.split(".").pop()?.toUpperCase() || "FILE";
  return (
    <div className="flex h-full items-center justify-center p-8">
      <div className="flex flex-col items-center gap-4 text-center">
        <div className="rounded-lg border border-neutral-800 bg-neutral-900/50 p-6">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="text-neutral-500">
            <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M14 2v6h6" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        <div>
          <p className="mb-1 text-sm font-medium text-neutral-300">{filename}</p>
          <p className="text-xs text-neutral-500">{ext} file</p>
        </div>
        <a
          href={src}
          download={filename}
          className="inline-flex items-center gap-2 rounded-lg border border-amber-500/50 px-4 py-2 text-sm font-medium text-amber-400 transition-colors hover:border-amber-400 hover:text-amber-300"
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
