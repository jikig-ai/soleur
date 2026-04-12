"use client";

import { useState, useEffect, useCallback, useMemo } from "react";
import type { ReactNode } from "react";
import { usePathname, useRouter } from "next/navigation";
import { KbContext } from "@/components/kb/kb-context";
import type { KbContextValue } from "@/components/kb/kb-context";
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

export default function KbLayout({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [tree, setTree] = useState<TreeNode | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<KbContextValue["error"]>(null);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

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

  // Full-width states: loading, errors, or empty KB (no sidebar needed)
  if (loading || error || (!loading && !hasTreeContent)) {
    return (
      <KbContext value={ctxValue}>
        {loading && <LoadingSkeleton />}
        {error === "workspace-not-ready" && <WorkspaceNotReady />}
        {error === "not-found" && <NoProjectState />}
        {error === "unknown" && <UnknownError />}
        {!loading && !error && !hasTreeContent && <EmptyState />}
      </KbContext>
    );
  }

  // Two-panel layout: tree sidebar + content area
  return (
    <KbContext value={ctxValue}>
      <div className="flex h-full">
        {/* Tree sidebar — visible on desktop always, on mobile only at root */}
        <aside
          className={`w-full shrink-0 overflow-y-auto border-r border-neutral-800 md:block md:w-64 ${
            isContentView ? "hidden" : "block"
          }`}
        >
          <div className="flex h-full flex-col">
            <header className="shrink-0 px-4 pb-3 pt-4">
              <h1 className="font-serif text-lg font-medium tracking-tight text-white">
                Knowledge Base
              </h1>
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
          <KbErrorBoundary>
            {isContentView ? children : <DesktopPlaceholder />}
          </KbErrorBoundary>
        </div>
      </div>
    </KbContext>
  );
}
