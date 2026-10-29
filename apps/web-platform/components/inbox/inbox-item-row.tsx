"use client";

// Native operational-inbox row (feat-severity-ranked-inbox #6007) — renders an
// inbox_item (task_completed / system today). Companion to EmailTriageRow, which
// keeps rendering the email-triage rows in the merged surface.
//
// INVARIANT — plain-text rendering. `title` is server-generated, but it renders
// as a plain React text node (sanitized, defense-in-depth): never markdown,
// never dangerouslySetInnerHTML, never an <a>/href built from row content. The
// ONLY navigation is a router push to the deep link BUILT AT RENDER from
// source_ref ids (buildInboxDeepLink) — never a stored URL. When the target
// doesn't exist yet (a source whose child hasn't shipped) or the ref is missing,
// the row renders NON-NAVIGATING rather than dead-ending on a 404.

import { useState } from "react";
import { usePendingRouter } from "@/hooks/use-pending-router";
import { usePendingAction } from "@/hooks/use-pending-action";
import { Button } from "@/components/ui/button";
import { sanitizeDisplayString } from "@/lib/sanitize-display";
import { revealInvisible } from "@/lib/approval-card-state";
import { inboxRowEligibility } from "@/lib/inbox-archive-eligibility";
import { relativeTime } from "@/lib/relative-time";
import { APPROVAL_COPY, formatExpiry } from "@/lib/approval-copy";
import {
  buildInboxDeepLink,
  type InboxItemRowData,
  type InboxItemSeverity,
} from "@/lib/inbox-severity";

interface InboxItemRowProps {
  item: InboxItemRowData;
  /** Called after a successful act/archive — the surface refetches. */
  onChanged?: () => void;
}

const DOT_CLASS: Record<InboxItemSeverity, string> = {
  action_required: "bg-red-500",
  attention: "bg-amber-500",
  info: "bg-soleur-text-muted",
};

const CONTAINER_CLASS: Record<InboxItemSeverity, string> = {
  action_required: "border-red-500/30 bg-red-500/[0.06] hover:bg-red-500/[0.1]",
  attention: "border-amber-500/30 bg-amber-500/[0.06] hover:bg-amber-500/[0.1]",
  info: "border-soleur-border-default bg-soleur-bg-surface-1/50 hover:bg-soleur-bg-surface-2/50",
};

