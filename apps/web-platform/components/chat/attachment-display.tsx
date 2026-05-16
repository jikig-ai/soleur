"use client";

import { useState, useEffect } from "react";
import type { AttachmentRef } from "@/lib/types";
import { reportSilentFallback } from "@/lib/client-observability";

// ── Signed-URL cache with 50-minute TTL ──────────────────────────────
// Signed URLs expire after 1 hour; we cache for 50 minutes to avoid
// serving an expired URL while still minimising redundant fetches.
const URL_TTL_MS = 50 * 60 * 1_000; // 50 minutes
const urlCache = new Map<string, { url: string; expiresAt: number }>();

interface AttachmentUrlState {
  url: string | null;
  loadFailed: boolean;
}

function useAttachmentUrl(
  storagePath: string,
): AttachmentUrlState & { retry: () => void } {
  const [state, setState] = useState<AttachmentUrlState>(() => {
    const cached = urlCache.get(storagePath);
    if (cached && cached.expiresAt > Date.now()) {
      return { url: cached.url, loadFailed: false };
    }
    return { url: null, loadFailed: false };
  });
  // Bumping `retryNonce` re-triggers the fetch effect after a Retry click.
  // No `userId` in this client component — `ClientExtra` brands it `never`,
  // so all Sentry mirror calls below pass `{ feature, op, message }` only.
  const [retryNonce, setRetryNonce] = useState(0);

  useEffect(() => {
    const cached = urlCache.get(storagePath);
    if (cached && cached.expiresAt > Date.now()) {
      setState({ url: cached.url, loadFailed: false });
      return;
    }

    let cancelled = false;
    fetch("/api/attachments/url", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ storagePath }),
    })
      .then((r) => r.json())
      .then((data) => {
        if (cancelled) return;
        if (data?.url) {
          urlCache.set(storagePath, {
            url: data.url,
            expiresAt: Date.now() + URL_TTL_MS,
          });
          setState({ url: data.url, loadFailed: false });
        } else {
          // Server returned 200 but no `url` field — treat as load failure
          // rather than rendering a permanent skeleton.
          reportSilentFallback(null, {
            feature: "attachments",
            op: "url-fetch",
            message: "Attachment URL response missing url field",
          });
          setState({ url: null, loadFailed: true });
        }
      })
      .catch((err) => {
        if (cancelled) return;
        reportSilentFallback(err, {
          feature: "attachments",
          op: "url-fetch",
          message: "Attachment URL fetch failed",
        });
        setState({ url: null, loadFailed: true });
      });
    return () => {
      cancelled = true;
    };
  }, [storagePath, retryNonce]);

  const retry = () => {
    urlCache.delete(storagePath);
    setState({ url: null, loadFailed: false });
    setRetryNonce((n) => n + 1);
  };

  return { ...state, retry };
}

// ── Components ───────────────────────────────────────────────────────

interface AttachmentDisplayProps {
  attachments: AttachmentRef[];
}

export function AttachmentDisplay({ attachments }: AttachmentDisplayProps) {
  if (attachments.length === 0) return null;

  return (
    <div className="mt-2 flex flex-wrap gap-2">
      {attachments.map((att) =>
        att.contentType.startsWith("image/") ? (
          <ImageAttachment key={att.storagePath} attachment={att} />
        ) : (
          <FileAttachment key={att.storagePath} attachment={att} />
        ),
      )}
    </div>
  );
}

function PreviewUnavailable({
  filename,
  onRetry,
}: {
  filename: string;
  onRetry: () => void;
}) {
  return (
    <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 p-3 text-sm">
      <p className="text-soleur-text-secondary">
        Preview unavailable
        <span className="sr-only"> for {filename}</span>
      </p>
      <button
        type="button"
        onClick={onRetry}
        className="mt-1 text-soleur-text-accent underline"
      >
        Retry
      </button>
    </div>
  );
}

function ImageAttachment({ attachment }: { attachment: AttachmentRef }) {
  const { url, loadFailed, retry } = useAttachmentUrl(attachment.storagePath);
  const [expanded, setExpanded] = useState(false);

  if (loadFailed) {
    return <PreviewUnavailable filename={attachment.filename} onRetry={retry} />;
  }

  if (!url) {
    return (
      <div className="h-32 w-32 animate-pulse rounded-lg bg-soleur-bg-surface-2" />
    );
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setExpanded(true)}
        className="overflow-hidden rounded-lg border border-soleur-border-default transition-opacity hover:opacity-80"
      >
        <img
          src={url}
          alt={attachment.filename}
          className="max-h-48 max-w-[300px] object-contain"
        />
      </button>

      {/* Lightbox */}
      {expanded && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
          onClick={() => setExpanded(false)}
          role="dialog"
          aria-label={`Expanded view of ${attachment.filename}`}
        >
          <img
            src={url}
            alt={attachment.filename}
            className="max-h-[90vh] max-w-[90vw] rounded-lg object-contain"
          />
        </div>
      )}
    </>
  );
}

function FileAttachment({ attachment }: { attachment: AttachmentRef }) {
  const { url, loadFailed, retry } = useAttachmentUrl(attachment.storagePath);

  const sizeKb = Math.round(attachment.sizeBytes / 1_024);

  if (loadFailed) {
    return <PreviewUnavailable filename={attachment.filename} onRetry={retry} />;
  }

  return (
    <a
      href={url ?? "#"}
      target="_blank"
      rel="noopener noreferrer"
      className={`flex items-center gap-2 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2/50 px-3 py-2 text-sm transition-colors hover:border-soleur-border-emphasized ${!url ? "pointer-events-none opacity-60" : ""}`}
    >
      <svg
        width="20"
        height="20"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        className="shrink-0 text-red-400"
      >
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
        <polyline points="14 2 14 8 20 8" />
        <line x1="16" y1="13" x2="8" y2="13" />
        <line x1="16" y1="17" x2="8" y2="17" />
      </svg>
      <div className="flex flex-col">
        <span className="max-w-[200px] truncate text-soleur-text-primary">{attachment.filename}</span>
        <span className="text-xs text-soleur-text-muted">{sizeKb} KB</span>
      </div>
    </a>
  );
}
