"use client";

import { useState, useEffect, useMemo, useRef, use, useContext } from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { parseLikeC4Embed } from "@/lib/c4-embed";
import { safeDecode } from "@/components/kb/kb-breadcrumb";
import { FilePreview } from "@/components/kb/file-preview";
import { KbContentHeader } from "@/components/kb/kb-content-header";
import { KbContentSkeleton } from "@/components/kb/kb-content-skeleton";
import { KbContext } from "@/components/kb/kb-context";
import { KbChatContext } from "@/components/kb/kb-chat-context";
import { KbChatQuoteBridgeContext } from "@/components/kb/kb-chat-quote-bridge";
import { SelectionToolbar } from "@/components/kb/selection-toolbar";
import { getKbExtension, isMarkdownKbPath } from "@/lib/kb-extensions";
import { classifyByExtension } from "@/lib/kb-file-kind";
import { useOptionalFeatureFlag } from "@/components/feature-flags/provider";
import { C4_VISUALIZER_FLAG } from "@/lib/c4-constants";
import type { ContentResult } from "@/server/kb-reader";

// Full-screen LikeC4 workspace (diagram ‖ Concierge/Code). Browser-only
// (@likec4/diagram is canvas-based) so it loads client-side after mount.
const C4Workspace = dynamic(() => import("@/components/kb/c4-workspace"), {
  ssr: false,
  loading: () => (
    <div className="flex h-full items-center justify-center">
      <div className="h-5 w-5 animate-spin rounded-full border-2 border-soleur-border-default border-t-amber-400" />
    </div>
  ),
});

export default function KbContentPage({
  params,
}: {
  params: Promise<{ path: string[] }>;
}) {
  const { path: pathSegments } = use(params);
  const joinedPath = pathSegments.join("/");
  const extension = getKbExtension(joinedPath);
  const isMarkdown = isMarkdownKbPath(joinedPath);
  const c4Enabled = useOptionalFeatureFlag(C4_VISUALIZER_FLAG);
  // The LikeC4 project lives in the same dir as the .md view-embed page.
  const c4DirPath = pathSegments.slice(0, -1).join("/");
  const [content, setContent] = useState<ContentResult | null>(null);
  const [loading, setLoading] = useState(isMarkdown);
  const [error, setError] = useState<"not-found" | "unknown" | null>(null);
  const articleRef = useRef<HTMLElement>(null);
  const kbChat = useContext(KbChatContext);
  const quoteBridge = useContext(KbChatQuoteBridgeContext);
  // #4224 — KB layout publishes the latest sync row + a refresh hook.
  // Use the raw context (not the gated `useKb()` hook) so the page also
  // renders in test surfaces that exercise it without KbLayout wrap.
  const kbCtx = useContext(KbContext);
  const lastSync = kbCtx?.lastSync ?? undefined;
  const refreshTree = kbCtx?.refreshTree;

  // A diagram page is markdown that embeds a ```likec4-view block, with the
  // c4-visualizer flag on. Computed once here (top-level, before the early
  // returns) so the suppression effect below has a stable dependency.
  const c4Embed = useMemo(
    () =>
      isMarkdown && c4Enabled && content
        ? parseLikeC4Embed(content.content)
        : null,
    [isMarkdown, c4Enabled, content],
  );

  // The C4 workspace renders its own Concierge beside the diagram, so suppress
  // the desktop side chat panel for this doc (else two KbChatContent mount with
  // the same contextPath). setSuppressSidebar is a stable useState setter.
  const setSuppressSidebar = kbChat?.setSuppressSidebar;
  const suppressChat = !!c4Embed;
  useEffect(() => {
    setSuppressSidebar?.(suppressChat);
    return () => setSuppressSidebar?.(false);
  }, [suppressChat, setSuppressSidebar]);

  useEffect(() => {
    // Non-markdown files are rendered by FilePreview — no fetch needed
    if (!isMarkdown) return;

    setLoading(true);
    let cancelled = false;
    async function fetchContent() {
      try {
        const res = await fetch(`/api/kb/content/${joinedPath}`);
        if (!cancelled) {
          // GAP F (ADR-067 staleTimes): revocation bounce — HARD-nav to wipe the
          // Router Cache. Detect the direct 401 AND the #4307 middleware
          // 302→/login (fetch follows the redirect to 200 HTML, so 401-only
          // never fires).
          if (
            res.status === 401 ||
            (res.redirected && new URL(res.url).pathname === "/login")
          ) {
            window.location.assign("/login");
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
  }, [joinedPath, isMarkdown]);

  if (loading) {
    return (
      <div className="p-6 md:p-8">
        <div className="mx-auto max-w-3xl space-y-4">
          <div className="h-4 w-48 animate-pulse rounded bg-soleur-bg-surface-2" />
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
          <p className="mb-2 text-sm text-soleur-text-secondary">
            File not found. This file may have been renamed or removed.
          </p>
          <Link
            href="/dashboard/kb"
            className="text-sm text-soleur-accent-gold-fg underline hover:text-soleur-accent-gold-text"
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
          <p className="text-sm text-soleur-text-secondary">
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
          lastSync={lastSync}
          onSynced={refreshTree}
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

  // A KB diagram page (markdown that embeds a ```likec4-view block) becomes a
  // full-screen workspace: diagram on the left, Soleur Concierge / Code on the
  // right (c4Embed computed at the top). contextPath mirrors the KbChat sidebar
  // format so the embedded Concierge resumes the same document thread.
  if (c4Embed) {
    return (
      <div className="flex h-full flex-col">
        <KbContentHeader
          joinedPath={joinedPath}
          chatUrl={chatUrl}
          lastSync={lastSync}
          onSynced={refreshTree}
        />
        <div className="min-h-0 flex-1">
          <C4Workspace
            viewId={c4Embed.viewId}
            dirPath={c4DirPath}
            contextPath={`knowledge-base/${joinedPath}`}
            notes={c4Embed.notes}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      <KbContentHeader
        joinedPath={joinedPath}
        chatUrl={chatUrl}
        lastSync={lastSync}
        onSynced={refreshTree}
      />

      {/* Rendered markdown content */}
      <article
        ref={articleRef}
        className="flex-1 overflow-y-auto px-4 py-6 md:px-8"
        style={{ userSelect: "text" }}
      >
        <div className="mx-auto max-w-3xl">
          <div className="prose-kb">
            <MarkdownRenderer
              content={content!.content}
              enableC4={c4Enabled}
              c4DirPath={c4DirPath}
            />
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

