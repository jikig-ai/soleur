"use client";

import { useRouter } from "next/navigation";
import { STATUS_LABELS } from "@/lib/types";
import type { ConversationStatus } from "@/lib/types";
import type { ConversationWithPreview } from "@/hooks/use-conversations";
import { relativeTime } from "@/lib/relative-time";
import type { DomainLeaderId } from "@/server/domain-leaders";

function StatusBadge({ status }: { status: ConversationStatus }) {
  const label = STATUS_LABELS[status];

  const styles: Record<ConversationStatus, { dot: string; text: string; bg: string }> = {
    waiting_for_user: { dot: "bg-amber-500", text: "text-amber-500", bg: "bg-amber-500/10" },
    active: { dot: "bg-blue-500", text: "text-blue-500", bg: "bg-blue-500/10" },
    completed: { dot: "bg-green-500", text: "text-green-500", bg: "bg-green-500/10" },
    failed: { dot: "bg-red-500", text: "text-red-500", bg: "bg-red-500/10" },
  };

  const s = styles[status];

  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium ${s.bg} ${s.text}`}>
      <span className={`h-1.5 w-1.5 rounded-full ${s.dot}`} />
      {label}
    </span>
  );
}

function LeaderBadge({ leaderId }: { leaderId: DomainLeaderId }) {
  return (
    <span
      className="flex h-7 w-7 items-center justify-center overflow-hidden rounded-md md:h-8 md:w-8"
      aria-label={`Soleur ${leaderId.toUpperCase()}`}
    >
      <img
        src="/icons/soleur-logo-mark.png"
        alt=""
        width={28}
        height={28}
        className="h-full w-full object-cover"
      />
    </span>
  );
}

export function ConversationRow({ conversation }: { conversation: ConversationWithPreview }) {
  const router = useRouter();
  const isDecision = conversation.status === "waiting_for_user";
  const isCompleted = conversation.status === "completed";

  return (
    <button
      type="button"
      onClick={() => router.push(`/dashboard/chat/${conversation.id}`)}
      className={`flex w-full min-h-[44px] items-start gap-3 rounded-lg border p-3 text-left transition-colors md:items-center md:gap-4 md:p-4 ${
        isDecision
          ? "border-amber-500/20 bg-amber-500/[0.06] hover:bg-amber-500/[0.1]"
          : "border-neutral-800 bg-neutral-900/50 hover:bg-neutral-800/50"
      }`}
    >
      {/* Mobile: vertical stack */}
      <div className="flex flex-1 flex-col gap-1.5 md:hidden">
        <div className="flex items-center justify-between gap-2">
          <StatusBadge status={conversation.status} />
          <span className="text-xs text-neutral-500">
            {relativeTime(conversation.last_active)}
          </span>
        </div>
        <p className={`text-sm font-medium ${isCompleted ? "text-neutral-400" : "text-white"}`}>
          {conversation.title}
        </p>
        {conversation.preview && (
          <p className={`text-xs ${isCompleted ? "text-neutral-600" : "text-neutral-400"}`}>
            {conversation.preview}
          </p>
        )}
        {conversation.domain_leader && (
          <div className="flex items-center gap-1.5">
            <LeaderBadge leaderId={conversation.domain_leader} />
          </div>
        )}
      </div>

      {/* Desktop: horizontal row */}
      <div className="hidden w-full items-center gap-4 md:flex">
        <StatusBadge status={conversation.status} />
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <p className={`truncate text-sm font-medium ${isCompleted ? "text-neutral-400" : "text-white"}`}>
            {conversation.title}
          </p>
          {conversation.preview && (
            <p className={`truncate text-xs ${isCompleted ? "text-neutral-600" : "text-neutral-400"}`}>
              {conversation.preview}
            </p>
          )}
        </div>
        {conversation.domain_leader && (
          <LeaderBadge leaderId={conversation.domain_leader} />
        )}
        <span className="shrink-0 text-xs text-neutral-500">
          {relativeTime(conversation.last_active)}
        </span>
      </div>
    </button>
  );
}