export function InboxItemRow({ item, onChanged }: InboxItemRowProps) {
  const router = usePendingRouter();
  const [confirming, setConfirming] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  // An approval row names the agent's action: invisible direction/zero-width controls are made visible BEFORE the
  // sanitizer (which would drop them silently), so a right-to-left override cannot disguise a recipient.
  // An approval title is also exempt from the sanitizer's 200-character cap: the row names the action in full, so a
  // cap would silently cut the very value (a long recipient or branch) the Owner is checking.
  const title =
    item.source === "approval_required"
      ? sanitizeDisplayString(revealInvisible(item.title), Number.POSITIVE_INFINITY)
      : sanitizeDisplayString(item.title);
  const severity = item.severity;
  const isActionRequired = severity === "action_required";
  const isActed = item.acted_at !== null;
  const isArchived = item.status === "archived";
  // An action_required item must be acted before it can be archived (mirrors
  // the RPC archive-guard — a misclick must never lose a decision).
  // Shared predicate (lib/inbox-archive-eligibility) — the SAME rule the
  // bulk-archive checkbox + server classifier use: archive-guard applies
  // only to un-acted action_required rows.
  const canArchive =
    inboxRowEligibility({
      severity: item.severity,
      acted_at: item.acted_at,
      status: item.status,
    }) === "ok";

  const href = buildInboxDeepLink(item.source, item.source_ref);
  const navigable = href !== null && !isArchived;

  // #4672 — an approval row opens the request (the card decides; the row never carries Approve or Deny, because deciding
  // without the full action in view is the failure this surface exists to prevent). While un-acted it can be neither
  // marked done nor archived: it leaves NEEDS YOU only when decided or expired.
  const isApproval = item.source === "approval_required";
  const approvalPending = isApproval && item.approval?.status === "pending";
  const expiry = approvalPending && item.approval ? formatExpiry(item.approval.expiresAt, Date.now()) : null;
  const resolvedLine =
    isApproval && item.approval && (item.approval.status === "expired" || item.approval.status === "rejected")
      ? APPROVAL_COPY.resolvedNothing
      : null;
  const lockedApproval = isApproval && isActionRequired && !isActed;

  const { run: runAction, pending } = usePendingAction(
    async (action: "acted" | "archived") => {
      setActionError(null);
      try {
        const res = await fetch(`/api/inbox/${item.id}/state`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ action }),
        });
        if (res.ok || res.status === 409) {
          // 409 = the row already transitioned elsewhere; the refetch reconciles.
          onChanged?.();
          setConfirming(false);
        } else {
          setActionError(
            action === "acted" ? "Couldn't update — try again." : "Couldn't archive — try again.",
          );
        }
      } catch {
        setActionError("Network error — try again.");
      }
    },
  );

  const navigate = () => {
    if (!navigable || !href) return;
    // Opening an unread item clears its FYI gold-dot (marks read). Fire-and-
    // forget + idempotent (read_at is set-once in the RPC); guarded on unread so
    // a re-open is not a needless write. onChanged refreshes the shared SWR feed
    // (list + nav badge) so the dot clears immediately.
    if (item.read_at === null && !isArchived) {
      void fetch(`/api/inbox/${item.id}/state`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action: "read" }),
      })
        .then(() => onChanged?.())
        .catch(() => {});
    }
    router.push(href);
  };

  return (
    <div
      role={navigable ? "button" : undefined}
      tabIndex={navigable ? 0 : undefined}
      onClick={navigable ? navigate : undefined}
      onKeyDown={
        navigable
          ? (e) => {
              // Only the row itself navigates — a bubbled keydown from a
              // focused inner control (Mark done / Archive) must not.
              if (e.target !== e.currentTarget) return;
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                navigate();
              }
            }
          : undefined
      }
      className={`flex w-full min-h-[44px] items-start gap-3 rounded-lg border p-3 text-left transition-colors md:gap-4 md:p-4 ${
        navigable ? "cursor-pointer" : "cursor-default"
      } ${CONTAINER_CLASS[severity]}`}
    >
      {/* Severity dot — the calm, business-language signal (not a status column). */}
      <span
        aria-hidden="true"
        className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${DOT_CLASS[severity]}`}
      />

      <div className="flex w-full flex-col gap-1.5">
        <div className="flex items-center justify-between gap-2">
          <p className="min-w-0 text-sm font-medium text-soleur-text-primary [overflow-wrap:anywhere]">{title}</p>
          <span className="shrink-0 text-xs tabular-nums text-soleur-text-muted">
            {relativeTime(item.created_at)}
          </span>
        </div>

        {isApproval && !isArchived && (expiry || resolvedLine || approvalPending) && (
          <div className="flex flex-wrap items-center gap-2 text-xs text-soleur-text-secondary">
            {expiry && expiry.text && (
              <span
                data-testid="approval-row-expiry"
                suppressHydrationWarning
                className={`rounded-md bg-soleur-bg-surface-2/70 px-2 py-0.5 font-medium ${
                  expiry.urgent ? "text-amber-400" : "text-soleur-accent-gold-text"
                }`}
              >
                {expiry.text}
              </span>
            )}
            <span>{resolvedLine ?? "Open to see the exact action and decide"}</span>
          </div>
        )}

        {!navigable && !isArchived && !isApproval && (
          <p className="text-xs text-soleur-text-muted">
            Nothing to open yet — this is just an update.
          </p>
        )}

        {!isArchived && !lockedApproval && (
          <div className="flex items-center justify-end gap-2">
            {actionError && (
              <p role="alert" className="text-xs font-medium text-red-500">
                {actionError}
              </p>
            )}

            {isActionRequired && !isActed && (
              <Button
                variant="danger"
                type="button"
                aria-label="Mark done"
                disabled={pending}
                loading={pending}
                onClick={(e) => {
                  e.stopPropagation();
                  runAction("acted");
                }}
                className="min-h-[32px] rounded-md border border-red-500/30 px-3 py-1 text-xs font-medium text-red-500 transition-colors hover:bg-red-500/10 disabled:opacity-50"
              >
                Mark done
              </Button>
            )}

            {confirming ? (
              <span className="inline-flex items-center gap-2">
                <span className="text-xs text-soleur-text-secondary">Archive this?</span>
                <Button
                  variant="outlined"
                  type="button"
                  aria-label="Confirm archive"
                  disabled={pending}
                  loading={pending}
                  onClick={(e) => {
                    e.stopPropagation();
                    runAction("archived");
                  }}
                  className="min-h-[32px] rounded-md border border-soleur-border-default px-3 py-1 text-xs font-medium text-soleur-text-primary transition-colors hover:bg-soleur-bg-surface-2 disabled:opacity-50"
                >
                  Confirm
                </Button>
                <Button
                  variant="ghost"
                  type="button"
                  aria-label="Cancel archive"
                  disabled={pending}
                  onClick={(e) => {
                    e.stopPropagation();
                    setConfirming(false);
                  }}
                  className="min-h-[32px] rounded-md px-2 py-1 text-xs text-soleur-text-secondary hover:text-soleur-text-primary disabled:opacity-50"
                >
                  Cancel
                </Button>
              </span>
            ) : (
              <Button
                variant="outlined"
                type="button"
                aria-label="Archive item"
                // Guard: an un-acted action_required item cannot be archived
                // until it is marked done (a misclick must not lose a decision).
                disabled={pending || !canArchive}
                loading={pending}
                title={
                  !canArchive ? "Mark it done before archiving" : undefined
                }
                onClick={(e) => {
                  e.stopPropagation();
                  if (!canArchive) return;
                  // action_required archives always confirm; low-severity is direct.
                  if (isActionRequired) setConfirming(true);
                  else runAction("archived");
                }}
                className="min-h-[32px] rounded-md border border-soleur-border-default px-3 py-1 text-xs font-medium text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 disabled:opacity-50"
              >
                Archive
              </Button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
