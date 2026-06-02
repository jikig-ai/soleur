"use client";

import { FileTree } from "@/components/kb/file-tree";
import { SearchOverlay } from "@/components/kb/search-overlay";
import { useKb } from "@/components/kb/kb-context";
import { RailEmptyState } from "@/components/dashboard/rail-empty-state";

interface KbSidebarShellProps {
  /**
   * Optional click-collapse handler. Under the single nav rail (ADR-047) the
   * tree lives in the unified rail and collapse is owned by the rail itself
   * (⌘B / the band's controls), so the shell renders no collapse button when
   * this is omitted.
   */
  onCollapse?: () => void;
}

/**
 * KB file-tree sidebar shell — search overlay + the file tree. Pure
 * presentation; state lives in `useKbLayoutState`. The section title
 * ("Knowledge Base") now lives in the persistent context band, not here.
 */
export function KbSidebarShell({ onCollapse }: KbSidebarShellProps) {
  const { tree, loading } = useKb();
  // RQ5 / AC6: never a blank KB rail. Once loaded with no docs, show a labeled
  // CTA in place of the (null-rendering) empty FileTree.
  const isEmpty = !loading && !tree?.children?.length;

  return (
    <div className="flex h-full flex-col">
      {onCollapse && (
        <header className="flex min-h-7 shrink-0 items-center justify-end px-4 py-3">
          <button
            onClick={onCollapse}
            aria-label="Collapse file tree"
            title="Collapse file tree (⌘B)"
            className="hidden md:flex h-6 w-6 items-center justify-center rounded text-soleur-text-secondary hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
          >
            <svg
              className="h-4 w-4"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              strokeWidth={1.5}
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d="M15.75 19.5 8.25 12l7.5-7.5"
              />
            </svg>
          </button>
        </header>
      )}
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
    </div>
  );
}
