"use client";

import { useState, useEffect, use } from "react";
import Link from "next/link";
import dynamic from "next/dynamic";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { CtaBanner } from "@/components/shared/cta-banner";
import {
  SHARED_CONTENT_KIND_HEADER,
  isSharedContentKind,
  type SharedContentKind,
} from "@/lib/shared-kind";

// Dynamic import with ssr: false — pdf-preview touches `import.meta.url` and
// pdfjs worker globals at module load, which fail during server render.
const PdfPreview = dynamic(
  () => import("@/components/kb/pdf-preview").then((mod) => mod.PdfPreview),
  {
    ssr: false,
    loading: () => (
      <div className="flex items-center justify-center p-8">
        <div className="h-5 w-5 animate-spin rounded-full border-2 border-neutral-600 border-t-amber-400" />
      </div>
    ),
  },
);

type SharedKind = SharedContentKind;

type SharedData =
  | { kind: "markdown"; content: string; path: string }
  | { kind: "pdf"; src: string; filename: string }
  | { kind: "image"; src: string; alt: string }
  | { kind: "download"; src: string; filename: string };

type PageError = "not-found" | "revoked" | "content-changed" | "unknown";

/**
 * Parse a `Content-Disposition` filename per RFC 5987. Prefers the
 * `filename*=UTF-8''...` encoding (non-ASCII safe) and falls back to the
 * ASCII `filename="..."` form. Returns `null` when neither is present so
 * callers can substitute a stable fallback instead of the literal "file".
 */
function extractFilename(contentDisposition: string | null): string | null {
  if (!contentDisposition) return null;
  const utf8 = contentDisposition.match(/filename\*\s*=\s*UTF-8''([^;]+)/i);
  if (utf8?.[1]) {
    try {
      return decodeURIComponent(utf8[1].trim());
    } catch {
      // Fall through to ASCII filename.
    }
  }
  const ascii = contentDisposition.match(/filename\s*=\s*"?([^";]+)"?/i);
  return ascii?.[1]?.trim() || null;
}

function basenameFromToken(token: string): string {
  // Last-resort label when both RFC 5987 and ASCII filename parsing fail.
  // Only hit on a server that violates the Content-Disposition contract.
  return `shared-${token}`;
}


