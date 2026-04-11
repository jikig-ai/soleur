"use client";

import { useState, useEffect, use } from "react";
import Link from "next/link";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { CtaBanner } from "@/components/shared/cta-banner";

interface SharedContent {
  content: string;
  path: string;
}

type PageError = "not-found" | "revoked" | "unknown";

export default function SharedDocumentPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = use(params);
  const [data, setData] = useState<SharedContent | null>(null);
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
          setError("revoked");
          setLoading(false);
          return;
        }
        if (!res.ok) {
          setError("unknown");
          setLoading(false);
          return;
        }
        const json = await res.json();
        setData(json);
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

            {error === "unknown" && (
              <ErrorMessage
                title="Something went wrong"
                message="Unable to load this document. Please try again later."
              />
            )}

            {data && (
              <article className="prose-kb">
                <MarkdownRenderer content={data.content} nofollow />
              </article>
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
