"use client";

import { useState, useEffect, use } from "react";
import Link from "next/link";
import dynamic from "next/dynamic";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { CtaBanner } from "@/components/shared/cta-banner";
import { KbContentSkeleton } from "@/components/kb/kb-content-skeleton";
import { TextPreview } from "@/components/kb/text-preview";
import { SHARED_CONTENT_KIND_HEADER } from "@/lib/shared-kind";
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
        <div className="h-5 w-5 animate-spin rounded-full border-2 border-soleur-text-muted border-t-amber-400" />
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
    async function run(): Promise<{ data: SharedData } | { error: PageError }> {
      // HEAD first — discriminate content kind (and short-circuit error
      // states) without paying a full GET that the browser would repeat
      // as the embed's `<src>` fetch. On cold PDF views this eliminates
      // one 50 MB server-side stream (see #2324). For binary kinds the
      // HEAD response alone carries all the headers classifyResponse
      // needs; markdown requires a follow-up GET for the JSON body; and
      // 410 requires a GET to read the JSON `code` field so revoked vs.
      // content-changed can be discriminated.
      const headRes = await fetch(`/api/shared/${token}`, { method: "HEAD" });
      if (headRes.status === 410) {
        const getRes = await fetch(`/api/shared/${token}`);
        return classifyResponse(getRes, token);
      }
      if (!headRes.ok) {
        return classifyResponse(headRes, token);
      }
      const kind = headRes.headers.get(SHARED_CONTENT_KIND_HEADER);
      if (kind === "markdown") {
        const getRes = await fetch(`/api/shared/${token}`);
        return classifyResponse(getRes, token);
      }
      return classifyResponse(headRes, token);
    }
    run()
      .catch((): { error: PageError } => ({ error: "unknown" }))
      .then((result) => {
        if (cancelled) return;
        if ("error" in result) setError(result.error);
        else setData(result.data);
        setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [token]);

  return (
    <>
      <head>
        <meta name="robots" content="noindex" />
      </head>
      <div className="min-h-screen bg-soleur-bg-base text-soleur-text-primary">
        {/* Soleur branded header */}
        <header className="border-b border-soleur-border-default px-4 py-3">
          <div className="mx-auto flex max-w-3xl items-center justify-between">
            <Link href="https://soleur.ai" className="text-lg font-semibold text-soleur-text-primary">
              Soleur
            </Link>
            <span className="text-xs text-soleur-text-muted">Shared document</span>
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

            {data && renderSharedContent(data)}
          </div>
        </main>

        {/* CTA banner — only show when content loaded successfully */}
        {data && <CtaBanner />}
      </div>
    </>
  );
}

function renderSharedContent(data: SharedData) {
  switch (data.kind) {
    case "markdown":
      return (
        <article className="prose-kb">
          <MarkdownRenderer content={data.content} nofollow />
        </article>
      );
    case "pdf":
      return (
        <div className="h-[70vh]">
          <PdfPreview src={data.src} filename={data.filename} />
        </div>
      );
    case "image":
      return (
        <div className="flex justify-center">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            data-testid="shared-image"
            src={data.src}
            alt="Shared image"
            title={data.filename ?? undefined}
            className="max-h-[80vh] max-w-full rounded-lg border border-soleur-border-default"
          />
        </div>
      );
    case "text":
      return <TextPreview src={data.src} filename={data.filename} showDownload={true} />;
    case "download":
      return (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <h1 className="mb-2 text-lg font-semibold text-soleur-text-primary">{data.filename}</h1>
          <p className="mb-6 text-sm text-soleur-text-secondary">Download to view this file.</p>
          <a
            data-testid="shared-download"
            href={data.src}
            download={data.filename}
            className="inline-flex items-center gap-2 rounded-lg border border-soleur-border-emphasized px-4 py-2 text-sm font-medium text-soleur-accent-gold-fg transition-colors hover:border-amber-400 hover:text-soleur-accent-gold-text"
          >
            Download {data.filename}
          </a>
        </div>
      );
    default: {
      // Exhaustiveness guard — widening SharedContentKind without a
      // renderer here fails the build.
      const _exhaustive: never = data;
      void _exhaustive;
      return null;
    }
  }
}

function ErrorMessage({ title, message }: { title: string; message: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-20 text-center">
      <h1 className="mb-2 text-lg font-semibold text-soleur-text-primary">{title}</h1>
      <p className="mb-6 text-sm text-soleur-text-secondary">{message}</p>
      <Link
        href="https://soleur.ai"
        className="text-sm text-soleur-accent-gold-fg underline hover:text-soleur-accent-gold-text"
      >
        Learn about Soleur
      </Link>
    </div>
  );
}
