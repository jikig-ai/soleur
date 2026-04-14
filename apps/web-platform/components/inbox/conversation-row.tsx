"use client";

import { useRef, useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { STATUS_LABELS } from "@/lib/types";
import type { ConversationStatus } from "@/lib/types";
import type { ConversationWithPreview } from "@/hooks/use-conversations";
import { relativeTime } from "@/lib/relative-time";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { LeaderAvatar } from "@/components/leader-avatar";
import { useTeamNames } from "@/hooks/use-team-names";

const STATUS_ACTIONS: Partial<Record<ConversationStatus, { label: string; target: ConversationStatus }>> = {
  failed: { label: "Dismiss", target: "completed" },
  waiting_for_user: { label: "Mark resolved", target: "completed" },
};

const BADGE_STYLES: Record<ConversationStatus, { dot: string; text: string; bg: string }> = {
  waiting_for_user: { dot: "bg-amber-500", text: "text-amber-500", bg: "bg-amber-500/10" },
  active: { dot: "bg-blue-500", text: "text-blue-500", bg: "bg-blue-500/10" },
  completed: { dot: "bg-green-500", text: "text-green-500", bg: "bg-green-500/10" },
  failed: { dot: "bg-red-500", text: "text-red-500", bg: "bg-red-500/10" },
};

function StatusBadge({
  status,
  onAction,
}: {
  status: ConversationStatus;
  onAction?: (newStatus: ConversationStatus) => void;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const action = onAction ? STATUS_ACTIONS[status] : undefined;
  const interactive = !!action;

  useEffect(() => {
    if (!open) return;
    function handleClickOutside(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [open]);

  const label = STATUS_LABELS[status];

  const s = BADGE_STYLES[status];

  const badge = (
    <span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium ${s.bg} ${s.text}`}>
      <span className={`h-1.5 w-1.5 rounded-full ${s.dot}`} />
      {label}
    </span>
  );

  if (!interactive) return badge;

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        className="min-h-[44px] min-w-[44px] flex items-center cursor-pointer"
        aria-label={`Change status: ${label}`}
        onClick={(e) => {
          e.stopPropagation();
          setOpen((prev) => !prev);
        }}
      >
        {badge}
      </button>
      {open && (
        <div
          role="menu"
          className="absolute left-0 top-full z-50 mt-1 min-w-[160px] rounded-lg border border-neutral-700 bg-neutral-900 py-1 shadow-lg"
        >
          <button
            type="button"
            role="menuitem"
            className="flex w-full min-h-[44px] items-center gap-2 px-3 py-2 text-left text-sm text-neutral-200 hover:bg-neutral-800"
            onClick={(e) => {
              e.stopPropagation();
              onAction!(action!.target);
              setOpen(false);
            }}
          >
            <span className="flex h-4 w-4 items-center justify-center rounded-full border border-neutral-500 text-[10px] text-neutral-400">
              &#x2298;
            </span>
            <div>
              <div>{action!.label}</div>
              <div className="text-xs text-neutral-500">Move to completed</div>
            </div>
          </button>
        </div>
      )}
    </div>
  );
}


function ArchiveButton({
  isArchived,
  onArchive,
  onUnarchive,
}: {
  isArchived: boolean;
  onArchive: () => void;
  onUnarchive: () => void;
}) {
  return (
    <button
      type="button"
      aria-label={isArchived ? "Unarchive conversation" : "Archive conversation"}
      onClick={(e) => {
        e.stopPropagation();
        isArchived ? onUnarchive() : onArchive();
      }}
      className="flex h-7 w-7 shrink-0 items-center justify-center rounded-md text-neutral-500 transition-colors hover:bg-neutral-700 hover:text-neutral-300"
    >
      {isArchived ? (
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="h-4 w-4">
          <path fillRule="evenodd" d="M2 3a1 1 0 00-1 1v1a1 1 0 001 1h16a1 1 0 001-1V4a1 1 0 00-1-1H2zm14.5 4h-13v8a2 2 0 002 2h9a2 2 0 002-2V7zm-4.03 3.22a.75.75 0 010 1.06l-1.72 1.72h3.5a.75.75 0 010 1.5h-3.5l1.72 1.72a.75.75 0 11-1.06 1.06l-3-3a.75.75 0 010-1.06l3-3a.75.75 0 011.06 0z" clipRule="evenodd" />
        </svg>
      ) : (
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="h-4 w-4">
          <path d="M2 3a1 1 0 00-1 1v1a1 1 0 001 1h16a1 1 0 001-1V4a1 1 0 00-1-1H2z" />
          <path fillRule="evenodd" d="M2 7.5h16l-.811 7.71a2 2 0 01-1.99 1.79H4.802a2 2 0 01-1.99-1.79L2 7.5zM7 11a1 1 0 011-1h4a1 1 0 110 2H8a1 1 0 01-1-1z" clipRule="evenodd" />
        </svg>
      )}
    </button>
  );
}

interface ConversationRowProps {
  conversation: ConversationWithPreview;
  onArchive?: (id: string) => void;
  onUnarchive?: (id: string) => void;
  onStatusChange?: (conversationId: string, newStatus: ConversationStatus) => void;
}

export function ConversationRow({ conversation, onArchive, onUnarchive, onStatusChange }: ConversationRowProps) {
  const router = useRouter();
  const { getIconPath } = useTeamNames();
  const isDecision = conversation.status === "waiting_for_user";
  const isCompleted = conversation.status === "completed";
  const isArchived = conversation.archived_at !== null;

  const handleStatusAction = onStatusChange
    ? (newStatus: ConversationStatus) => onStatusChange(conversation.id, newStatus)
    : undefined;

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => router.push(`/dashboard/chat/${conversation.id}`)}
      onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); router.push(`/dashboard/chat/${conversation.id}`); } }}
      className={`flex w-full min-h-[44px] cursor-pointer items-start gap-3 rounded-lg border p-3 text-left transition-colors md:items-center md:gap-4 md:p-4 ${
        isDecision
          ? "border-amber-500/20 bg-amber-500/[0.06] hover:bg-amber-500/[0.1]"
          : "border-neutral-800 bg-neutral-900/50 hover:bg-neutral-800/50"
      } ${isArchived ? "opacity-60" : ""}`}
    >
      {/* Mobile: vertical stack */}
      <div className="flex flex-1 flex-col gap-1.5 md:hidden">
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <StatusBadge status={conversation.status} onAction={handleStatusAction} />
            {isArchived && (
              <span className="inline-flex items-center rounded-full bg-neutral-800 px-2 py-0.5 text-[10px] font-medium text-neutral-400">
                Archived
              </span>
            )}
          </div>
          <span className="text-xs text-neutral-500">
            {relativeTime(conversation.last_active)}
          </span>
        </div>
        <p className={`text-sm font-medium ${isCompleted || isArchived ? "text-neutral-400" : "text-white"}`}>
          {conversation.title}
        </p>
        {conversation.preview && (
          <p className={`text-xs ${isCompleted || isArchived ? "text-neutral-600" : "text-neutral-400"}`}>
            {conversation.preview}
          </p>
        )}
        <div className="flex items-center justify-between">
          {conversation.domain_leader && (
            <div className="flex items-center gap-1.5">
              <LeaderAvatar leaderId={conversation.domain_leader} size="md" customIconPath={getIconPath(conversation.domain_leader as DomainLeaderId)} />
            </div>
          )}
          {(onArchive || onUnarchive) && (
            <ArchiveButton
              isArchived={isArchived}
              onArchive={() => onArchive?.(conversation.id)}
              onUnarchive={() => onUnarchive?.(conversation.id)}
            />
          )}
        </div>
      </div>

      {/* Desktop: horizontal row */}
      <div className="hidden w-full items-center gap-4 md:flex">
        <StatusBadge status={conversation.status} onAction={handleStatusAction} />
        {isArchived && (
          <span className="inline-flex items-center rounded-full bg-neutral-800 px-2 py-0.5 text-[10px] font-medium text-neutral-400">
            Archived
          </span>
        )}
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <p className={`truncate text-sm font-medium ${isCompleted || isArchived ? "text-neutral-400" : "text-white"}`}>
            {conversation.title}
          </p>
          {conversation.preview && (
            <p className={`truncate text-xs ${isCompleted || isArchived ? "text-neutral-600" : "text-neutral-400"}`}>
              {conversation.preview}
            </p>
          )}
        </div>
        {conversation.domain_leader && (
          <LeaderAvatar leaderId={conversation.domain_leader} size="md" customIconPath={getIconPath(conversation.domain_leader as DomainLeaderId)} />
        )}
        <span className="shrink-0 text-xs text-neutral-500">
          {relativeTime(conversation.last_active)}
        </span>
        {(onArchive || onUnarchive) && (
          <ArchiveButton
            isArchived={isArchived}
            onArchive={() => onArchive?.(conversation.id)}
            onUnarchive={() => onUnarchive?.(conversation.id)}
          />
        )}
      </div>
    </div>
  );
}
