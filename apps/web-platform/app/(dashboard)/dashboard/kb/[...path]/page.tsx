"use client";

import { useState, useEffect, use } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { KbBreadcrumb } from "@/components/kb/kb-breadcrumb";
import { SharePopover } from "@/components/kb/share-popover";
import { FilePreview } from "@/components/kb/file-preview";
import type { ContentResult } from "@/server/kb-reader";

export default function KbContentPage({
  params,
}: {
  params: Promise<{ path: string[] }>;
}) {
  const { path: pathSegments } = use(params);
  const router = useRouter();
  const joinedPath = pathSegments.join("/");
  const extension = joinedPath.includes(".") ? `.${joinedPath.split(".").pop()}` : "";
  const isMarkdown = extension === ".md" || extension === "";
  const [content, setContent] = useState<ContentResult | null>(null);
  const [loading, setLoading] = useState(isMarkdown);
  const [error, setError] = useState<"not-found" | "unknown" | null>(null);

  useEffect(() => {
    // Non-markdown files are rendered by FilePreview — no fetch needed
    if (!isMarkdown) return;

    setLoading(true);
    let cancelled = false;
    async function fetchContent() {
      try {
        const res = await fetch(`/api/kb/content/${joinedPath}`);
        if (!cancelled) {
          if (res.status === 401) {
            router.replace("/login");
            return;
          }
          if (res.status === 404) {
            setError("not-found");
            setLoading(false);
            return;
          }
          if (!res.ok) {
            setError("unknown");
            setLoading(false);
            return;
          }
          const data = await res.json();
          setContent(data);
          setLoading(false);
        }
      } catch {
        if (!cancelled) {
          setError("unknown");
          setLoading(false);
        }
      }
    }
    fetchContent();
    return () => { cancelled = true; };
  }, [joinedPath, router, isMarkdown]);

  if (loading) {
    return <ContentSkeleton />;
  }

  if (error === "not-found") {
    return (
      <div className="flex h-full items-center justify-center p-6">
        <div className="text-center">
          <p className="mb-2 text-sm text-neutral-400">
            File not found. This file may have been renamed or removed.
          </p>
          <Link
            href="/dashboard/kb"
            className="text-sm text-amber-400 underline hover:text-amber-300"
          >
            Back to file tree
          </Link>
        </div>
      </div>
    );
  }

  if (error || (!content && isMarkdown)) {
    return (
      <div className="flex h-full items-center justify-center p-6">
        <div className="text-center">
          <p className="text-sm text-neutral-400">
            Unable to load this file. Please try again later.
          </p>
        </div>
      </div>
    );
  }

  const chatUrl = `/dashboard/chat/new?msg=${encodeURIComponent(`Tell me about the file at ${joinedPath}`)}&leader=cto&context=${encodeURIComponent(joinedPath)}`;

  // Non-markdown files get FilePreview
  if (!isMarkdown) {
    return (
      <div className="flex h-full flex-col">
        <header className="flex shrink-0 items-center justify-between border-b border-neutral-800 px-4 py-3 md:px-6">
          <div className="flex items-center gap-2">
            <Link
              href="/dashboard/kb"
              aria-label="Back to file tree"
              className="flex items-center text-neutral-400 hover:text-white md:hidden"
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="15 18 9 12 15 6" />
              </svg>
            </Link>
            <KbBreadcrumb path={joinedPath} />
          </div>
          <div className="flex items-center gap-2">
            <SharePopover documentPath={joinedPath} />
            <Link
              href={chatUrl}
              className="inline-flex items-center gap-1.5 rounded-lg border border-amber-500/50 px-3 py-1.5 text-xs font-medium text-amber-400 transition-colors hover:border-amber-400 hover:text-amber-300"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="shrink-0">
                <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2Z" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              Chat about this
            </Link>
          </div>
        </header>
        <div className="flex-1 overflow-y-auto">
          <FilePreview path={joinedPath} extension={extension} />
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      {/* Header with back arrow, breadcrumb, and chat link */}
      <header className="flex shrink-0 items-center justify-between border-b border-neutral-800 px-4 py-3 md:px-6">
        <div className="flex items-center gap-2">
          {/* Mobile back arrow */}
          <Link
            href="/dashboard/kb"
            aria-label="Back to file tree"
            className="flex items-center text-neutral-400 hover:text-white md:hidden"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="15 18 9 12 15 6" />
            </svg>
          </Link>
          <KbBreadcrumb path={joinedPath} />
        </div>
        <div className="flex items-center gap-2">
          <SharePopover documentPath={joinedPath} />
          <Link
            href={chatUrl}
            className="inline-flex items-center gap-1.5 rounded-lg border border-amber-500/50 px-3 py-1.5 text-xs font-medium text-amber-400 transition-colors hover:border-amber-400 hover:text-amber-300"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="shrink-0">
              <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2Z" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            Chat about this
          </Link>
        </div>
      </header>

      {/* Rendered markdown content */}
      <article className="flex-1 overflow-y-auto px-4 py-6 md:px-8">
        <div className="mx-auto max-w-3xl">
          <div className="prose-kb">
            <MarkdownRenderer content={content!.content} />
          </div>
        </div>
      </article>
    </div>
  );
}

const CONTENT_SKELETON_WIDTHS = ["85%", "70%", "90%", "65%", "80%", "75%"];

function ContentSkeleton() {
  return (
    <div className="p-6 md:p-8">
      <div className="mx-auto max-w-3xl space-y-4">
        <div className="h-4 w-48 animate-pulse rounded bg-neutral-800" />
        <div className="h-8 w-64 animate-pulse rounded bg-neutral-800" />
        <div className="space-y-2">
          {CONTENT_SKELETON_WIDTHS.map((w, i) => (
            <div
              key={i}
              className="h-4 animate-pulse rounded bg-neutral-800"
              style={{ width: w }}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
