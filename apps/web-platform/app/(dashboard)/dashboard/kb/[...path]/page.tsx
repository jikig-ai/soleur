"use client";

import { useState, useEffect, useRef, use, useContext } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { safeDecode } from "@/components/kb/kb-breadcrumb";
import { FilePreview } from "@/components/kb/file-preview";
import { KbContentHeader } from "@/components/kb/kb-content-header";
import { KbContentSkeleton } from "@/components/kb/kb-content-skeleton";
import { KbChatContext } from "@/components/kb/kb-chat-context";
import { KbChatQuoteBridgeContext } from "@/components/kb/kb-chat-quote-bridge";
import { SelectionToolbar } from "@/components/kb/selection-toolbar";
import { getKbExtension, isMarkdownKbPath } from "@/lib/kb-extensions";
import { classifyByExtension } from "@/lib/kb-file-kind";
import type { ContentResult } from "@/server/kb-reader";

export default function KbContentPage({
  params,
}: {
  params: Promise<{ path: string[] }>;
}) {
  const { path: pathSegments } = use(params);
  const router = useRouter();
  const joinedPath = pathSegments.join("/");
  const extension = getKbExtension(joinedPath);
  const isMarkdown = isMarkdownKbPath(joinedPath);
  const [content, setContent] = useState<ContentResult | null>(null);
  const [loading, setLoading] = useState(isMarkdown);
  const [error, setError] = useState<"not-found" | "unknown" | null>(null);
  const articleRef = useRef<HTMLElement>(null);
  const kbChat = useContext(KbChatContext);
  const quoteBridge = useContext(KbChatQuoteBridgeContext);

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
    return (
      <div className="p-6 md:p-8">
        <div className="mx-auto max-w-3xl space-y-4">
          <div className="h-4 w-48 animate-pulse rounded bg-neutral-800" />
          <KbContentSkeleton
            widths={["85%", "70%", "90%", "65%", "80%", "75%"]}
          />
        </div>
      </div>
    );
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
    const rawFilename = pathSegments[pathSegments.length - 1] ?? joinedPath;
    const filename = safeDecode(rawFilename);
    const contentUrl = `/api/kb/content/${joinedPath}`;

    return (
      <div className="flex h-full flex-col">
        <KbContentHeader
          joinedPath={joinedPath}
          chatUrl={chatUrl}
          download={{ href: contentUrl, filename }}
        />
        <div className="min-h-0 flex-1">
          <FilePreview
            path={joinedPath}
            kind={classifyByExtension(extension)}
            showDownload={false}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      <KbContentHeader joinedPath={joinedPath} chatUrl={chatUrl} />

      {/* Rendered markdown content */}
      <article
        ref={articleRef}
        className="flex-1 overflow-y-auto px-4 py-6 md:px-8"
        style={{ userSelect: "text" }}
      >
        <div className="mx-auto max-w-3xl">
          <div className="prose-kb">
            <MarkdownRenderer content={content!.content} />
          </div>
        </div>
      </article>
      {kbChat?.enabled && quoteBridge && (
        <SelectionToolbar
          articleRef={articleRef}
          onAddToChat={quoteBridge.submitQuote}
        />
      )}
    </div>
  );
}

