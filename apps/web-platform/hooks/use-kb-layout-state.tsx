"use client";

import { useState, useEffect, useCallback, useMemo, useRef } from "react";
import { usePathname } from "next/navigation";
import { usePanelRef } from "react-resizable-panels";
import useSWR from "swr";
import { useMediaQuery } from "@/hooks/use-media-query";
import { useFeatureFlag } from "@/components/feature-flags/provider";
import { isRevocationBounce } from "@/lib/auth/revocation-bounce";
import type { KbContextValue } from "@/components/kb/kb-context";
import type { KbChatContextValue } from "@/components/kb/kb-chat-context";
import { safeSession } from "@/lib/safe-session";
import { getAncestorPaths } from "@/components/kb/get-ancestor-paths";
import type { TreeNode } from "@/server/kb-reader";
import { reportSilentFallback } from "@/lib/client-observability";
import { swrKeys } from "@/lib/swr-config";
import type { KbSyncHistoryRow } from "@/components/kb/kb-sync-status";

const KB_SIDEBAR_OPEN_KEY = "kb.chat.sidebarOpen";

interface KbTreeData {
  tree: TreeNode | null;
  lastSync: KbSyncHistoryRow | null;
  needsReconnect: boolean;
}

// Carries which render error a /api/kb/tree response maps to, so SWR's single
// `error` channel can reconstruct the original status-code → error-kind mapping
// (a 503 → "workspace-not-ready", 404 → "not-found", everything else →
// "unknown"). `kind: null` is the 401 case: the fetcher has already pushed to
// /login, so there is no error to render.
class KbTreeError extends Error {
  constructor(public kind: KbContextValue["error"]) {
    super(kind ?? "unauthorized");
    this.name = "KbTreeError";
  }
}

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
  const isDesktop = useMediaQuery("(min-width: 768px)");
  const chatPanelRef = usePanelRef();
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  // Runtime feature flag — hydrated server-side via FeatureFlagProvider in
  // app/layout.tsx (ADR-038 v2). No client fetch round-trip.
  const kbChatFlag = useFeatureFlag("kb-chat-sidebar");

  // ADR-067: the KB tree is cached under a stable key (swrKeys.kbTree), so
  // returning to the KB tab renders the last-known tree instantly and
  // revalidates quietly. The rich status-code → error-kind mapping is preserved
  // by throwing a typed KbTreeError (see below) that SWR surfaces via `error`.
  const fetchKbTree = useCallback(async (): Promise<KbTreeData> => {
    let res: Response;
    try {
      res = await fetch("/api/kb/tree");
    } catch (err) {
      // Network throw — mirror to Sentry (client) before degrading (#4712).
      reportSilentFallback(err, { feature: "kb-tree", op: "fetch-tree" });
      throw new KbTreeError("unknown");
    }
    // GAP F (ADR-067 staleTimes): revocation bounce — HARD-nav to wipe the
    // Router Cache. isRevocationBounce detects the direct 401 AND the #4307
    // middleware 302→/login (fetch follows the redirect to 200 HTML).
    if (isRevocationBounce(res)) {
      window.location.assign("/login");
      throw new KbTreeError(null);
    }
    if (res.status === 503) throw new KbTreeError("workspace-not-ready");
    if (res.status === 404) throw new KbTreeError("not-found");
    if (!res.ok) throw new KbTreeError("unknown");
    try {
      const data = await res.json();
      return {
        // #4224 — server tucks the latest kb_sync_history row alongside.
        // #4712 — server-derived reconnect signal; refreshTree re-derives it.
        tree: (data.tree as TreeNode | null) ?? null,
        lastSync: (data.lastSync as KbSyncHistoryRow | null) ?? null,
        needsReconnect: data.needsReconnect === true,
      };
    } catch (err) {
      // 200-with-malformed-body must not silently null needsReconnect (#4712).
      reportSilentFallback(err, { feature: "kb-tree", op: "fetch-tree" });
      throw new KbTreeError("unknown");
    }
  }, []);

  const {
    data: treeData,
    error: treeError,
    mutate: mutateTree,
  } = useSWR<KbTreeData, Error>(swrKeys.kbTree(), fetchKbTree);

  const tree = treeData?.tree ?? null;
  const lastSync = treeData?.lastSync ?? null;
  const needsReconnect = treeData?.needsReconnect ?? false;
  // First-load skeleton gates on absence of BOTH data and error (GAP F) — a
  // background revalidation of a warm cache keeps treeData defined, so the
  // skeleton never re-shows. The 401 case (KbTreeError kind===null) keeps
  // loading=true so the skeleton holds through the /login redirect rather than
  // flashing the empty/"no documents" state on the way out.
  const isRedirecting401 =
    treeError instanceof KbTreeError && treeError.kind === null;
  const loading =
    treeData === undefined && (treeError === undefined || isRedirecting401);
  const error: KbContextValue["error"] =
    treeError instanceof KbTreeError
      ? treeError.kind
      : treeError
        ? "unknown"
        : null;

  // refreshTree(): re-validate the cached tree. Used by KbSyncStatus's Sync-now
  // resolution and by ReconnectNotice after a successful reconnect (#4712).
  const refreshTree = useCallback(async () => {
    await mutateTree();
  }, [mutateTree]);

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

  // ⌘B and rail collapse are owned solely by (dashboard)/layout.tsx (AC5,
  // ADR-047). KB no longer has its own collapse axis — the tree lives in the
  // unified rail, which collapses as a whole.

  const isContentView = pathname !== "/dashboard/kb";
  const hasTreeContent = !!(tree?.children && tree.children.length > 0);

  const ctxValue: KbContextValue = useMemo(
    () => ({
      tree,
      loading,
      error,
      expanded,
      toggleExpanded,
      refreshTree,
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
      refreshTree,
    ],
  );

  // --- Chat sidebar state -------------------------------------------------
  const contextPath = useMemo(
    () => deriveContextPathFromPathname(pathname),
    [pathname],
  );
  const [sidebarOpen, setSidebarOpen] = useState(false);
  // Set by a document view that embeds its own Concierge (the C4 workspace) so
  // the side chat panel isn't double-mounted with the same contextPath.
  const [suppressSidebar, setSuppressSidebar] = useState(false);
  // Reveal state for an embedded Concierge (C4 workspace). DISTINCT from
  // sidebarOpen so the header trigger drives the C4 diagram-side panel without
  // re-mounting a second side-panel Concierge. Defaults open (parity with the
  // pre-lift local conciergeCollapsed=false initial state).
  const [embeddedConciergeOpen, setEmbeddedConciergeOpen] = useState(true);
  const revealEmbeddedConcierge = useCallback(
    () => setEmbeddedConciergeOpen(true),
    [],
  );
  const collapseEmbeddedConcierge = useCallback(
    () => setEmbeddedConciergeOpen(false),
    [],
  );

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
    // Re-open the embedded Concierge default for the new doc (mirrors the side
    // panel close-on-navigate; a fresh doc shows its Concierge by default).
    setEmbeddedConciergeOpen(true);
  }, [contextPath, closeSidebar]);

  // Prefetch message count for the current document so the toolbar trigger
  // shows "Continue thread" vs "Ask about this document" accurately even while
  // the chat panel is closed. ADR-067: cached per-contextPath (swrKeys
  // .chatThreadInfo), so revisiting a document shows its count instantly. SWR
  // skips the fetch when the key is null (no contextPath / flag off).
  const { data: threadInfo } = useSWR(
    kbChatFlag ? swrKeys.chatThreadInfo(contextPath) : null,
    async ([, cp]: readonly [string, string]) => {
      const r = await fetch(
        `/api/chat/thread-info?contextPath=${encodeURIComponent(cp)}`,
      );
      if (!r.ok) return { messageCount: 0 };
      const data = (await r.json()) as { messageCount?: number };
      return {
        messageCount:
          typeof data.messageCount === "number" ? data.messageCount : 0,
      };
    },
  );
  // The live ChatSurface owns the count once it mounts (it calls
  // setMessageCount as messages are sent); that live value takes precedence
  // over the prefetched cache. Reset to "defer to cache" on document change so
  // a new doc shows ITS cached count, not the previous doc's live count.
  const [liveCount, setLiveCount] = useState<number | null>(null);
  useEffect(() => {
    setLiveCount(null);
  }, [contextPath]);
  const messageCount = liveCount ?? threadInfo?.messageCount ?? 0;
  const setMessageCount = useCallback((n: number) => setLiveCount(n), []);

  const chatCtxValue: KbChatContextValue = useMemo(
    () => ({
      open: sidebarOpen,
      openSidebar,
      closeSidebar,
      contextPath,
      enabled: kbChatFlag,
      messageCount,
      setMessageCount,
      suppressSidebar,
      setSuppressSidebar,
      embeddedConciergeOpen,
      revealEmbeddedConcierge,
      collapseEmbeddedConcierge,
    }),
    [
      sidebarOpen,
      openSidebar,
      closeSidebar,
      contextPath,
      kbChatFlag,
      messageCount,
      suppressSidebar,
      embeddedConciergeOpen,
      revealEmbeddedConcierge,
      collapseEmbeddedConcierge,
    ],
  );

  // Whether to show the chat panel as a resizable column on desktop.
  // sidebarOpen is user-controlled: clicking X (`closeSidebar`) sets it false
  // and unmounts the chat Panel; "Continue thread" (`openSidebar`) re-opens it.
  // suppressSidebar wins: a view embedding its own Concierge (C4 workspace)
  // hides the side panel to avoid a double-mounted chat on the same doc.
  const showChat =
    kbChatFlag && !!contextPath && sidebarOpen && !suppressSidebar;

  return {
    ctxValue,
    chatCtxValue,
    isDesktop,
    isContentView,
    pathname,
    loading,
    error,
    hasTreeContent,
    contextPath,
    showChat,
    openSidebar,
    closeSidebar,
    chatPanelRef,
  };
}
