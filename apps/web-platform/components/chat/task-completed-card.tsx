"use client";

import { useEffect } from "react";
import { useSWRConfig } from "swr";
import { swrKeys } from "@/lib/swr-config";
import { sanitizeDisplayString } from "@/lib/sanitize-display";
import { warnSilentFallback } from "@/lib/client-observability";

/**
 * feat-session-completion-inline — the inline per-request completion card.
 *
 * Renders inside the viewed conversation when the server emits the
 * `task_completed` frame (server/notifications.ts `notifyTaskCompleted` — the
 * shared seam both turn-boundary lineages call). The matching inbox_item row
 * stays the durable record.
 *
 * The read-mark fires from this component's mount effect — "read" therefore
 * genuinely implies the card committed to the tree (a dispatch racing an
 * unmount leaves an honest unread row + badge). `read_at` is set-once
 * server-side (mig 122 `set_inbox_item_state`), so a remount double-fire is a
 * no-op. On success the shared `/api/inbox` key revalidates so the inbox
 * surface + nav badge reconcile (ADR-067). A failed mark leaves the row
 * unread — over-notify — and the failure itself is mirrored.
 *
 * Residual: mount ≠ in-view — a card mounting below the fold while the
 * operator is scrolled up still marks the row read (painted ≠ viewed). Same
 * accepted-residual class as the mounted-but-backgrounded tab documented at
 * session-registry `isConversationViewed`; viewport-anchoring via an
 * IntersectionObserver is the upgrade path if ever required.
 *
 * SECURITY: the title renders through `sanitizeDisplayString` (the
 * InboxItemRow invariant — bidi/control strip + 200-char cap) as a plain
 * React text node — never markdown, never dangerouslySetInnerHTML. It is
 * server-generated (never agent output, ADR-085), so this is
 * defense-in-depth, not trust.
 *
 * Non-navigating by design: the operator is already inside the target
 * conversation — a deep link to it would dead-end on the same view.
 */
export function TaskCompletedCard({
  title,
  inboxItemId,
}: {
  title: string;
  inboxItemId: string;
}) {
  const { mutate: globalMutate } = useSWRConfig();

  useEffect(() => {
    void fetch(`/api/inbox/${inboxItemId}/state`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ action: "read" }),
    })
      .then((res) => {
        if (res.ok) {
          void globalMutate(swrKeys.inbox("active"));
        } else {
          warnSilentFallback(null, {
            feature: "task-completed-card",
            op: "task-completed-mark-read",
            message: "task_completed read-mark POST returned non-ok",
            extra: { status: res.status },
          });
        }
      })
      .catch((err) => {
        warnSilentFallback(err, {
          feature: "task-completed-card",
          op: "task-completed-mark-read",
          message: "task_completed read-mark POST failed",
        });
      });
  }, [inboxItemId, globalMutate]);

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
          {sanitizeDisplayString(title)}
        </p>
        <p className="mt-0.5 text-xs text-soleur-text-muted">
          Also recorded in your inbox
        </p>
      </div>
    </div>
  );
}
