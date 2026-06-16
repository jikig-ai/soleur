"use client";

import { memo } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useConversations } from "@/hooks/use-conversations";
import { RailEmptyState } from "@/components/dashboard/rail-empty-state";
import { useRailCollapsed } from "@/components/dashboard/rail-slot";
import { relativeTime } from "@/lib/relative-time";
import { LEADER_COLORS } from "@/components/chat/leader-colors";
import type { ConversationStatus } from "@/lib/types";
import type { ConversationWithPreview } from "@/hooks/use-conversations";

const RAIL_LIMIT = 15;
// The canonical new-conversation entry point (resolves to
// chat/[conversationId]/page.tsx with id "new" → ChatSurface.startSession).
// Shared by BOTH the persistent header affordance and the empty-state CTA so
// the route cannot drift between the two (user-impact review FINDING 5).
const NEW_CONVERSATION_HREF = "/dashboard/chat/new";
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
          ? "bg-soleur-bg-surface-2 text-soleur-text-primary"
          : "text-soleur-text-secondary hover:bg-soleur-bg-surface-1"
      }`}
    >
      <div className="truncate text-sm font-medium">{conversation.title}</div>
      <div className="mt-1 flex items-center justify-between gap-2 text-[11px] text-soleur-text-muted">
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
  const { conversations, loading, error, refetch } = useConversations(RAIL_OPTIONS);
  const params = useParams<{ conversationId: string }>();
  const activeId = params?.conversationId;

  // ADR-047: the conversations rail lives in the single nav rail's slot now.
  // Collapse is owned by the unified rail (⌘B / the band) — no per-rail
  // collapse state or button here.
  //
  // Collapse fix: the rich rows (status badge + leader color + relative time)
  // have no coherent icon-only form at the 56px collapsed rail, so when
  // collapsed the rail content is DOM-removed (render-conditional). The stable
  // `data-testid="conversations-rail"` wrapper lives in conversations-rail-portal.tsx,
  // so present/absent assertions stay anchored across both toggle states.
  const collapsed = useRailCollapsed();
  if (collapsed) return null;

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center justify-between border-b border-soleur-border-default px-3 py-2">
        <span className="text-xs font-semibold uppercase tracking-wide text-soleur-text-muted">
          Recent conversations
        </span>
        {/* Persistent new-conversation entry point — visible regardless of
            list state (the empty-state CTA below only shows when zero rows).
            Expanded branch only: the collapsed rail returns null above. */}
        <Link
          href={NEW_CONVERSATION_HREF}
          aria-label="New conversation"
          className="text-xs font-medium text-soleur-accent-gold-fg hover:underline"
        >
          + New
        </Link>
      </div>

      <nav className="min-h-0 flex-1 overflow-y-auto py-1">
        {!loading && conversations.length === 0 && error ? (
          // Transient failure with no last-known conversations: surface a
          // distinct retryable error, NOT the "Start one" empty CTA — the
          // empty CTA reads as "you have no conversations" and is a lie when
          // the list simply failed to load (single-user-incident threshold).
          // When last-known conversations exist, they keep rendering (the
          // map branch below wins), so a failed refetch never blanks the rail.
          <div
            data-testid="conversations-rail-error"
            className="px-3 py-4 text-xs text-soleur-text-muted"
          >
            <p>Couldn&rsquo;t load conversations.</p>
            <button
              type="button"
              onClick={() => refetch()}
              className="mt-1 text-soleur-text-secondary underline hover:text-soleur-text-primary"
            >
              Retry
            </button>
          </div>
        ) : !loading && conversations.length === 0 ? (
          <RailEmptyState
            testId="conversations-rail-empty"
            message="No conversations yet."
            ctaLabel="Start one"
            ctaHref={NEW_CONVERSATION_HREF}
          />
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

      <div className="border-t border-soleur-border-default px-3 py-2">
        <Link
          href="/dashboard"
          className="text-xs text-soleur-text-secondary hover:text-soleur-text-primary"
        >
          View all in Dashboard
        </Link>
      </div>
    </div>
  );
}
