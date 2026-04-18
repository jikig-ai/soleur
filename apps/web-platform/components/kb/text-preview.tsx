"use client";

import { useState, useEffect } from "react";
import { DownloadPreview } from "@/components/kb/download-preview";

/**
 * Inline text preview. HEADs `src` first, and if the body is over
 * `INLINE_TEXT_MAX_BYTES` falls back to `DownloadPreview` instead of
 * buffering the whole file into a single `<pre>`. Under the threshold,
 * fetches the body and renders it.
 *
 * Shared between the owner viewer (`components/kb/file-preview.tsx`) and
 * the shared viewer (`app/shared/[token]/page.tsx`) — one component closes
 * the inline-text rendering drift between the two surfaces.
 *
 * The size guard is the deliberate policy choice: `MAX_BINARY_SIZE` (50 MB)
 * allows `.txt` uploads far larger than a browser can lay out in a single
 * `<pre>` without janking the main thread, and we don't ship a virtualized
 * renderer yet. Failing over to the download card is the safe default.
 */
const INLINE_TEXT_MAX_BYTES = 1 * 1024 * 1024; // 1 MB

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
  const [oversized, setOversized] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function fetchText() {
      try {
        const head = await fetch(src, { method: "HEAD" });
        if (!head.ok) throw new Error("Fetch failed");
        const contentLengthHeader = head.headers.get("content-length");
        const contentLength = contentLengthHeader ? Number(contentLengthHeader) : Number.NaN;
        if (Number.isFinite(contentLength) && contentLength > INLINE_TEXT_MAX_BYTES) {
          if (!cancelled) {
            setOversized(true);
            setLoading(false);
          }
          return;
        }
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

  if (error || oversized || text === null) {
    return <DownloadPreview src={src} filename={filename} />;
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
