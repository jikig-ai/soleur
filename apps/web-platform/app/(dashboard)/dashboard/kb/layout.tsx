"use client";

import { useState, useEffect, useCallback, useMemo, useRef } from "react";
import { useSidebarCollapse } from "@/hooks/use-sidebar-collapse";
import type { ReactNode } from "react";
import { usePathname, useRouter } from "next/navigation";
import dynamic from "next/dynamic";
import { KbContext } from "@/components/kb/kb-context";
import type { KbContextValue } from "@/components/kb/kb-context";
import { KbChatContext } from "@/components/kb/kb-chat-context";
import type { KbChatContextValue } from "@/components/kb/kb-chat-context";
import { FileTree } from "@/components/kb/file-tree";
import { SearchOverlay } from "@/components/kb/search-overlay";
import { getAncestorPaths } from "@/components/kb/get-ancestor-paths";
import {
  DesktopPlaceholder,
  EmptyState,
  KbErrorBoundary,
  LoadingSkeleton,
  NoProjectState,
  UnknownError,
  WorkspaceNotReady,
} from "@/components/kb";
import type { TreeNode } from "@/server/kb-reader";

const KbChatSidebar = dynamic(
  () => import("@/components/chat/kb-chat-sidebar").then((m) => m.KbChatSidebar),
  { ssr: false, loading: () => null },
);

const KB_SIDEBAR_OPEN_KEY = "kb.chat.sidebarOpen";

function deriveContextPathFromPathname(pathname: string): string | null {
  if (!pathname.startsWith("/dashboard/kb/")) return null;
  if (pathname === "/dashboard/kb" || pathname === "/dashboard/kb/") return null;
  const rel = decodeURIComponent(pathname.slice("/dashboard/kb/".length));
  return rel ? `knowledge-base/${rel}` : null;
}

