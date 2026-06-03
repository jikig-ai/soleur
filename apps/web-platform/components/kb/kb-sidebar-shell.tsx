"use client";

import { FileTree } from "@/components/kb/file-tree";
import { SearchOverlay } from "@/components/kb/search-overlay";
import { useKb } from "@/components/kb/kb-context";
import { KbSyncStatus } from "@/components/kb/kb-sync-status";
import { RailEmptyState } from "@/components/dashboard/rail-empty-state";

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
 */
export function KbSidebarShell() {
  const { tree, loading, lastSync, refreshTree } = useKb();
  // RQ5 / AC6: never a blank KB rail. Once loaded with no docs, show a labeled
  // CTA in place of the (null-rendering) empty FileTree.
  const isEmpty = !loading && !tree?.children?.length;

  return (
    <div className="flex h-full flex-col">
      <div className="shrink-0 px-3 pb-3 pt-3">
        <SearchOverlay />
      </div>
      <div className="flex-1 overflow-y-auto px-2 pb-4">
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
      {/* Sync affordance — pinned footer, rendered in ALL rail branches
          (populated + empty-tree) so the self-recovery path is always reachable
          (AC-A2). onSynced refetches the tree + lastSync via context. */}
      <div className="shrink-0 border-t border-soleur-border-default px-3 py-2">
        <KbSyncStatus lastSync={lastSync} onSynced={refreshTree} />
      </div>
    </div>
  );
}
