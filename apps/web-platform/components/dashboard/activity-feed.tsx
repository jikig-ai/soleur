"use client";

import { useWorkspaceActivity, type ActivityEvent } from "@/hooks/use-workspace-activity";
import { relativeTime } from "@/lib/relative-time";

const EVENT_LABELS: Record<string, string> = {
  member_join: "joined the workspace",
  member_leave: "left the workspace",
  conversation_shared: "shared a conversation",
};

function EventRow({ event }: { event: ActivityEvent }) {
  const label = EVENT_LABELS[event.event_type] ?? event.event_type;
  const actor = event.actor_user_id ? event.actor_user_id.slice(0, 8) : "Former member";

  return (
    <div className="flex items-start gap-3 border-b border-soleur-border-default px-4 py-3 last:border-b-0">
      <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-soleur-bg-surface-2 text-xs font-medium text-soleur-text-secondary">
        {actor.slice(0, 2).toUpperCase()}
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <p className="text-sm text-soleur-text-primary">
          <span className="font-medium">{actor}</span>{" "}
          <span className="text-soleur-text-secondary">{label}</span>
        </p>
        <span className="text-xs text-soleur-text-muted">
          {relativeTime(event.created_at)}
        </span>
      </div>
    </div>
  );
}

export function ActivityFeed() {
  const { events, loading, error, loadMore, hasMore } = useWorkspaceActivity();

  if (loading && events.length === 0) {
    return (
      <div className="py-8 text-center text-sm text-soleur-text-muted">
        Loading activity...
      </div>
    );
  }

  if (error) {
    return (
      <div className="py-8 text-center text-sm text-red-400">
        {error}
      </div>
    );
  }

  if (events.length === 0) {
    return (
      <div className="py-8 text-center text-sm text-soleur-text-muted">
        No activity yet. Activity will appear here when team members join or share conversations.
      </div>
    );
  }

  return (
    <div className="divide-y divide-soleur-border-default">
      {events.map((event) => (
        <EventRow key={event.id} event={event} />
      ))}
      {hasMore && (
        <button
          onClick={loadMore}
          disabled={loading}
          className="w-full py-3 text-center text-sm text-soleur-text-secondary hover:text-soleur-text-primary"
        >
          {loading ? "Loading..." : "Load more"}
        </button>
      )}
    </div>
  );
}
