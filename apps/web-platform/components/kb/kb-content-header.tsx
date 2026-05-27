"use client";

import Link from "next/link";
import { KbBreadcrumb } from "@/components/kb/kb-breadcrumb";
import { SharePopover } from "@/components/kb/share-popover";
import { KbChatTrigger } from "@/components/kb/kb-chat-trigger";
import {
  KbSyncStatus,
  type KbSyncHistoryRow,
} from "@/components/kb/kb-sync-status";

export type KbContentHeaderProps = {
  joinedPath: string;
  chatUrl: string;
  download?: { href: string; filename: string };
  /** Latest entry from the operator's kb_sync_history JSONB. Pass null for
   *  never-synced operators. */
  lastSync?: KbSyncHistoryRow | null;
  /** Refetch hook invoked after a successful manual /api/kb/sync POST. */
  onSynced?: () => void;
  /** Uploader attribution label (e.g. user email prefix). Null for pre-existing files. */
  uploaderLabel?: string | null;
};

export function KbContentHeader({
  joinedPath,
  chatUrl,
  download,
  lastSync,
  onSynced,
  uploaderLabel,
}: KbContentHeaderProps) {
  return (
    <header className="flex shrink-0 items-center justify-between border-b border-soleur-border-default px-4 py-3 md:px-6">
      <div className="flex items-center gap-2">
        <Link
          href="/dashboard/kb"
          aria-label="Back to file tree"
          className="flex items-center text-soleur-text-secondary hover:text-soleur-text-primary md:hidden"
        >
          <svg
            width="20"
            height="20"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <polyline points="15 18 9 12 15 6" />
          </svg>
        </Link>
        <KbBreadcrumb path={joinedPath} />
        {uploaderLabel && (
          <span className="hidden items-center gap-1 text-xs text-soleur-text-muted md:inline-flex">
            <span className="inline-flex h-5 w-5 items-center justify-center rounded-full bg-soleur-bg-surface-2 text-[10px] font-medium">
              {uploaderLabel.slice(0, 2).toUpperCase()}
            </span>
            {uploaderLabel}
          </span>
        )}
      </div>
      <div className="flex items-center gap-2">
        {download && (
          <a
            data-testid="kb-content-download"
            href={download.href}
            download={download.filename}
            aria-label={`Download ${download.filename}`}
            className="inline-flex items-center gap-1.5 rounded-lg border border-soleur-border-default px-3 py-1.5 text-xs font-medium text-soleur-text-secondary transition-colors hover:border-soleur-border-emphasized hover:text-soleur-text-primary"
          >
            <svg
              width="14"
              height="14"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              className="shrink-0"
            >
              <path
                d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
              <polyline
                points="7 10 12 15 17 10"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
              <line
                x1="12"
                y1="15"
                x2="12"
                y2="3"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
            Download
          </a>
        )}
        {lastSync !== undefined && (
          <KbSyncStatus lastSync={lastSync} onSynced={onSynced} />
        )}
        <SharePopover documentPath={joinedPath} />
        <KbChatTrigger fallbackHref={chatUrl} />
      </div>
    </header>
  );
}