export default function KbLayout({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [tree, setTree] = useState<TreeNode | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<KbContextValue["error"]>(null);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  // Runtime feature flag — fetched from /api/flags (not build-time NEXT_PUBLIC_*)
  const [kbChatFlag, setKbChatFlag] = useState(false);
  useEffect(() => {
    fetch("/api/flags")
      .then((r) => r.json())
      .then((flags: Record<string, boolean>) => {
        setKbChatFlag(flags["kb-chat-sidebar"] ?? false);
      })
      .catch(() => {}); // flags stay off if fetch fails
  }, []);

  const fetchTree = useCallback(async (signal?: AbortSignal) => {
    try {
      const res = await fetch("/api/kb/tree", { signal });
      if (signal?.aborted) return;
      if (res.status === 401) {
        router.push("/login");
        return;
      }
      if (res.status === 503) {
        setError("workspace-not-ready");
        setLoading(false);
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
      setTree(data.tree);
      setLoading(false);
    } catch {
      if (!signal?.aborted) {
        setError("unknown");
        setLoading(false);
      }
    }
  }, [router]);

  useEffect(() => {
    const controller = new AbortController();
    fetchTree(controller.signal);
    return () => { controller.abort(); };
  }, [fetchTree]);

  const refreshTree = useCallback(async () => {
    await fetchTree();
  }, [fetchTree]);

  const toggleExpanded = useCallback((path: string) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(path)) {
        next.delete(path);
      } else {
        next.add(path);
      }
      return next;
    });
  }, []);

  // Auto-expand ancestor directories when navigating to a file
  useEffect(() => {
    if (!pathname.startsWith("/dashboard/kb/") || pathname === "/dashboard/kb") {
      return;
    }
    const relativePath = decodeURIComponent(pathname.slice("/dashboard/kb/".length));
    const ancestors = getAncestorPaths(relativePath);
    if (ancestors.length === 0) return;

    setExpanded((prev) => {
      const next = new Set(prev);
      let changed = false;
      for (const dir of ancestors) {
        if (!next.has(dir)) {
          next.add(dir);
          changed = true;
        }
      }
      return changed ? next : prev;
    });
  }, [pathname]);

  const [kbCollapsed, toggleKbCollapsed] = useSidebarCollapse("soleur:sidebar.kb.collapsed");

  // Cmd+B / Ctrl+B toggles KB file tree sidebar (only on KB routes, not in inputs)
  useEffect(() => {
    function handleToggleShortcut(e: KeyboardEvent) {
      if (!(e.metaKey || e.ctrlKey) || e.key !== "b") return;
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      if ((e.target as HTMLElement)?.isContentEditable) return;
      if (!pathname.startsWith("/dashboard/kb")) return;
      e.preventDefault();
      toggleKbCollapsed();
    }
    document.addEventListener("keydown", handleToggleShortcut);
    return () => document.removeEventListener("keydown", handleToggleShortcut);
  }, [pathname, toggleKbCollapsed]);

  const isContentView = pathname !== "/dashboard/kb";
  const hasTreeContent = tree?.children && tree.children.length > 0;

  const ctxValue: KbContextValue = useMemo(() => ({
    tree,
    loading,
    error,
    expanded,
    toggleExpanded,
    refreshTree,
  }), [tree, loading, error, expanded, toggleExpanded, refreshTree]);

  // --- Chat sidebar state -------------------------------------------------
  const contextPath = useMemo(() => deriveContextPathFromPathname(pathname), [pathname]);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [messageCount, setMessageCount] = useState(0);
  const quoteHandlerRef = useRef<((text: string) => void) | null>(null);

  // Restore sidebarOpen from sessionStorage on mount (per-tab persistence)
  useEffect(() => {
    if (!kbChatFlag) return;
    try {
      const saved = sessionStorage.getItem(KB_SIDEBAR_OPEN_KEY);
      if (saved === "1") setSidebarOpen(true);
    } catch { /* sessionStorage unavailable */ }
  }, [kbChatFlag]);

  const openSidebar = useCallback(() => {
    setSidebarOpen(true);
    try { sessionStorage.setItem(KB_SIDEBAR_OPEN_KEY, "1"); } catch { /* noop */ }
  }, []);

  const closeSidebar = useCallback(() => {
    setSidebarOpen(false);
    try { sessionStorage.setItem(KB_SIDEBAR_OPEN_KEY, "0"); } catch { /* noop */ }
  }, []);

  const registerQuoteHandler = useCallback(
    (handler: ((text: string) => void) | null) => {
      quoteHandlerRef.current = handler;
    },
    [],
  );

  const submitQuote = useCallback(
    (text: string) => {
      setSidebarOpen(true);
      try { sessionStorage.setItem(KB_SIDEBAR_OPEN_KEY, "1"); } catch { /* noop */ }
      // Give the sidebar a tick to mount + register its handler before inserting.
      queueMicrotask(() => {
        quoteHandlerRef.current?.(text);
      });
    },
    [],
  );

  const chatCtxValue: KbChatContextValue = useMemo(() => ({
    open: sidebarOpen,
    openSidebar,
    closeSidebar,
    contextPath,
    enabled: kbChatFlag,
    submitQuote,
    registerQuoteHandler,
    messageCount,
    setMessageCount,
  }), [sidebarOpen, openSidebar, closeSidebar, contextPath, kbChatFlag, submitQuote, registerQuoteHandler, messageCount]);

  // Full-width states: loading, errors, or empty KB (no sidebar needed)
  if (loading || error || (!loading && !hasTreeContent)) {
    return (
      <KbContext value={ctxValue}>
        <KbChatContext value={chatCtxValue}>
          {loading && <LoadingSkeleton />}
          {error === "workspace-not-ready" && <WorkspaceNotReady />}
          {error === "not-found" && <NoProjectState />}
          {error === "unknown" && <UnknownError />}
          {!loading && !error && !hasTreeContent && <EmptyState />}
        </KbChatContext>
      </KbContext>
    );
  }

  // Two-panel layout: tree sidebar + content area
  return (
    <KbContext value={ctxValue}>
      <KbChatContext value={chatCtxValue}>
        <div className="flex h-full">
          {/* Tree sidebar — visible on desktop always, on mobile only at root */}
          <aside
            className={`w-full shrink-0 overflow-y-auto border-r border-neutral-800 md:block
              md:transition-[width] md:duration-200 md:ease-out
              ${kbCollapsed ? "md:w-0 md:overflow-hidden md:border-r-0" : "md:w-64"}
              ${isContentView ? "hidden" : "block"}`}
          >
            <div className="flex h-full flex-col">
              <header className="flex shrink-0 items-center justify-between px-4 pb-3 pt-4">
                <h1 className="font-serif text-lg font-medium tracking-tight text-white">
                  Knowledge Base
                </h1>
                <button
                  onClick={toggleKbCollapsed}
                  aria-label="Collapse file tree"
                  className="hidden md:flex h-6 w-6 items-center justify-center rounded text-neutral-400 hover:bg-neutral-800 hover:text-white"
                >
                  <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                    <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
                  </svg>
                </button>
              </header>
              <div className="shrink-0 px-3 pb-3">
                <SearchOverlay />
              </div>
              <div className="flex-1 overflow-y-auto px-2 pb-4">
                <FileTree />
              </div>
            </div>
          </aside>

          {/* Content area — visible on desktop always, on mobile only when viewing content */}
          <div
            className={`min-w-0 flex-1 overflow-y-auto md:block ${
              isContentView ? "block" : "hidden"
            }`}
          >
            {kbCollapsed && (
              <button
                onClick={toggleKbCollapsed}
                aria-label="Expand file tree"
                className="hidden md:flex m-2 h-8 w-8 items-center justify-center rounded-lg border border-neutral-800 text-neutral-400 hover:bg-neutral-800 hover:text-white"
              >
                <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
                </svg>
              </button>
            )}
            <KbErrorBoundary>
              {isContentView ? children : <DesktopPlaceholder />}
            </KbErrorBoundary>
          </div>

          {kbChatFlag && contextPath && (
            <KbChatSidebar
              open={sidebarOpen}
              onClose={closeSidebar}
              contextPath={contextPath}
            />
          )}
        </div>
      </KbChatContext>
    </KbContext>
  );
}
