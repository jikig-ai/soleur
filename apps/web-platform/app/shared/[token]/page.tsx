"use client";

import { useState, useEffect, use } from "react";
import Link from "next/link";
import dynamic from "next/dynamic";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { CtaBanner } from "@/components/shared/cta-banner";
import { KbContentSkeleton } from "@/components/kb/kb-content-skeleton";
import {
  classifyResponse,
  type PageError,
  type SharedData,
} from "./classify-response";

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
    (async () => {
      try {
        const res = await fetch(`/api/shared/${token}`);
        if (cancelled) return;
        const result = await classifyResponse(res, token);
        if (cancelled) return;
        if ("error" in result) {
          setError(result.error);
        } else {
          setData(result.data);
        }
      } catch {
        if (!cancelled) setError("unknown");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
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
            {loading && <KbContentSkeleton />}

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
                  alt="Shared image"
                  {...(data.filename ? { title: data.filename } : {})}
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
