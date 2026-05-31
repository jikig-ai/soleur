"use client";

import { useState, useEffect, useCallback, useMemo, useRef } from "react";
import { usePathname, useRouter } from "next/navigation";
import { usePanelRef } from "react-resizable-panels";
import { useMediaQuery } from "@/hooks/use-media-query";
import { useFeatureFlag } from "@/components/feature-flags/provider";
import type { KbContextValue } from "@/components/kb/kb-context";
import type { KbChatContextValue } from "@/components/kb/kb-chat-context";
import { safeSession } from "@/lib/safe-session";
import { getAncestorPaths } from "@/components/kb/get-ancestor-paths";
import type { TreeNode } from "@/server/kb-reader";
import type { KbSyncHistoryRow } from "@/components/kb/kb-sync-status";

const KB_SIDEBAR_OPEN_KEY = "kb.chat.sidebarOpen";

function deriveContextPathFromPathname(pathname: string): string | null {
  if (!pathname.startsWith("/dashboard/kb/")) return null;
  if (pathname === "/dashboard/kb" || pathname === "/dashboard/kb/") return null;
  const rel = decodeURIComponent(pathname.slice("/dashboard/kb/".length));
  return rel ? `knowledge-base/${rel}` : null;
}

export interface UseKbLayoutStateResult {
  // Context values
  ctxValue: KbContextValue;
  chatCtxValue: KbChatContextValue;
  // Viewport + routing
  isDesktop: boolean;
  isContentView: boolean;
  pathname: string;
  // Layout state
  loading: boolean;
  error: KbContextValue["error"];
  hasTreeContent: boolean;
  kbCollapsed: boolean;
  toggleKbCollapsed: () => void;
  // Chat state
  contextPath: string | null;
  showChat: boolean;
  openSidebar: () => void;
  closeSidebar: () => void;
  // Chat panel ref — owned here so the toggle + resize closures share
  // identity with the render side. The file-tree sidebar is no longer a
  // Panel (it's a CSS-transitioning <aside>), so only the chat panel
  // needs an imperative handle.
  chatPanelRef: ReturnType<typeof usePanelRef>;
}

