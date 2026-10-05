"use client";

/**
 * feat-session-completion-inline — the inline per-request completion card.
 *
 * Renders inside the viewed conversation when the server emits the
 * `task_completed` frame (server/notifications.ts `notifyTaskCompleted` — the
 * shared seam both turn-boundary lineages call). The matching inbox_item row
 * stays the durable record; the client marks it `read` at render
 * (ws-client `case "task_completed"`), which is why a "also in your inbox"
 * affordance is NOT needed as a link — the row is already marked seen.
 *
 * SECURITY: `title` renders as a plain React text node — never markdown,
 * never dangerouslySetInnerHTML (the InboxItemRow invariant). It is
 * server-generated (never agent output, ADR-085), and React escaping keeps
 * any stray markup inert regardless.
 *
 * Non-navigating by design: the operator is already inside the target
 * conversation — a deep link to it would dead-end on the same view.
 */
export function TaskCompletedCard({ title }: { title: string }) {
  return (
    <div
      data-testid="task-completed"
      data-message-type="task_completed"
      className="flex items-start gap-2 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/40 px-4 py-3"
    >
      <span
        aria-hidden="true"
        className="mt-[7px] h-2 w-2 shrink-0 rounded-full bg-emerald-500"
      />
      <div className="min-w-0">
        <p className="whitespace-pre-wrap [overflow-wrap:anywhere] text-[15px] font-medium text-soleur-text-primary">
          {title}
        </p>
        <p className="mt-0.5 text-xs text-soleur-text-muted">
          Also recorded in your inbox
        </p>
      </div>
    </div>
  );
}
