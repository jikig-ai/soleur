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
import { useRouter } from "next/navigation";
import { sanitizeDisplayString } from "@/lib/sanitize-display";
import { relativeTime } from "@/lib/relative-time";
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
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const title = sanitizeDisplayString(item.title);
  const severity = item.severity;
  const isActionRequired = severity === "action_required";
  const isActed = item.acted_at !== null;
  const isArchived = item.status === "archived";
  // An action_required item must be acted before it can be archived (mirrors
  // the RPC archive-guard — a misclick must never lose a decision).
  const canArchive = !isActionRequired || isActed;

  const href = buildInboxDeepLink(item.source, item.source_ref);
  const navigable = href !== null && !isArchived;

  async function runAction(action: "acted" | "archived") {
    if (pending) return;
    setPending(true);
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
    } finally {
      setPending(false);
    }
  }

  const navigate = () => {
    if (navigable && href) router.push(href);
  };

  return (
    <div
      role={navigable ? "button" : undefined}
      tabIndex={navigable ? 0 : undefined}
      onClick={navigable ? navigate : undefined}
      onKeyDown={
        navigable
          ? (e) => {
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
          <p className="text-sm font-medium text-soleur-text-primary">{title}</p>
          <span className="shrink-0 text-xs tabular-nums text-soleur-text-muted">
            {relativeTime(item.created_at)}
          </span>
        </div>

        {!navigable && !isArchived && (
          <p className="text-xs text-soleur-text-muted">
            Nothing to open yet — this is just an update.
          </p>
        )}

        {!isArchived && (
          <div className="flex items-center justify-end gap-2">
            {actionError && (
              <p role="alert" className="text-xs font-medium text-red-500">
                {actionError}
              </p>
            )}

            {isActionRequired && !isActed && (
              <button
                type="button"
                aria-label="Mark done"
                disabled={pending}
                onClick={(e) => {
                  e.stopPropagation();
                  void runAction("acted");
                }}
                className="min-h-[32px] rounded-md border border-red-500/30 px-3 py-1 text-xs font-medium text-red-500 transition-colors hover:bg-red-500/10 disabled:opacity-50"
              >
                Mark done
              </button>
            )}

            {confirming ? (
              <span className="inline-flex items-center gap-2">
                <span className="text-xs text-soleur-text-secondary">Archive this?</span>
                <button
                  type="button"
                  aria-label="Confirm archive"
                  disabled={pending}
                  onClick={(e) => {
                    e.stopPropagation();
                    void runAction("archived");
                  }}
                  className="min-h-[32px] rounded-md border border-soleur-border-default px-3 py-1 text-xs font-medium text-soleur-text-primary transition-colors hover:bg-soleur-bg-surface-2 disabled:opacity-50"
                >
                  Confirm
                </button>
                <button
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
                </button>
              </span>
            ) : (
              <button
                type="button"
                aria-label="Archive item"
                // Guard: an un-acted action_required item cannot be archived
                // until it is marked done (a misclick must not lose a decision).
                disabled={pending || !canArchive}
                title={
                  !canArchive ? "Mark it done before archiving" : undefined
                }
                onClick={(e) => {
                  e.stopPropagation();
                  if (!canArchive) return;
                  // action_required archives always confirm; low-severity is direct.
                  if (isActionRequired) setConfirming(true);
                  else void runAction("archived");
                }}
                className="min-h-[32px] rounded-md border border-soleur-border-default px-3 py-1 text-xs font-medium text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 disabled:opacity-50"
              >
                Archive
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