export default function SharedDocumentPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = use(params);
  const [data, setData] = useState<SharedData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<PageError | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function fetchSharedContent() {
      try {
        const res = await fetch(`/api/shared/${token}`);
        if (cancelled) return;
        if (res.status === 404) {
          setError("not-found");
          setLoading(false);
          return;
        }
        if (res.status === 410) {
          // Discriminate via response body `code` so we can show tailored
          // copy for content-changed without disturbing the existing revoked
          // path. Fall back to "revoked" copy if the body is missing/unparseable.
          const body = await res.json().catch(() => null);
          const code = body && typeof body === "object" ? body.code : null;
          if (code === "content-changed" || code === "legacy-null-hash") {
            setError("content-changed");
          } else {
            setError("revoked");
          }
          setLoading(false);
          return;
        }
        if (!res.ok) {
          setError("unknown");
          setLoading(false);
          return;
        }
        // Server-declared kind — branch on X-Soleur-Kind (emitted by
        // /api/shared/[token] for every success response) rather than
        // sniffing the content-type string. Keeps the UI decoupled from
        // the transport mime map and makes "new kind added without a
        // render branch" a compile error (exhaustive switch below).
        const headerKind = res.headers.get(SHARED_CONTENT_KIND_HEADER);
        const kind: SharedKind | null = isSharedContentKind(headerKind)
          ? headerKind
          : null;
        if (!kind) {
          setError("unknown");
          setLoading(false);
          return;
        }
        const disposition = res.headers.get("content-disposition");
        const label = extractFilename(disposition) ?? basenameFromToken(token);
        const src = `/api/shared/${token}`;

        switch (kind) {
          case "markdown": {
            const json = await res.json();
            setData({
              kind: "markdown",
              content: json.content,
              path: json.path,
            });
            break;
          }
          case "pdf":
            setData({ kind: "pdf", src, filename: label });
            break;
          case "image":
            setData({ kind: "image", src, alt: label });
            break;
          case "download":
            setData({ kind: "download", src, filename: label });
            break;
          default: {
            // Exhaustiveness guard — adding a new SharedKind without a
            // render branch fails the build here instead of silently
            // falling through to `download`.
            const _exhaustive: never = kind;
            void _exhaustive;
            setError("unknown");
          }
        }
        setLoading(false);
      } catch {
        if (!cancelled) {
          setError("unknown");
          setLoading(false);
        }
      }
    }
    fetchSharedContent();
    return () => { cancelled = true; };
  }, [token]);

  return (
    <>
      <head>
        <meta name="robots" content="noindex" />
      </head>
      <div className="min-h-screen bg-neutral-950 text-neutral-200">
        {/* Soleur branded header */}
        <header className="border-b border-neutral-800 px-4 py-3">
          <div className="mx-auto flex max-w-3xl items-center justify-between">
            <Link href="https://soleur.ai" className="text-lg font-semibold text-white">
              Soleur
            </Link>
            <span className="text-xs text-neutral-500">Shared document</span>
          </div>
        </header>

        {/* Content */}
        <main className="px-4 pb-20 pt-6">
          <div className="mx-auto max-w-3xl">
            {loading && <LoadingSkeleton />}

            {error === "not-found" && (
              <ErrorMessage
                title="Document not found"
                message="This document may have been removed or the link is invalid."
              />
            )}

            {error === "revoked" && (
              <ErrorMessage
                title="This link has been disabled"
                message="The owner has revoked access to this document."
              />
            )}

            {error === "content-changed" && (
              <ErrorMessage
                title="The shared file was modified"
                message="The file has been edited or replaced since this link was created. Ask the owner to share again."
              />
            )}

            {error === "unknown" && (
              <ErrorMessage
                title="Something went wrong"
                message="Unable to load this document. Please try again later."
              />
            )}

            {data?.kind === "markdown" && (
              <article className="prose-kb">
                <MarkdownRenderer content={data.content} nofollow />
              </article>
            )}

            {data?.kind === "pdf" && (
              <div className="h-[70vh]">
                <PdfPreview src={data.src} filename={data.filename} />
              </div>
            )}

            {data?.kind === "image" && (
              <div className="flex justify-center">
                <img
                  data-testid="shared-image"
                  src={data.src}
                  alt={data.alt}
                  className="max-h-[80vh] max-w-full rounded-lg border border-neutral-800"
                />
              </div>
            )}

            {data?.kind === "download" && (
              <div className="flex flex-col items-center justify-center py-20 text-center">
                <h1 className="mb-2 text-lg font-semibold text-white">
                  {data.filename}
                </h1>
                <p className="mb-6 text-sm text-neutral-400">
                  Download to view this file.
                </p>
                <a
                  data-testid="shared-download"
                  href={data.src}
                  download={data.filename}
                  className="inline-flex items-center gap-2 rounded-lg border border-amber-500/50 px-4 py-2 text-sm font-medium text-amber-400 transition-colors hover:border-amber-400 hover:text-amber-300"
                >
                  Download {data.filename}
                </a>
              </div>
            )}
          </div>
        </main>

        {/* CTA banner — only show when content loaded successfully */}
        {data && <CtaBanner />}
      </div>
    </>
  );
}

function ErrorMessage({ title, message }: { title: string; message: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-20 text-center">
      <h1 className="mb-2 text-lg font-semibold text-white">{title}</h1>
      <p className="mb-6 text-sm text-neutral-400">{message}</p>
      <Link
        href="https://soleur.ai"
        className="text-sm text-amber-400 underline hover:text-amber-300"
      >
        Learn about Soleur
      </Link>
    </div>
  );
}

function LoadingSkeleton() {
  return (
    <div className="space-y-4">
      <div className="h-8 w-64 animate-pulse rounded bg-neutral-800" />
      <div className="space-y-2">
        {["85%", "70%", "90%", "65%", "80%"].map((w, i) => (
          <div
            key={i}
            className="h-4 animate-pulse rounded bg-neutral-800"
            style={{ width: w }}
          />
        ))}
      </div>
    </div>
  );
}
