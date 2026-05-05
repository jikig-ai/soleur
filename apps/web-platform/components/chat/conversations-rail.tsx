"use client";

import { memo, useEffect } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useConversations } from "@/hooks/use-conversations";
import { useSidebarCollapse } from "@/hooks/use-sidebar-collapse";
import { relativeTime } from "@/lib/relative-time";
import { LEADER_COLORS } from "@/components/chat/leader-colors";
import type { ConversationStatus } from "@/lib/types";
import type { ConversationWithPreview } from "@/hooks/use-conversations";

const COLLAPSE_KEY = "soleur:sidebar.chat-rail.collapsed";
const RAIL_LIMIT = 15;
// Hoisted to module scope so re-renders pass the SAME options object
// reference to useConversations — a literal `{ limit: RAIL_LIMIT }` per
// render would be safe today (the hook destructures primitives) but is
// fragile to any future hook change that depends on options identity.
const RAIL_OPTIONS = { limit: RAIL_LIMIT } as const;

// Founder-language labels intentionally diverge from `STATUS_LABELS` in
// `lib/types.ts` ("Executing"/"Completed" → "In progress"/"Done"). Do
// NOT consolidate: the rail surfaces a switcher UI for the user, while
// `STATUS_LABELS` is the ops-language used by the Command Center status
// dropdown. Same enum, two distinct user-facing surfaces.
const RAIL_STATUS_LABEL: Record<ConversationStatus, string> = {
  waiting_for_user: "Needs your decision",
  active: "In progress",
  completed: "Done",
  failed: "Needs attention",
};

const RAIL_STATUS_BADGE: Record<ConversationStatus, { dot: string; text: string; bg: string }> = {
  waiting_for_user: { dot: "bg-amber-500", text: "text-amber-500", bg: "bg-amber-500/10" },
  active: { dot: "bg-blue-500", text: "text-blue-500", bg: "bg-blue-500/10" },
  completed: { dot: "bg-green-500", text: "text-green-500", bg: "bg-green-500/10" },
  failed: { dot: "bg-red-500", text: "text-red-500", bg: "bg-red-500/10" },
};

function StatusBadge({ status }: { status: ConversationStatus }) {
  const s = RAIL_STATUS_BADGE[status];
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[10px] font-medium ${s.bg} ${s.text}`}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${s.dot}`} />
      {RAIL_STATUS_LABEL[status]}
    </span>
  );
}

function ConversationRailRowImpl({
  conversation,
  active,
}: {
  conversation: ConversationWithPreview;
  active: boolean;
}) {
  const leader = conversation.domain_leader;
  const borderColor = leader && LEADER_COLORS[leader]
    ? LEADER_COLORS[leader]
    : "border-l-transparent";
  return (
    <Link
      href={`/dashboard/chat/${conversation.id}`}
      aria-current={active ? "page" : undefined}
      className={`block border-l-2 ${borderColor} px-3 py-2 transition-colors ${
        active
          ? "bg-neutral-800/60 text-white"
          : "text-neutral-300 hover:bg-neutral-900"
      }`}
    >
      <div className="truncate text-sm font-medium">{conversation.title}</div>
      <div className="mt-1 flex items-center justify-between gap-2 text-[11px] text-neutral-500">
        <StatusBadge status={conversation.status} />
        <span>{relativeTime(conversation.last_active)}</span>
      </div>
    </Link>
  );
}

// Memo on (conversation, active): only the row whose `active` flips
// re-renders when useParams emits a new conversationId — the other
// 14 rows skip reconciliation.
export const ConversationRailRow = memo(ConversationRailRowImpl);

export function ConversationsRail() {
  const { conversations, loading } = useConversations(RAIL_OPTIONS);
  const params = useParams<{ conversationId: string }>();
  const activeId = params?.conversationId;
  const [collapsed, toggle] = useSidebarCollapse(COLLAPSE_KEY);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "b") {
        e.preventDefault();
        toggle();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [toggle]);

  if (collapsed) {
    return (
      <div className="flex h-full flex-col items-center py-2">
        <button
          type="button"
          aria-label="Expand conversations rail"
          onClick={toggle}
          className="rounded p-2 text-neutral-400 hover:bg-neutral-800 hover:text-neutral-100"
        >
          ›
        </button>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center justify-between border-b border-neutral-800 px-3 py-2">
        <span className="text-xs font-semibold uppercase tracking-wide text-neutral-500">
          Recent conversations
        </span>
        <button
          type="button"
          aria-label="Collapse conversations rail"
          onClick={toggle}
          className="rounded p-1 text-neutral-500 hover:bg-neutral-800 hover:text-neutral-100"
        >
          ‹
        </button>
      </div>

      <nav className="min-h-0 flex-1 overflow-y-auto py-1">
        {!loading && conversations.length === 0 ? (
          <Link
            href="/dashboard/chat/new"
            className="block px-3 py-3 text-sm text-blue-400 hover:bg-neutral-900"
          >
            + New conversation
          </Link>
        ) : (
          conversations.map((conv) => (
            <ConversationRailRow
              key={conv.id}
              conversation={conv}
              active={conv.id === activeId}
            />
          ))
        )}
      </nav>

      <div className="border-t border-neutral-800 px-3 py-2">
        <Link
          href="/dashboard"
          className="text-xs text-neutral-400 hover:text-neutral-100"
        >
          View all in Dashboard
        </Link>
      </div>
    </div>
  );
}