export function useKbLayoutState(): UseKbLayoutStateResult {
  const pathname = usePathname();
  const router = useRouter();
  const isDesktop = useMediaQuery("(min-width: 768px)");
  const chatPanelRef = usePanelRef();
  const [kbCollapsed, setKbCollapsed] = useState(false);
  const [tree, setTree] = useState<TreeNode | null>(null);
  const [lastSync, setLastSync] = useState<KbSyncHistoryRow | null>(null);
  const [needsReconnect, setNeedsReconnect] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<KbContextValue["error"]>(null);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  // Runtime feature flag — hydrated server-side via FeatureFlagProvider in
  // app/layout.tsx (ADR-038 v2). No client fetch round-trip.
  const kbChatFlag = useFeatureFlag("kb-chat-sidebar");

  const fetchTree = useCallback(
    async (signal?: AbortSignal) => {
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
        // #4224 — server tucks the latest kb_sync_history row alongside.
        // Cached on the layout state; refetched on KbSyncStatus's Sync-now
        // resolution via refreshTree (the same fetchTree callback).
        setLastSync((data.lastSync as KbSyncHistoryRow | null) ?? null);
        // #4712 — server-derived reconnect signal; refreshTree re-fetches and
        // re-derives this to false after a successful reconnect.
        setNeedsReconnect(data.needsReconnect === true);
        setLoading(false);
      } catch {
        if (!signal?.aborted) {
          setError("unknown");
          setLoading(false);
        }
      }
    },
    [router],
  );

  useEffect(() => {
    const controller = new AbortController();
    fetchTree(controller.signal);
    return () => {
      controller.abort();
    };
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
    const relativePath = decodeURIComponent(
      pathname.slice("/dashboard/kb/".length),
    );
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

  const toggleKbCollapsed = useCallback(() => {
    setKbCollapsed((prev) => !prev);
  }, []);

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
  const hasTreeContent = !!(tree?.children && tree.children.length > 0);

  const ctxValue: KbContextValue = useMemo(
    () => ({
      tree,
      loading,
      error,
      expanded,
      toggleExpanded,
      refreshTree: fetchTree,
      lastSync,
      needsReconnect,
    }),
    [
      tree,
      lastSync,
      needsReconnect,
      loading,
      error,
      expanded,
      toggleExpanded,
      fetchTree,
    ],
  );

  // --- Chat sidebar state -------------------------------------------------
  const contextPath = useMemo(
    () => deriveContextPathFromPathname(pathname),
    [pathname],
  );
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [messageCount, setMessageCount] = useState(0);

  // Restore sidebarOpen from sessionStorage on mount (per-tab persistence)
  useEffect(() => {
    if (!kbChatFlag) return;
    if (safeSession(KB_SIDEBAR_OPEN_KEY) === "1") setSidebarOpen(true);
  }, [kbChatFlag]);

  const openSidebar = useCallback(() => {
    setSidebarOpen(true);
    safeSession(KB_SIDEBAR_OPEN_KEY, "1");
  }, []);

  const closeSidebar = useCallback(() => {
    setSidebarOpen(false);
    safeSession(KB_SIDEBAR_OPEN_KEY, "0");
  }, []);

  // Close the chat panel when the user navigates to a different document.
  // The chat conversation is bound to a specific contextPath; leaving the
  // panel open while the viewer loads a new document would display stale
  // conversation content. Users can re-open the panel for the current
  // document via the "Continue thread" button in the toolbar.
  const prevContextPathRef = useRef<string | null>(contextPath);
  useEffect(() => {
    if (prevContextPathRef.current === contextPath) return;
    prevContextPathRef.current = contextPath;
    closeSidebar();
  }, [contextPath, closeSidebar]);

  // Prefetch message count for the current document so the toolbar trigger
  // shows "Continue thread" vs "Ask about this document" accurately even
  // while the chat panel is closed. Without this, messageCount stays stale
  // from the previously-mounted ChatSurface.
  useEffect(() => {
    if (!kbChatFlag) return;
    if (!contextPath) {
      setMessageCount(0);
      return;
    }
    setMessageCount(0);
    const controller = new AbortController();
    fetch(
      `/api/chat/thread-info?contextPath=${encodeURIComponent(contextPath)}`,
      {
        signal: controller.signal,
      },
    )
      .then((r) => (r.ok ? r.json() : null))
      .then((data: { messageCount?: number } | null) => {
        // Rapid navigation can resolve a stale response after cleanup; guard
        // against updating state on an aborted request.
        if (controller.signal.aborted) return;
        if (data && typeof data.messageCount === "number") {
          setMessageCount(data.messageCount);
        }
      })
      .catch(() => {
        /* abort or network error — label stays at default */
      });
    return () => controller.abort();
  }, [contextPath, kbChatFlag]);

  const chatCtxValue: KbChatContextValue = useMemo(
    () => ({
      open: sidebarOpen,
      openSidebar,
      closeSidebar,
      contextPath,
      enabled: kbChatFlag,
      messageCount,
      setMessageCount,
    }),
    [
      sidebarOpen,
      openSidebar,
      closeSidebar,
      contextPath,
      kbChatFlag,
      messageCount,
    ],
  );

  // Whether to show the chat panel as a resizable column on desktop.
  // sidebarOpen is user-controlled: clicking X (`closeSidebar`) sets it false
  // and unmounts the chat Panel; "Continue thread" (`openSidebar`) re-opens it.
  const showChat = kbChatFlag && !!contextPath && sidebarOpen;

  return {
    ctxValue,
    chatCtxValue,
    isDesktop,
    isContentView,
    pathname,
    loading,
    error,
    hasTreeContent,
    kbCollapsed,
    toggleKbCollapsed,
    contextPath,
    showChat,
    openSidebar,
    closeSidebar,
    chatPanelRef,
  };
}
