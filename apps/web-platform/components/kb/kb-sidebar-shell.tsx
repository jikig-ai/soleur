"use client";

import { FileTree } from "@/components/kb/file-tree";
import { SearchOverlay } from "@/components/kb/search-overlay";

interface KbSidebarShellProps {
  onCollapse: () => void;
}

/**
 * KB file-tree sidebar shell — header with collapse button, search overlay,
 * and the file tree. Pure presentation; state lives in `useKbLayoutState`.
 */
export function KbSidebarShell({ onCollapse }: KbSidebarShellProps) {
  return (
    <div className="flex h-full flex-col">
      <header className="flex shrink-0 items-center justify-between px-4 pb-3 pt-4">
        <h1 className="font-serif text-lg font-medium tracking-tight text-soleur-text-primary">
          Knowledge Base
        </h1>
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
      <div className="shrink-0 px-3 pb-3">
        <SearchOverlay />
      </div>
      <div className="flex-1 overflow-y-auto px-2 pb-4">
        <FileTree />
      </div>
    </div>
  );
}
