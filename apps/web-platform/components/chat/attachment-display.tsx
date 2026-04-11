"use client";

import { useState, useEffect } from "react";
import type { AttachmentRef } from "@/lib/types";

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

function ImageAttachment({ attachment }: { attachment: AttachmentRef }) {
  const [url, setUrl] = useState<string | null>(null);
  const [expanded, setExpanded] = useState(false);

  useEffect(() => {
    let cancelled = false;
    fetch("/api/attachments/url", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ storagePath: attachment.storagePath }),
    })
      .then((r) => r.json())
      .then((data) => {
        if (!cancelled && data.url) setUrl(data.url);
      })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [attachment.storagePath]);

  if (!url) {
    return (
      <div className="h-32 w-32 animate-pulse rounded-lg bg-neutral-800" />
    );
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setExpanded(true)}
        className="overflow-hidden rounded-lg border border-neutral-700 transition-opacity hover:opacity-80"
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
  const [url, setUrl] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetch("/api/attachments/url", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ storagePath: attachment.storagePath }),
    })
      .then((r) => r.json())
      .then((data) => {
        if (!cancelled && data.url) setUrl(data.url);
      })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [attachment.storagePath]);

  const sizeKb = Math.round(attachment.sizeBytes / 1_024);

  return (
    <a
      href={url ?? "#"}
      target="_blank"
      rel="noopener noreferrer"
      className={`flex items-center gap-2 rounded-lg border border-neutral-700 bg-neutral-800/50 px-3 py-2 text-sm transition-colors hover:border-neutral-500 ${!url ? "pointer-events-none opacity-60" : ""}`}
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
        <span className="max-w-[200px] truncate text-neutral-200">{attachment.filename}</span>
        <span className="text-xs text-neutral-500">{sizeKb} KB</span>
      </div>
    </a>
  );
}
