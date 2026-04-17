"use client";

import Link from "next/link";
import { KbBreadcrumb } from "@/components/kb/kb-breadcrumb";
import { SharePopover } from "@/components/kb/share-popover";
import { KbChatTrigger } from "@/components/kb/kb-chat-trigger";

export type KbContentHeaderProps = {
  joinedPath: string;
  chatUrl: string;
  download?: { href: string; filename: string };
};

export function KbContentHeader({ joinedPath, chatUrl, download }: KbContentHeaderProps) {
  return (
    <header className="flex shrink-0 items-center justify-between border-b border-neutral-800 px-4 py-3 md:px-6">
      <div className="flex items-center gap-2">
        <Link
          href="/dashboard/kb"
          aria-label="Back to file tree"
          className="flex items-center text-neutral-400 hover:text-white md:hidden"
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
      </div>
      <div className="flex items-center gap-2">
        {download && (
          <a
            data-testid="kb-content-download"
            href={download.href}
            download={download.filename}
            aria-label={`Download ${download.filename}`}
            className="inline-flex items-center gap-1.5 rounded-lg border border-neutral-700 px-3 py-1.5 text-xs font-medium text-neutral-300 transition-colors hover:border-neutral-500 hover:text-white"
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
        <SharePopover documentPath={joinedPath} />
        <KbChatTrigger fallbackHref={chatUrl} />
      </div>
    </header>
  );
}
