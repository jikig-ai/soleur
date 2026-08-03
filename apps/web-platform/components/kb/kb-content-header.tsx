"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { KbBreadcrumb } from "@/components/kb/kb-breadcrumb";
import { SharePopover } from "@/components/kb/share-popover";
import { KbChatTrigger } from "@/components/kb/kb-chat-trigger";
import { useIsMobile } from "@/hooks/use-is-mobile";
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
  const isMobile = useIsMobile();
  const [overflowOpen, setOverflowOpen] = useState(false);
  const overflowRef = useRef<HTMLDivElement | null>(null);
  const triggerRef = useRef<HTMLButtonElement | null>(null);

  const closeOverflow = useCallback(() => {
    setOverflowOpen(false);
    // Focus restore: without it, dismissing the menu drops the user at the top
    // of the document for keyboard/screen-reader navigation.
    triggerRef.current?.focus();
  }, []);

  // Escape + outside-pointerdown dismissal. SharePopover (which now lives
  // INSIDE this menu) implements neither — do not copy that gap forward.
  useEffect(() => {
    if (!overflowOpen) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") closeOverflow();
    };
    const onPointerDown = (e: Event) => {
      const el = overflowRef.current;
      if (el && !el.contains(e.target as Node)) setOverflowOpen(false);
    };
    document.addEventListener("keydown", onKeyDown);
    document.addEventListener("pointerdown", onPointerDown);
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.removeEventListener("pointerdown", onPointerDown);
    };
  }, [overflowOpen, closeOverflow]);

  // The viewport can change under an open menu (rotation, a desktop resize).
  // Leaving `overflowOpen` true would strand state the desktop branch cannot
  // reach — and re-open a stale menu on the way back.
  useEffect(() => {
    if (!isMobile) setOverflowOpen(false);
  }, [isMobile]);

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
        {/* DC3 (#7186): four trailing actions do not fit a 375px phone. Below
            `md` the secondary three move behind a `⋯` — nothing is dropped
            (Download is the only way to consume a non-markdown attachment on a
            phone, and silently losing Share is a capability regression).
            Gated in JS, not with `md:hidden` twins: SharePopover and
            KbSyncStatus own state and fetches, so a CSS dual-render would mount
            each twice. */}
        {isMobile ? (
          <>
            <KbChatTrigger fallbackHref={chatUrl} />
            <div className="relative" ref={overflowRef}>
              <button
                type="button"
                data-testid="kb-header-overflow-trigger"
                aria-label="More actions"
                aria-haspopup="menu"
                aria-expanded={overflowOpen}
                ref={triggerRef}
                onClick={() => setOverflowOpen((v) => !v)}
                className="flex h-11 w-11 items-center justify-center rounded-lg text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
              >
                <svg
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <circle cx="5" cy="12" r="1.75" />
                  <circle cx="12" cy="12" r="1.75" />
                  <circle cx="19" cy="12" r="1.75" />
                </svg>
              </button>
              {overflowOpen && (
                <div
                  role="menu"
                  aria-label="Document actions"
                  data-testid="kb-header-overflow-menu"
                  className="absolute right-0 top-full z-50 mt-2 flex w-56 flex-col gap-2 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-3 shadow-xl"
                >
                  {download && (
                    <a
                      data-testid="kb-content-download"
                      href={download.href}
                      download={download.filename}
                      aria-label={`Download ${download.filename}`}
                      className="inline-flex min-h-11 items-center gap-2 rounded-lg px-2 text-sm text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
                    >
                      Download
                    </a>
                  )}
                  {lastSync !== undefined && (
                    <KbSyncStatus lastSync={lastSync} onSynced={onSynced} />
                  )}
                  <SharePopover documentPath={joinedPath} />
                </div>
              )}
            </div>
          </>
        ) : (
          <>
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
          </>
        )}
      </div>
    </header>
  );
}
