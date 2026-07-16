"use client";

import { useCallback, useEffect, useRef } from "react";
import { FileTree } from "@/components/kb/file-tree";
import { SearchOverlay } from "@/components/kb/search-overlay";
import { useKb } from "@/components/kb/kb-context";
import { KbSyncStatus } from "@/components/kb/kb-sync-status";
import { RailEmptyState } from "@/components/dashboard/rail-empty-state";
import { useRailCollapsed, RAIL_EXPAND_EVENT } from "@/components/dashboard/rail-slot";
import { useNavResume } from "@/hooks/use-nav-resume";

/**
 * KB file-tree sidebar shell — search overlay + the file tree. Pure
 * presentation; state lives in `useKbLayoutState`. The section title
 * ("Knowledge Base") now lives in the persistent context band, and collapse is
 * owned by the unified rail (⌘B), so this shell carries no collapse control.
 *
 * Fix A (kb-sync-affordance-reconcile): the manual "Sync now" affordance
 * (`KbSyncStatus`) is mounted in a fixed footer so it is reachable WITHOUT
 * opening a file and survives the empty-tree branch — the self-recovery valve
 * PR #4810's nav refactor removed (it previously lived ONLY in the file-open
 * `KbContentHeader`). Reads `lastSync` + `refreshTree` from the always-mounted
 * `useKb()` context — no new server route or prop plumbing.
 *
 * #4826: tree scrollport persists/restores scrollTop via useNavResume.
 */
export function KbSidebarShell() {
  const { tree, loading, lastSync, refreshTree } = useKb();
  // RQ5 / AC6: never a blank KB rail. Once loaded with no docs, show a labeled
  // CTA in place of the (null-rendering) empty FileTree.
  const isEmpty = !loading && !tree?.children?.length;
  // ADR-047 collapse fix: when the unified rail is collapsed the search overlay
  // + arbitrarily-nested file tree are DOM-removed (render-conditional, NOT
  // display:none) so deep rows cannot clip at the 56px collapsed rail. A nested
  // file tree has no coherent icon-only form, so it hides rather than condenses.
  // Sidebar-UX follow-up Issue 6: the collapsed rail used to render NOTHING here,
  // so it looked empty/broken. It now shows a compact icon-only affordance —
  // "Browse files" (expands the rail via the layout's RAIL_EXPAND_EVENT channel)
  // + "Refresh" (refetch the tree) — so the collapsed KB rail is meaningful, not
  // blank. NOTE: this is a tree REFRESH, not the repo "Sync now" (POST
  // /api/kb/sync) — that richer action with its in-flight + error states lives in
  // the expanded rail's KbSyncStatus, reachable once expanded. The stable
  // `kb-rail-tree` wrapper always renders to anchor present/absent assertions.
  const collapsed = useRailCollapsed();
  const { readScrollTop, writeScrollTop } = useNavResume();
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const restoredRef = useRef(false);
  const rafWriteRef = useRef<number | null>(null);

  const onScroll = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    if (rafWriteRef.current != null) return;
    rafWriteRef.current = window.requestAnimationFrame(() => {
      rafWriteRef.current = null;
      if (scrollRef.current) writeScrollTop(scrollRef.current.scrollTop);
    });
  }, [writeScrollTop]);

  // Restore scroll once after tree content is available (one-shot).
  useEffect(() => {
    if (collapsed || loading || isEmpty || restoredRef.current) return;
    const saved = readScrollTop();
    if (saved == null || saved <= 0) {
      restoredRef.current = true;
      return;
    }
    let cancelled = false;
    const apply = () => {
      if (cancelled) return;
      const el = scrollRef.current;
      if (!el) return;
      // Wait until the scrollport can actually scroll (content painted).
      if (el.scrollHeight <= el.clientHeight + 1) {
        window.requestAnimationFrame(apply);
        return;
      }
      el.scrollTop = saved;
      restoredRef.current = true;
    };
    window.requestAnimationFrame(() => window.requestAnimationFrame(apply));
    return () => {
      cancelled = true;
    };
  }, [collapsed, loading, isEmpty, readScrollTop, tree]);

  useEffect(() => {
    return () => {
      if (rafWriteRef.current != null) {
        window.cancelAnimationFrame(rafWriteRef.current);
      }
    };
  }, []);

  return (
    <div data-testid="kb-rail-tree" data-tour-id="action:kb-tree" className="flex h-full flex-col">
      {collapsed ? (
        <div className="flex flex-col items-center gap-1 px-1 py-3">
          <button
            type="button"
            data-testid="kb-rail-collapsed-expand"
            aria-label="Browse files"
            title="Browse files"
            onClick={() => window.dispatchEvent(new CustomEvent(RAIL_EXPAND_EVENT))}
            className="flex min-h-[44px] w-full items-center justify-center rounded-lg text-soleur-text-muted transition-colors hover:bg-soleur-bg-surface-2/60 hover:text-soleur-text-secondary"
          >
            <FilesIcon className="h-4 w-4 shrink-0" />
          </button>
          <button
            type="button"
            data-testid="kb-rail-collapsed-refresh"
            aria-label="Refresh file tree"
            title="Refresh file tree"
            onClick={() => refreshTree()}
            className="flex min-h-[44px] w-full items-center justify-center rounded-lg text-soleur-text-muted transition-colors hover:bg-soleur-bg-surface-2/60 hover:text-soleur-text-secondary"
          >
            <SyncIcon className="h-4 w-4 shrink-0" />
          </button>
        </div>
      ) : (
        <>
          <div className="shrink-0 px-3 pb-3 pt-3">
            <SearchOverlay />
          </div>
          <div
            ref={scrollRef}
            data-testid="kb-tree-scrollport"
            className="flex-1 overflow-y-auto px-2 pb-4"
            onScroll={onScroll}
          >
            {isEmpty ? (
              <RailEmptyState
                testId="kb-rail-empty"
                message="No documents yet."
                ctaLabel="Connect a repo or add docs"
                ctaHref="/dashboard/settings/services"
              />
            ) : (
              <FileTree />
            )}
          </div>
          {/* Sync affordance — pinned footer, rendered in ALL EXPANDED rail
              branches (populated + empty-tree) so the self-recovery path is
              reachable (Fix A / AC-A2). It lives INSIDE the !collapsed gate: at
              the 56px collapsed rail it would clip like the rest of the
              secondary nav, so it hides with it (reachable again on ⌘B expand).
              onSynced refetches the tree + lastSync via context. */}
          <div className="shrink-0 border-t border-soleur-border-default px-3 py-2">
            <KbSyncStatus lastSync={lastSync} onSynced={refreshTree} />
          </div>
        </>
      )}
    </div>
  );
}

/* Collapsed-rail glyphs (Sidebar-UX follow-up Issue 6). Decorative — the button
   owns the accessible name via aria-label/title — so they are aria-hidden.
   Stroke style matches the dashboard primary-nav icons. */
function FilesIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      aria-hidden="true"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z"
      />
    </svg>
  );
}

function SyncIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      aria-hidden="true"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M16.023 9.348h4.992V4.356M3.985 14.652H8.98v4.992M19.768 9.348a8.25 8.25 0 0 0-15.36-1.5m-.392 6.804a8.25 8.25 0 0 0 15.36 1.5"
      />
    </svg>
  );
}
